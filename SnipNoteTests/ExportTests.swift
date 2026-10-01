import XCTest
import CoreGraphics
@testable import SnipNote

final class ExportTests: XCTestCase {

    // MARK: - Helpers

    private func sampleDocument(summary: String? = "## Decisions\n- Ship **PDF** export\n- Ship Word export\n\nAll good & <fine>.",
                                transcript: [ExportParagraph] = [ExportParagraph(text: "Ciao a tutti, è un test. 😀")]) -> MeetingExportDocument {
        MeetingExportDocument(
            title: "Riunione <A&B>",
            date: Date(timeIntervalSince1970: 1_780_000_000),
            duration: 3723,
            summary: summary,
            transcript: transcript,
            summaryHeading: "Summary",
            transcriptHeading: "Transcript",
            localeIdentifier: "en"
        )
    }

    private struct ZipEntry {
        let name: String
        let crc: UInt32
        let data: Data
    }

    private func le16(_ d: Data, _ o: Int) -> Int { Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
    private func le32(_ d: Data, _ o: Int) -> UInt32 { UInt32(le16(d, o)) | UInt32(le16(d, o + 2)) << 16 }

    /// Reads a stored-only zip through its central directory.
    private func readZip(_ data: Data) throws -> [ZipEntry] {
        // End of central directory is the last 22 bytes (no comment written).
        let eocd = data.count - 22
        XCTAssertEqual(le32(data, eocd), 0x06054B50)
        let count = le16(data, eocd + 10)
        var offset = Int(le32(data, eocd + 16))
        var entries: [ZipEntry] = []

        for _ in 0..<count {
            XCTAssertEqual(le32(data, offset), 0x02014B50)
            XCTAssertEqual(le16(data, offset + 10), 0, "method must be stored")
            let crc = le32(data, offset + 16)
            let size = Int(le32(data, offset + 24))
            let nameLength = le16(data, offset + 28)
            let extraLength = le16(data, offset + 30)
            let commentLength = le16(data, offset + 32)
            let localOffset = Int(le32(data, offset + 42))
            let nameStart = offset + 46
            let name = String(decoding: data[(data.startIndex + nameStart)..<(data.startIndex + nameStart + nameLength)], as: UTF8.self)

            // Local header: 30 bytes + name + extra, then data.
            XCTAssertEqual(le32(data, localOffset), 0x04034B50)
            let localNameLength = le16(data, localOffset + 26)
            let localExtraLength = le16(data, localOffset + 28)
            let dataStart = data.startIndex + localOffset + 30 + localNameLength + localExtraLength
            let payload = data[dataStart..<(dataStart + size)]

            entries.append(ZipEntry(name: name, crc: crc, data: Data(payload)))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    private final class ParserProbe: NSObject, XMLParserDelegate {
        var error: Error?
        var text = ""
        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) { error = parseError }
        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    }

    private func parseXML(_ data: Data) -> ParserProbe {
        let probe = ParserProbe()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = probe
        XCTAssertTrue(parser.parse(), "XML did not parse: \(String(describing: probe.error))")
        return probe
    }

    // MARK: - ZIP / CRC

    func testCRC32KnownVector() {
        XCTAssertEqual(ZipArchiveWriter.crc32(Data("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(ZipArchiveWriter.crc32(Data()), 0)
    }

    func testZipRoundTrip() throws {
        var zip = ZipArchiveWriter()
        zip.addFile(name: "a.txt", string: "hello")
        zip.addFile(name: "dir/b.txt", string: "wörld 😀")
        let entries = try readZip(zip.finalized())

        XCTAssertEqual(entries.map(\.name), ["a.txt", "dir/b.txt"])
        XCTAssertEqual(String(decoding: entries[1].data, as: UTF8.self), "wörld 😀")
        for entry in entries {
            XCTAssertEqual(entry.crc, ZipArchiveWriter.crc32(entry.data))
        }
    }

    // MARK: - DOCX

    func testDOCXPackageStructure() throws {
        let data = DOCXExporter.render(sampleDocument())
        let entries = try readZip(data)

        XCTAssertEqual(entries.first?.name, "[Content_Types].xml")
        let names = Set(entries.map(\.name))
        XCTAssertTrue(names.isSuperset(of: [
            "[Content_Types].xml", "_rels/.rels", "word/document.xml",
            "word/styles.xml", "word/footer1.xml", "word/_rels/document.xml.rels"
        ]))

        for entry in entries {
            XCTAssertEqual(entry.crc, ZipArchiveWriter.crc32(entry.data), entry.name)
            _ = parseXML(entry.data)   // every part must be well-formed XML
        }
    }

    func testDOCXDocumentEscapesAndKeepsContent() throws {
        let entries = try readZip(DOCXExporter.render(sampleDocument()))
        let documentData = try XCTUnwrap(entries.first { $0.name == "word/document.xml" }?.data)
        let xml = String(decoding: documentData, as: UTF8.self)

        XCTAssertTrue(xml.contains("Riunione &lt;A&amp;B&gt;"))
        // Inline Markdown may split plain content into multiple Word runs.
        // Verify the decoded document text rather than XML run boundaries.
        XCTAssertTrue(parseXML(documentData).text.contains("All good & <fine>."))
        XCTAssertTrue(xml.contains("&amp;"))
        XCTAssertTrue(xml.contains("&lt;fine&gt;"))
        XCTAssertFalse(xml.contains("<A&B>"))
        XCTAssertTrue(xml.contains("w:val=\"Title\""))
        XCTAssertTrue(xml.contains("w:val=\"Heading1\""))
        XCTAssertTrue(xml.contains("Ciao a tutti, è un test. 😀"))
        XCTAssertTrue(xml.contains("<w:b/>"), "**PDF** should become bold")
    }

    func testDOCXStripsIllegalXMLCharactersAndKeepsLineBreaks() throws {
        let doc = sampleDocument(summary: nil, transcript: [ExportParagraph(speaker: "Anna", text: "riga1\nriga2\u{0}\u{1B}fine")])
        let xml = DOCXExporter.documentXML(for: doc)

        XCTAssertFalse(xml.unicodeScalars.contains { $0.value < 0x20 && $0 != "\n" && $0 != "\t" && $0 != "\r" })
        XCTAssertTrue(xml.contains("<w:br/>"))
        XCTAssertTrue(xml.contains("riga2fine"))
        XCTAssertTrue(xml.contains("Anna: "))
        _ = parseXML(Data(xml.utf8))
    }

    func testEscapeHandlesCombiningMarkAfterAmpersand() {
        XCTAssertEqual(DOCXExporter.escape("&\u{301}"), "&amp;\u{301}")
    }

    // MARK: - Text processing

    func testLongTranscriptIsSplitIntoParagraphs() {
        let sentence = "Questa è una frase di prova abbastanza lunga. "
        let transcript = String(repeating: sentence, count: 400)   // one line, ~18k chars
        let paragraphs = ExportTextProcessing.transcriptParagraphs(from: transcript)

        XCTAssertGreaterThan(paragraphs.count, 10)
        XCTAssertTrue(paragraphs.allSatisfy { $0.text.count <= 1400 })
        XCTAssertTrue(paragraphs.allSatisfy { $0.speaker == nil })
    }

    func testTranscriptKeepsLineSeparatedParagraphs() {
        let paragraphs = ExportTextProcessing.transcriptParagraphs(from: "uno\n\n  due  \r\ntre")
        XCTAssertEqual(paragraphs.map(\.text), ["uno", "due", "tre"])
    }

    func testSummaryBlocks() {
        let blocks = ExportTextProcessing.summaryBlocks(from: "# Title\nline one\nline two\n\n- a\n* b\n")
        XCTAssertEqual(blocks, [
            .heading("Title", level: 1),
            .paragraph("line one line two"),
            .bullet("a"),
            .bullet("b")
        ])
    }

    func testSanitizedFileName() {
        let date = Date(timeIntervalSince1970: 43_200)   // noon UTC, same day in nearly every time zone
        XCTAssertEqual(
            ExportTextProcessing.sanitizedFileBaseName(title: "Q3/Plan: \"draft\"?  v2", suffix: "Summary", date: date),
            "Q3-Plan-_-draft--_v2_Summary_1970-01-01"
        )
        XCTAssertEqual(ExportTextProcessing.sanitizedFileBaseName(title: "  ", suffix: nil, date: date), "Transcription_1970-01-01")
        XCTAssertLessThanOrEqual(
            ExportTextProcessing.sanitizedFileBaseName(title: String(repeating: "a", count: 300), suffix: nil, date: date).count,
            80
        )
    }

    // MARK: - PDF

    func testShortPDFIsValidSinglePage() throws {
        let data = PDFExporter.render(sampleDocument())
        XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")

        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertEqual(pdf.numberOfPages, 1)
    }

    func testLongTranscriptPaginates() throws {
        let paragraph = String(repeating: "Parola emoji 😀 àèìòù transcript text. ", count: 20)
        let transcript = (0..<300).map { _ in ExportParagraph(text: paragraph) }
        let data = PDFExporter.render(sampleDocument(transcript: transcript))

        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThan(pdf.numberOfPages, 10)
    }

    func testSingleHugeParagraphSplitsAcrossPages() throws {
        let huge = String(repeating: "parola ", count: 6000)
        let data = PDFExporter.render(sampleDocument(summary: nil, transcript: [ExportParagraph(text: huge)]))

        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThan(pdf.numberOfPages, 1)
    }
}
