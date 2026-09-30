//
//  ExportService.swift
//  SnipNote
//
//  Turns a meeting into a PDF or Word file in a temporary directory and shows
//  the system share sheet. Rendering runs off the main thread.
//

import Foundation
import UIKit

enum ExportFormat: Equatable, Sendable {
    case pdf
    case word

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .word: return "docx"
        }
    }
}

enum ExportContent: Equatable, Sendable {
    case summary
    case transcript
    case everything

    /// Suffix used in the file name; nil for the combined document.
    var fileSuffix: String? {
        switch self {
        case .summary: return "Summary"
        case .transcript: return "Transcript"
        case .everything: return nil
        }
    }
}

/// Plain copy of the meeting fields an export needs. Built on the main actor
/// (SwiftData models are not thread safe), consumed on a background task.
struct MeetingExportSnapshot: Sendable {
    var title: String
    var date: Date
    var duration: TimeInterval?
    var summary: String?
    var transcript: String?
    var content: ExportContent
    var summaryHeading: String
    var transcriptHeading: String
    var localeIdentifier: String

    /// Splitting a very long transcript into paragraphs is done here so it can
    /// happen off the main thread.
    func makeDocument() -> MeetingExportDocument {
        MeetingExportDocument(
            title: title,
            date: date,
            duration: duration,
            summary: summary,
            transcript: transcript.map { ExportTextProcessing.transcriptParagraphs(from: $0) } ?? [],
            summaryHeading: summaryHeading,
            transcriptHeading: transcriptHeading,
            localeIdentifier: localeIdentifier
        )
    }
}

enum ExportService {

    enum ExportError: LocalizedError {
        case nothingToExport

        var errorDescription: String? {
            LocalizationManager.localizedAppString("export.error.nothingToExport")
        }
    }

    // MARK: - Snapshot

    @MainActor
    static func snapshot(of meeting: Meeting, content: ExportContent) -> MeetingExportSnapshot {
        let summary = meeting.aiSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let includeSummary = content != .transcript && !summary.isEmpty
        let includeTranscript = content != .summary && meeting.hasTranscriptContent

        let duration: TimeInterval? = {
            if meeting.duration > 0 { return meeting.duration }
            if meeting.sourceAudioDurationSeconds > 0 { return meeting.sourceAudioDurationSeconds }
            return nil
        }()

        let title = meeting.name.trimmingCharacters(in: .whitespacesAndNewlines)

        return MeetingExportSnapshot(
            title: title.isEmpty ? LocalizationManager.localizedAppString("export.untitled") : title,
            date: meeting.dateCreated,
            duration: duration,
            summary: includeSummary ? summary : nil,
            transcript: includeTranscript ? meeting.audioTranscript : nil,
            content: content,
            summaryHeading: LocalizationManager.localizedAppString("export.heading.summary"),
            transcriptHeading: LocalizationManager.localizedAppString("export.heading.transcript"),
            localeIdentifier: LocalizationManager.currentLanguageCode()
        )
    }

    // MARK: - Rendering

    static func render(_ document: MeetingExportDocument, as format: ExportFormat) -> Data {
        switch format {
        case .pdf: return PDFExporter.render(document)
        case .word: return DOCXExporter.render(document)
        }
    }

    /// Renders and writes the file, returning its URL. Safe to call from the main actor;
    /// the heavy work happens on a background task.
    static func exportFile(_ snapshot: MeetingExportSnapshot, as format: ExportFormat) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let document = snapshot.makeDocument()
            guard document.hasSummary || document.hasTranscript else {
                throw ExportError.nothingToExport
            }

            let data = ExportService.render(document, as: format)
            let baseName = ExportTextProcessing.sanitizedFileBaseName(
                title: snapshot.title,
                suffix: snapshot.content.fileSuffix,
                date: snapshot.date
            )
            return try ExportService.writeTemporaryFile(data, baseName: baseName, fileExtension: format.fileExtension)
        }.value
    }

    static func writeTemporaryFile(_ data: Data, baseName: String, fileExtension: String) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("SnipNoteExports", isDirectory: true)
        // Previous exports were already handed to the share sheet; drop them.
        try? fileManager.removeItem(at: root)

        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("\(baseName).\(fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Share sheet

enum ExportSharePresenter {
    @MainActor
    static func present(_ url: URL) {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
            var top = window.rootViewController
        else { return }

        while let presented = top.presentedViewController {
            top = presented
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = top.view
        activityVC.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        activityVC.popoverPresentationController?.permittedArrowDirections = []
        top.present(activityVC, animated: true)
    }
}
