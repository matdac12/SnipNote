//
//  PDFExporter.swift
//  SnipNote
//
//  Renders a MeetingExportDocument to a paginated A4 PDF.
//
//  The document is laid out block by block (title, headings, one block per
//  paragraph) instead of as one huge attributed string. Each block gets its own
//  small CTFramesetter and is flowed across pages, so a two hour transcript
//  costs memory and time proportional to a single paragraph at a time.
//

import UIKit
import CoreText

enum PDFExporter {

    // A4 in points.
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margins = UIEdgeInsets(top: 64, left: 56, bottom: 72, right: 56)

    private struct Block {
        let text: NSAttributedString
        var spaceBefore: CGFloat = 0
        var spaceAfter: CGFloat = 0
        /// Headings: do not start them in the last few lines of a page.
        var keepWithNext: Bool = false
    }

    static func render(_ document: MeetingExportDocument) -> Data {
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let contentWidth = pageSize.width - margins.left - margins.right
        let contentTop = margins.top
        let contentBottom = pageSize.height - margins.bottom

        let info: [String: Any] = [
            kCGPDFContextTitle as String: document.title,
            kCGPDFContextCreator as String: "SnipNote"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = info
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { context in
            var pageNumber = 0
            var cursorY = contentTop

            func startPage() {
                context.beginPage()
                pageNumber += 1
                cursorY = contentTop
                drawPageNumber(pageNumber, in: context.cgContext)
            }

            startPage()

            for block in makeBlocks(for: document) {
                let length = block.text.length
                guard length > 0 else { continue }
                let framesetter = CTFramesetterCreateWithAttributedString(block.text as CFAttributedString)

                // Spacing above a block is dropped at the top of a page.
                if cursorY > contentTop { cursorY += block.spaceBefore }

                if block.keepWithNext {
                    let needed = suggestedSize(framesetter, range: CFRange(location: 0, length: length), width: contentWidth, maxHeight: .greatestFiniteMagnitude).height + 48
                    if cursorY + needed > contentBottom && cursorY > contentTop {
                        startPage()
                    }
                }

                var location = 0
                while location < length {
                    let remainingHeight = max(0, contentBottom - cursorY)
                    if remainingHeight < 20 && cursorY > contentTop {
                        // Less than one line left on this page.
                        startPage()
                        continue
                    }
                    let range = CFRange(location: location, length: length - location)
                    var fitRange = CFRange()
                    let size = suggestedSize(framesetter, range: range, width: contentWidth, maxHeight: remainingHeight, fitRange: &fitRange)

                    if fitRange.length <= 0 || size.height <= 0 {
                        if cursorY <= contentTop {
                            // Pathological: nothing fits even on an empty page. Skip one
                            // character rather than loop forever.
                            location += 1
                        } else {
                            startPage()
                        }
                        continue
                    }

                    draw(framesetter, range: CFRange(location: location, length: fitRange.length), x: margins.left, top: cursorY, width: contentWidth, height: remainingHeight, in: context.cgContext)
                    cursorY += ceil(size.height)
                    location += fitRange.length

                    if location < length {
                        startPage()
                    }
                }

                cursorY += block.spaceAfter
            }
        }
    }

    // MARK: - Core Text helpers

    private static func suggestedSize(_ framesetter: CTFramesetter, range: CFRange, width: CGFloat, maxHeight: CGFloat) -> CGSize {
        var fit = CFRange()
        return suggestedSize(framesetter, range: range, width: width, maxHeight: maxHeight, fitRange: &fit)
    }

    private static func suggestedSize(_ framesetter: CTFramesetter, range: CFRange, width: CGFloat, maxHeight: CGFloat, fitRange: inout CFRange) -> CGSize {
        CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            range,
            nil,
            CGSize(width: width, height: maxHeight),
            &fitRange
        )
    }

