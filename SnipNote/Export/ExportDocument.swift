//
//  ExportDocument.swift
//  SnipNote
//
//  Format-agnostic description of what gets exported (PDF, DOCX, text).
//  Pure value types: no UIKit, no SwiftData, safe to build on any thread.
//

import Foundation

/// One paragraph of a transcript. `speaker` is nil until speaker labels exist;
/// every renderer already prints it (bold, before the text) when present.
struct ExportParagraph: Equatable, Sendable {
    var speaker: String?
    var text: String

    init(speaker: String? = nil, text: String) {
        self.speaker = speaker
        self.text = text
    }
}

/// A run of inline text with the little formatting the AI summary uses.
struct ExportInlineRun: Equatable, Sendable {
    var text: String
    var bold: Bool = false
    var italic: Bool = false
}

/// Block-level structure of the (markdown-ish) AI summary.
enum ExportSummaryBlock: Equatable, Sendable {
    case heading(String, level: Int)
    case bullet(String)
    case paragraph(String)
}

struct MeetingExportDocument: Equatable, Sendable {
    var title: String
    var date: Date
    /// Recording length in seconds, nil when unknown.
    var duration: TimeInterval?
    /// Summary text as stored on the meeting (light markdown), nil when absent.
    var summary: String?
    /// Transcript as paragraphs. Empty when the transcript is not exported.
    var transcript: [ExportParagraph]

    // Localised strings resolved by the caller so this type stays UI/locale free.
    var summaryHeading: String = "Summary"
    var transcriptHeading: String = "Transcript"
    var localeIdentifier: String = "en"

    /// e.g. "30 September 2026 · 1h 2m 3s"
    var subtitle: String {
        let locale = Locale(identifier: localeIdentifier)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        var parts = [dateFormatter.string(from: date)]

        if let duration, duration >= 1 {
            let formatter = DateComponentsFormatter()
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            formatter.calendar = calendar
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .abbreviated
            if let text = formatter.string(from: duration) {
                parts.append(text)
            }
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    var summaryBlocks: [ExportSummaryBlock] {
        guard let summary else { return [] }
        return ExportTextProcessing.summaryBlocks(from: summary)
    }

    var hasSummary: Bool { !summaryBlocks.isEmpty }
    var hasTranscript: Bool { !transcript.isEmpty }
}

// MARK: - Text processing shared by all renderers

enum ExportTextProcessing {

    /// Transcripts arrive either as line-separated chunks or as one giant line.
    /// Split on newlines, then break any overly long paragraph at sentence
    /// boundaries so renderers (and readers) get manageable paragraphs.
    static func transcriptParagraphs(from transcript: String, maxLength: Int = 700) -> [ExportParagraph] {
        var result: [ExportParagraph] = []

        for rawLine in transcript.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.count <= maxLength {
                result.append(ExportParagraph(text: line))
                continue
            }

            var current = ""
            line.enumerateSubstrings(in: line.startIndex..<line.endIndex, options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
                let sentence = String(line[range])
                if !current.isEmpty && current.count + sentence.count > maxLength {
                    result.append(ExportParagraph(text: current.trimmingCharacters(in: .whitespacesAndNewlines)))
                    current = ""
                }
                current += sentence

                // A single "sentence" longer than the limit (no punctuation): hard split.
                while current.count > maxLength * 2 {
                    let cut = current.index(current.startIndex, offsetBy: maxLength)
                    result.append(ExportParagraph(text: String(current[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)))
                    current = String(current[cut...])
                }
            }
            let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                result.append(ExportParagraph(text: tail))
            }
        }

        return result.filter { !$0.text.isEmpty }
    }

    /// Same block rules as the on-screen summary in MeetingDetailView.
    static func summaryBlocks(from text: String) -> [ExportSummaryBlock] {
        var blocks: [ExportSummaryBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let paragraph = paragraphLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphLines.removeAll()
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if let bullet = parseBullet(line) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                continue
            }

            paragraphLines.append(line)
        }

        flushParagraph()
        return blocks
    }

    private static func parseHeading(_ line: String) -> ExportSummaryBlock? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let content = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return .heading(content, level: level)
    }

    private static func parseBullet(_ line: String) -> String? {
        for prefix in ["- ", "* ", "\u{2022} "] where line.hasPrefix(prefix) {
            let content = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !content.isEmpty { return content }
        }
        return nil
    }

    /// Inline markdown (**bold**, *italic*) to styled runs. Falls back to plain text.
    static func inlineRuns(from text: String) -> [ExportInlineRun] {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let attributed = try? AttributedString(markdown: text, options: options) else {
            return [ExportInlineRun(text: text)]
        }

        var runs: [ExportInlineRun] = []
        for run in attributed.runs {
            let piece = String(attributed[run.range].characters)
            guard !piece.isEmpty else { continue }
            let intent = run.inlinePresentationIntent ?? []
            runs.append(ExportInlineRun(
                text: piece,
                bold: intent.contains(.stronglyEmphasized),
                italic: intent.contains(.emphasized)
            ))
        }
        return runs.isEmpty ? [ExportInlineRun(text: text)] : runs
    }

    /// Removes characters that are illegal in XML 1.0 (control characters,
    /// U+FFFE/U+FFFF). Transcripts from speech models occasionally contain them.
    static func xmlSafe(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x9, 0xA, 0xD, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                scalars.append(scalar)
            default:
                continue
            }
        }
        return String(scalars)
    }

    /// File-system safe name such as "Weekly_sync_Transcript_2026-09-30".
    static func sanitizedFileBaseName(title: String, suffix: String?, date: Date) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:\u{0}")
            .union(.controlCharacters)
            .union(.newlines)

        var cleaned = String(title.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) })
        cleaned = cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        if cleaned.count > 60 {
            cleaned = String(cleaned.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        }
        if cleaned.isEmpty { cleaned = "Meeting" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var parts = [cleaned]
        if let suffix, !suffix.isEmpty { parts.append(suffix) }
        parts.append(formatter.string(from: date))
        return parts.joined(separator: "_")
    }
}
