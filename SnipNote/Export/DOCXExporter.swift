//
//  DOCXExporter.swift
//  SnipNote
//
//  Builds a minimal, valid WordprocessingML package (.docx) by hand:
//    [Content_Types].xml, _rels/.rels, word/document.xml, word/styles.xml,
//    word/footer1.xml (page numbers), word/_rels/document.xml.rels
//  Uses Title / Subtitle / Heading1-3 / Normal styles so Word, Pages and
//  Google Docs show a real document outline.
//

import Foundation

enum DOCXExporter {

    static func render(_ document: MeetingExportDocument) -> Data {
        var zip = ZipArchiveWriter()
        // [Content_Types].xml first, as recommended by OPC.
        zip.addFile(name: "[Content_Types].xml", string: contentTypesXML)
        zip.addFile(name: "_rels/.rels", string: rootRelsXML)
        zip.addFile(name: "word/document.xml", string: documentXML(for: document))
        zip.addFile(name: "word/styles.xml", string: stylesXML)
        zip.addFile(name: "word/footer1.xml", string: footerXML)
        zip.addFile(name: "word/_rels/document.xml.rels", string: documentRelsXML)
        return zip.finalized()
    }

    // MARK: - XML helpers

    /// Escapes text for use in element content or attribute values and drops
    /// characters that are illegal in XML 1.0.
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for character in ExportTextProcessing.xmlSafe(text).unicodeScalars {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.unicodeScalars.append(character)
            }
        }
        return result
    }

    private static let wNamespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private static let rNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    /// One `<w:r>` per line of `text`, joined with `<w:br/>` so embedded line breaks survive.
    private static func runs(_ text: String, bold: Bool = false, italic: Bool = false) -> String {
        let props: String
        if bold || italic {
            props = "<w:rPr>" + (bold ? "<w:b/><w:bCs/>" : "") + (italic ? "<w:i/><w:iCs/>" : "") + "</w:rPr>"
        } else {
            props = ""
        }

        let lines = text.components(separatedBy: .newlines)
        var xml = ""
        for (index, line) in lines.enumerated() {
            if index > 0 { xml += "<w:r>\(props)<w:br/></w:r>" }
            guard !line.isEmpty else { continue }
            xml += "<w:r>\(props)<w:t xml:space=\"preserve\">\(escape(line))</w:t></w:r>"
        }
        return xml
    }

    private static func inlineRuns(_ text: String, baseBold: Bool = false) -> String {
        ExportTextProcessing.inlineRuns(from: text)
            .map { runs($0.text, bold: $0.bold || baseBold, italic: $0.italic) }
            .joined()
    }

    private static func paragraph(style: String?, properties: String = "", content: String) -> String {
        var pPr = ""
        if let style { pPr += "<w:pStyle w:val=\"\(style)\"/>" }
        pPr += properties
        return "<w:p>" + (pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>") + content + "</w:p>"
    }

    // MARK: - document.xml

    static func documentXML(for document: MeetingExportDocument) -> String {
        var body = ""

        let title = document.title.isEmpty ? " " : document.title
        body += paragraph(style: "Title", content: runs(title))
        body += paragraph(style: "Subtitle", content: runs(document.subtitle))

        if document.hasSummary {
            body += paragraph(style: "Heading1", content: runs(document.summaryHeading))
            for block in document.summaryBlocks {
                switch block {
                case .heading(let text, let level):
                    body += paragraph(style: level <= 1 ? "Heading2" : "Heading3", content: inlineRuns(text))
                case .bullet(let text):
                    // Plain hanging-indent bullet: avoids needing numbering.xml.
                    body += paragraph(
                        style: nil,
                        properties: "<w:tabs><w:tab w:val=\"left\" w:pos=\"360\"/></w:tabs><w:ind w:left=\"360\" w:hanging=\"360\"/>",
                        content: "<w:r><w:t>\u{2022}</w:t></w:r><w:r><w:tab/></w:r>" + inlineRuns(text)
                    )
                case .paragraph(let text):
                    body += paragraph(style: "Normal", content: inlineRuns(text))
                }
            }
        }

        if document.hasTranscript {
            body += paragraph(style: "Heading1", content: runs(document.transcriptHeading))
            for item in document.transcript {
                var content = ""
                if let speaker = item.speaker, !speaker.isEmpty {
                    content += runs(speaker + ": ", bold: true)
                }
                content += runs(item.text)
                body += paragraph(style: "Normal", content: content)
            }
        }

        // A4, 2 cm margins, footer with page number.
        let section = "<w:sectPr><w:footerReference w:type=\"default\" r:id=\"rIdFooter1\"/>"
            + "<w:pgSz w:w=\"11906\" w:h=\"16838\"/>"
            + "<w:pgMar w:top=\"1134\" w:right=\"1134\" w:bottom=\"1134\" w:left=\"1134\" w:header=\"708\" w:footer=\"708\" w:gutter=\"0\"/>"
            + "</w:sectPr>"

        return xmlHeader
            + "<w:document xmlns:w=\"\(wNamespace)\" xmlns:r=\"\(rNamespace)\"><w:body>"
            + body + section
            + "</w:body></w:document>"
    }

    // MARK: - Static parts

    static let contentTypesXML: String = [
        xmlHeader,
        "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">",
        "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>",
        "<Default Extension=\"xml\" ContentType=\"application/xml\"/>",
        "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>",
        "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>",
        "<Override PartName=\"/word/footer1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>",
        "</Types>",
    ].joined()

    static let rootRelsXML: String = [
        xmlHeader,
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
        "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>",
        "</Relationships>",
    ].joined()

    static let documentRelsXML: String = [
        xmlHeader,
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
        "<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>",
        "<Relationship Id=\"rIdFooter1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"footer1.xml\"/>",
        "</Relationships>",
    ].joined()

    static let footerXML: String = [
        xmlHeader,
        "<w:ftr xmlns:w=\"\(wNamespace)\" xmlns:r=\"\(rNamespace)\">",
        "<w:p><w:pPr><w:pStyle w:val=\"Footer\"/><w:jc w:val=\"center\"/></w:pPr>",
        "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>",
        "<w:r><w:instrText xml:space=\"preserve\"> PAGE </w:instrText></w:r>",
        "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>",
        "<w:r><w:t>1</w:t></w:r>",
        "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>",
        "</w:p></w:ftr>",
    ].joined()

    private static func headingStyle(id: String, name: String, level: Int, size: Int, before: Int, after: Int) -> String {
        "<w:style w:type=\"paragraph\" w:styleId=\"\(id)\"><w:name w:val=\"\(name)\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:uiPriority w:val=\"9\"/><w:qFormat/>"
            + "<w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before=\"\(before)\" w:after=\"\(after)\"/><w:outlineLvl w:val=\"\(level)\"/></w:pPr>"
            + "<w:rPr><w:b/><w:bCs/><w:sz w:val=\"\(size)\"/><w:szCs w:val=\"\(size)\"/></w:rPr></w:style>"
    }

    static let stylesXML: String = [
        xmlHeader,
        "<w:styles xmlns:w=\"\(wNamespace)\">",
        "<w:docDefaults>",
        "<w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Calibri\" w:hAnsi=\"Calibri\" w:eastAsia=\"Calibri\" w:cs=\"Calibri\"/><w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/><w:lang w:val=\"en-US\" w:eastAsia=\"en-US\" w:bidi=\"ar-SA\"/></w:rPr></w:rPrDefault>",
        "<w:pPrDefault><w:pPr><w:spacing w:after=\"160\" w:line=\"276\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault>",
        "</w:docDefaults>",
        "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/></w:style>",
        "<w:style w:type=\"paragraph\" w:styleId=\"Title\"><w:name w:val=\"Title\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:uiPriority w:val=\"10\"/><w:qFormat/>",
        "<w:pPr><w:spacing w:before=\"0\" w:after=\"80\"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val=\"48\"/><w:szCs w:val=\"48\"/></w:rPr></w:style>",
        "<w:style w:type=\"paragraph\" w:styleId=\"Subtitle\"><w:name w:val=\"Subtitle\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:uiPriority w:val=\"11\"/><w:qFormat/>",
        "<w:pPr><w:spacing w:after=\"240\"/></w:pPr><w:rPr><w:color w:val=\"666666\"/><w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/></w:rPr></w:style>",
        headingStyle(id: "Heading1", name: "heading 1", level: 0, size: 32, before: 360, after: 120),
        headingStyle(id: "Heading2", name: "heading 2", level: 1, size: 27, before: 240, after: 80),
        headingStyle(id: "Heading3", name: "heading 3", level: 2, size: 24, before: 200, after: 60),
        "<w:style w:type=\"paragraph\" w:styleId=\"Footer\"><w:name w:val=\"footer\"/><w:basedOn w:val=\"Normal\"/><w:uiPriority w:val=\"99\"/>",
        "<w:pPr><w:spacing w:after=\"0\"/></w:pPr><w:rPr><w:color w:val=\"808080\"/><w:sz w:val=\"18\"/><w:szCs w:val=\"18\"/></w:rPr></w:style>",
        "</w:styles>",
    ].joined()
}
