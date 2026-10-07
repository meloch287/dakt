import Foundation

extension WhisperX {
    /// Разговор с сервисом: вход, отправка файла, ожидание и разбор ответа.
    final class Client: NSObject, URLSessionTaskDelegate {
        private let base: URL
        private lazy var session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 60
            return URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }()

        init(base: URL) {
            self.base = base
        }

        /// URLSession держит делегата, пока её не закроют, - без этого клиент
        /// вместе с сессией жил бы до выхода из приложения.
        func close() {
            session.invalidateAndCancel()
        }

        // MARK: - Шаги

        func login(email: String, password: String) async throws {
            var request = URLRequest(url: base.appendingPathComponent("login"))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(("email=\(escape(email))&password=\(escape(password))").utf8)

            let (data, response) = try await send(request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Успешный вход отвечает переадресацией; сама страница входа
            // возвращается с 200 и текстом ошибки внутри.
            if code == 302 || code == 303 { return }
            // Отказ приходит страницей входа с текстом ошибки внутри: и с 401,
            // и с 200, когда вход просто не удался.
            if code == 401 || code == 200 || code == 429 {
                throw Failure.auth(loginError(in: data) ?? "проверьте почту и пароль из бота")
            }
            throw Failure.auth("код ответа \(code)")
        }

        func enqueue(file: URL, language: String, byChannel: Bool) async throws -> String {
            let boundary = "dakt-\(UUID().uuidString)"
            var fields: [String: String] = ["language": language]
            if byChannel {
                // Каналы разложены нами: слева свой голос, справа собеседники.
                fields["force_channel_transcription"] = "true"
                fields["diarization_pipeline"] = "channel"
            } else {
                // На одном канале разбор говорящих у сервиса падает - он ищет
                // их по каналам, а искать не в чем. Просто расшифровываем.
                fields["diarization_pipeline"] = "off"
                fields["num_speakers"] = "1"
            }
            let body = try multipart(file: file, fields: fields, boundary: boundary)
            defer { try? FileManager.default.removeItem(at: body) }

            var request = URLRequest(url: base.appendingPathComponent("api/transcribe"))
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)",
                             forHTTPHeaderField: "Content-Type")

            let (data, response) = try await session.upload(for: request, fromFile: body, delegate: self)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 202 || code == 200 else {
                if code == 401 { throw Failure.auth("сессия не принята") }
                throw Failure.server(message(in: data) ?? "код ответа \(code)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["job_id"] as? String, !id.isEmpty else {
                throw Failure.server("в ответе нет номера задачи")
            }
            return id
        }

        func wait(job: String, progress: @escaping (String) -> Void) async throws {
            let deadline = Date().addingTimeInterval(45)
            var lastStage = ""
            // Короткий фрагмент готов быстро: не добавляем долгую паузу опроса.
            var pause: TimeInterval = 0.3
            // Один обрыв сети не роняет ожидание; предел — три подряд.
            var failures = 0
            while Date() < deadline {
                try await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                pause = min(pause * 1.4, 1)
                let url = base.appendingPathComponent("api/status/\(job)")
                let data: Data
                let response: URLResponse
                do {
                    (data, response) = try await send(URLRequest(url: url))
                    failures = 0
                } catch {
                    failures += 1
                    if failures >= 3 { throw error }
                    continue
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    if code == 401 { throw Failure.auth("сессия истекла") }
                    throw Failure.server(message(in: data) ?? "код ответа \(code)")
                }
                let status = (json["status"] as? String ?? "").lowercased()
                if status == "finished" { return }
                if status == "failed" {
                    throw Failure.rejected(json["error"] as? String ?? "сервис не справился с файлом")
                }
                let stage = (json["stage"] as? String) ?? status
                if stage != lastStage {
                    lastStage = stage
                    progress(stage)
                }
            }
            throw Failure.timedOut
        }

        func result(job: String) async throws -> [Segment] {
            let url = base.appendingPathComponent("api/download/\(job)/json")
            let (data, response) = try await send(URLRequest(url: url))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                throw Failure.server(message(in: data) ?? "код ответа \(code)")
            }
            guard let segments = WhisperX.parseSegments(data) else {
                throw Failure.server("ответ не разобрать")
            }
            return segments
        }

        // MARK: - Разбор ответа

        private func message(in data: Data) -> String? {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["error"] as? String, !text.isEmpty else { return nil }
            return text
        }

        /// Страница входа возвращает ошибку внутри разметки - вытаскиваем текст.
        private func loginError(in data: Data) -> String? {
            guard let html = String(data: data, encoding: .utf8),
                  let range = html.range(of: "class=\"login-error\"") else { return nil }
            let tail = html[range.upperBound...]
            guard let open = tail.firstIndex(of: ">") else { return nil }
            let rest = tail[tail.index(after: open)...]
            guard let close = rest.range(of: "<") else { return nil }
            let text = rest[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        // MARK: - Приготовления

        private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            try Task.checkCancellation()
            do {
                return try await session.data(for: request, delegate: self)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .serverCertificateUntrusted {
                throw Failure.auth("macOS не доверяет сертификату сервиса")
            } catch {
                try Task.checkCancellation()
                throw Failure.server(error.localizedDescription)
            }
        }

        private func escape(_ value: String) -> String {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }

        /// Тело запроса пишем на диск: встреча на час не должна целиком лежать в памяти.
        private func multipart(file: URL, fields: [String: String], boundary: String) throws -> URL {
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("dakt-upload-\(UUID().uuidString)")
            FileManager.default.createFile(atPath: output.path, contents: nil)
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }

            for (name, value) in fields {
                var part = "--\(boundary)\r\n"
                part += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                part += "\(value)\r\n"
                handle.write(Data(part.utf8))
            }

            var header = "--\(boundary)\r\n"
            header += "Content-Disposition: form-data; name=\"file\"; filename=\"\(file.lastPathComponent)\"\r\n"
            header += "Content-Type: audio/mp4\r\n\r\n"
            handle.write(Data(header.utf8))

            let source = try FileHandle(forReadingFrom: file)
            defer { try? source.close() }
            while let chunk = try source.read(upToCount: 1 << 20), !chunk.isEmpty {
                handle.write(chunk)
            }
            handle.write(Data("\r\n--\(boundary)--\r\n".utf8))
            return output
        }

        // MARK: - Сеть

        /// Вход отвечает переадресацией на главную. Идти за ней незачем: нам нужен
        /// сам факт успеха, а лишний запрос только путал бы разбор ответа.
        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }

    }

    /// Реплики из JSON сервиса. Поля называются по-разному в зависимости от
    /// версии и режима: utterances или segments, text или transcription,
    /// speaker или channel. nil - если это вообще не JSON-объект.
    static func parseSegments(_ data: Data) -> [Segment]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let raw = (json["utterances"] as? [[String: Any]])
            ?? (json["segments"] as? [[String: Any]])
            ?? []
        return raw.compactMap { item in
            let text = ((item["text"] as? String) ?? (item["transcription"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Segment(start: seconds(item["start"]), speaker: speaker(in: item), text: text)
        }
    }

    private static func speaker(in item: [String: Any]) -> String {
        for key in ["speaker", "speaker_id", "channel", "channel_number"] {
            if let text = item[key] as? String, !text.isEmpty { return text }
            if let number = item[key] as? Int { return String(number) }
        }
        return ""
    }

    private static func seconds(_ value: Any?) -> Double {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let text = value as? String, let number = Double(text) { return number }
        return 0
    }

}