    /// Draws `range` top-aligned in a rect whose top edge is `top` (UIKit coordinates).
    private static func draw(_ framesetter: CTFramesetter, range: CFRange, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, in cg: CGContext) {
        cg.saveGState()
        // UIKit PDF contexts are y-down; Core Text draws y-up.
        cg.translateBy(x: 0, y: pageSize.height)
        cg.scaleBy(x: 1, y: -1)
        cg.textMatrix = .identity

        let rect = CGRect(x: x, y: pageSize.height - top - height, width: width, height: height)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: range.location, length: range.length), path, nil)
        CTFrameDraw(frame, cg)
        cg.restoreGState()
    }

    private static func drawPageNumber(_ number: Int, in cg: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSAttributedString(string: "\(number)", attributes: [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.gray,
            .paragraphStyle: paragraph
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        draw(framesetter, range: CFRange(location: 0, length: text.length), x: margins.left, top: pageSize.height - margins.bottom + 28, width: pageSize.width - margins.left - margins.right, height: 16, in: cg)
    }

    // MARK: - Content

    private enum Style {
        static var body: UIFont { UIFont.systemFont(ofSize: 11) }
        static var bodyBold: UIFont { UIFont.systemFont(ofSize: 11, weight: .bold) }
        static func italic(_ size: CGFloat) -> UIFont {
            let base = UIFont.systemFont(ofSize: size)
            let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) ?? base.fontDescriptor
            return UIFont(descriptor: descriptor, size: size)
        }
        static func boldItalic(_ size: CGFloat) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: .bold)
            let descriptor = base.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) ?? base.fontDescriptor
            return UIFont(descriptor: descriptor, size: size)
        }
        static var ink: UIColor { UIColor.black }
        static var secondary: UIColor { UIColor(white: 0.4, alpha: 1) }
    }

    private static func paragraphStyle(lineSpacing: CGFloat = 3, headIndent: CGFloat = 0, firstLine: CGFloat = 0, tab: CGFloat? = nil) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLine
        style.lineBreakMode = .byWordWrapping
        if let tab {
            style.tabStops = [NSTextTab(textAlignment: .left, location: tab, options: [:])]
            style.defaultTabInterval = tab
        }
        return style
    }

    private static func font(size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        switch (bold, italic) {
        case (true, true): return Style.boldItalic(size)
        case (true, false): return UIFont.systemFont(ofSize: size, weight: .bold)
        case (false, true): return Style.italic(size)
        case (false, false): return UIFont.systemFont(ofSize: size)
        }
    }

    private static func attributed(_ runs: [ExportInlineRun], size: CGFloat, baseBold: Bool = false, color: UIColor = Style.ink, style: NSParagraphStyle) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: "")
        for run in runs {
            result.append(NSAttributedString(string: run.text, attributes: [
                .font: font(size: size, bold: run.bold || baseBold, italic: run.italic),
                .foregroundColor: color,
                .paragraphStyle: style
            ]))
        }
        return result
    }

    private static func makeBlocks(for document: MeetingExportDocument) -> [Block] {
        var blocks: [Block] = []

        // Title header
        let title = document.title.isEmpty ? " " : document.title
        blocks.append(Block(
            text: NSAttributedString(string: title, attributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: Style.ink,
                .paragraphStyle: paragraphStyle(lineSpacing: 2)
            ]),
            spaceAfter: 6
        ))
        blocks.append(Block(
            text: NSAttributedString(string: document.subtitle, attributes: [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: Style.secondary,
                .paragraphStyle: paragraphStyle(lineSpacing: 2)
            ]),
            spaceAfter: 10
        ))

        func sectionHeading(_ text: String) -> Block {
            Block(
                text: NSAttributedString(string: text, attributes: [
                    .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                    .foregroundColor: Style.ink,
                    .paragraphStyle: paragraphStyle(lineSpacing: 2)
                ]),
                spaceBefore: 20,
                spaceAfter: 8,
                keepWithNext: true
            )
        }

        if document.hasSummary {
            blocks.append(sectionHeading(document.summaryHeading))
            for block in document.summaryBlocks {
                switch block {
                case .heading(let text, let level):
                    let size: CGFloat = level <= 1 ? 13.5 : 12
                    blocks.append(Block(
                        text: attributed(ExportTextProcessing.inlineRuns(from: text), size: size, baseBold: true, style: paragraphStyle(lineSpacing: 2)),
                        spaceBefore: 8,
                        spaceAfter: 4,
                        keepWithNext: true
                    ))
                case .bullet(let text):
                    let content = NSMutableAttributedString(string: "\u{2022}\t", attributes: [
                        .font: Style.body,
                        .foregroundColor: Style.ink,
                        .paragraphStyle: paragraphStyle(headIndent: 16, tab: 16)
                    ])
                    content.append(attributed(ExportTextProcessing.inlineRuns(from: text), size: 11, style: paragraphStyle(headIndent: 16, tab: 16)))
                    blocks.append(Block(text: content, spaceAfter: 4))
                case .paragraph(let text):
                    blocks.append(Block(
                        text: attributed(ExportTextProcessing.inlineRuns(from: text), size: 11, style: paragraphStyle()),
                        spaceAfter: 8
                    ))
                }
            }
        }

        if document.hasTranscript {
            blocks.append(sectionHeading(document.transcriptHeading))
            let style = paragraphStyle(lineSpacing: 3)
            for paragraph in document.transcript {
                let content = NSMutableAttributedString(string: "")
                if let speaker = paragraph.speaker, !speaker.isEmpty {
                    content.append(NSAttributedString(string: speaker + ": ", attributes: [
                        .font: Style.bodyBold,
                        .foregroundColor: Style.ink,
                        .paragraphStyle: style
                    ]))
                }
                content.append(NSAttributedString(string: paragraph.text, attributes: [
                    .font: Style.body,
                    .foregroundColor: Style.ink,
                    .paragraphStyle: style
                ]))
                blocks.append(Block(text: content, spaceAfter: 8))
            }
        }

        return blocks
    }
}
