import XCTest
import CoreGraphics
import CoreText
@testable import DaktRecorder

final class ResumeImporterTests: XCTestCase {
    func testReadsTextAndRejectsUnsupportedFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = folder.appendingPathComponent("resume.txt")
        try "  Python, FastAPI, PostgreSQL.  \n".write(to: text, atomically: true, encoding: .utf8)
        XCTAssertEqual(try ResumeImporter.read(text).text, "Python, FastAPI, PostgreSQL.")
        let unsupported = folder.appendingPathComponent("resume.bin")
        try Data([1, 2]).write(to: unsupported)
        XCTAssertThrowsError(try ResumeImporter.read(unsupported))
    }

    func testReadsTextLayerFromPDF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("resume-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(x: 0, y: 0, width: 600, height: 400)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 20, y: 350)
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let text = NSAttributedString(string: "Test Candidate. Python backend, FastAPI and PostgreSQL.",
                                      attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.endPDFPage()
        context.closePDF()
        let document = try ResumeImporter.read(url, displayName: "My resume.pdf")
        XCTAssertTrue(document.text.contains("Python backend"))
        XCTAssertEqual(document.name, "My resume.pdf")
    }

    func testEmptyAndOversizeResumeAreRejectedWithoutSilentTruncation() {
        XCTAssertThrowsError(try ResumeImporter.validate(" \n\t"))
        XCTAssertThrowsError(try ResumeImporter.validate(String(repeating: "x", count: ResumeImporter.maxCharacters + 1)))
    }
}
