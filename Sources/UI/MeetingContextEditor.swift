import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MeetingContextEditor: View {
    @ObservedObject var preferences: AssistantPreferences
    @ObservedObject var editor: MeetingContextController
    @State private var showResume = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Что нужно знать о встрече").font(.system(size: 14, weight: .semibold))
            detail("Добавьте резюме — Luna автоматически подготовит шаблон встречи. Резюме и шаблон будут учитываться в ответах.")

            HStack(spacing: 10) {
                Button(action: chooseResume) { Label("Добавить резюме", systemImage: "doc.badge.plus") }
                Button("Вставить текст") {
                    editor.importText(NSPasteboard.general.string(forType: .string) ?? "")
                }
            }
            .disabled(editor.isBusy)
            .controlSize(.small)

            if !preferences.resumeName.isEmpty, !preferences.resumeText.isEmpty {
                Label(preferences.resumeName, systemImage: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(AssistantTheme.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(preferences.resumeName)
            }

            DisclosureGroup(isExpanded: $showResume) {
                textArea("Текст резюме", text: $preferences.resumeText, height: 160,
                         placeholder: "Опыт работы, проекты, навыки и достижения…")
                Text("\(preferences.resumeText.count.formatted()) / 24 000 знаков")
                    .font(.system(size: 10))
                    .foregroundStyle(preferences.resumeText.count > ResumeImporter.maxCharacters ? Color.orange : AssistantTheme.secondary)
            } label: {
                Text("Просмотреть или изменить резюме").font(.system(size: 11))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Компания, роль или цель встречи").font(.system(size: 11, weight: .medium))
                TextField("Например: техническое собеседование на Python backend", text: $preferences.meetingDetails, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Компания, роль или цель встречи")
                detail("Необязательно. Без этих сведений получится общий шаблон по резюме.")
            }

            HStack(spacing: 10) {
                Button(editor.isGenerating ? "Готовлю шаблон…" : "Сформировать шаблон", action: editor.generate)
                    .disabled(!editor.canGenerate)
                    .buttonStyle(.borderedProminent)
                if editor.isBusy {
                    ProgressView().controlSize(.small)
                    Button("Отмена", action: editor.cancel).buttonStyle(.link)
                }
            }
            .controlSize(.small)

            if editor.isImporting { detail("Читаю резюме…") }
            if let error = editor.error {
                Text(error).font(.system(size: 11)).foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let status = editor.status { detail(status) }

            if (editor.isGenerating || editor.requiresApply) && !editor.draft.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Новый шаблон").font(.system(size: 11, weight: .semibold))
                    ScrollView {
                        Text(editor.draft).font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 160)
                    if editor.requiresApply {
                        Button("Использовать этот шаблон", action: editor.applyDraft)
                    }
                }
                .padding(12)
                .background(AssistantTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Шаблон встречи и ваши заметки").font(.system(size: 11, weight: .medium))
                    Spacer()
                    if editor.previousContext != nil {
                        Button("Вернуть прежний", action: editor.restorePrevious)
                            .buttonStyle(.link).font(.system(size: 10))
                    }
                }
                textArea("Контекст встречи", text: $preferences.context, height: 190,
                         placeholder: "Здесь появится шаблон. Можно написать свой контекст вручную.")
            }
            detail("Текст сохраняется на этом Mac и отправляется выбранному корпоративному прокси при подготовке шаблона и ответах. Поддерживаются PDF с текстовым слоем, TXT и Markdown.")
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textArea(_ label: String, text: Binding<String>, height: CGFloat, placeholder: String) -> some View {
        TextEditor(text: text)
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(height: height)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AssistantTheme.line))
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder).font(.system(size: 12)).foregroundStyle(AssistantTheme.secondary.opacity(0.75))
                        .padding(12).allowsHitTesting(false)
                }
            }
            .accessibilityLabel(label)
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(AssistantTheme.secondary)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    private func chooseResume() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Добавить резюме"
        panel.message = "После загрузки Luna подготовит шаблон встречи по резюме."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await editor.importResume(from: url) }
        }
    }
}
