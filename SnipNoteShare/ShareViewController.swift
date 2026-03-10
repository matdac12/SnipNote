//
//  ShareViewController.swift
//  SnipNoteShare
//
//  Created by Mattia Da Campo on 10/03/26.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let appGroupID = "group.com.mattianalytics.snipnote"
    private let sharedFolderName = "SharedAudio"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        handleSharedAudio()
    }

    private func handleSharedAudio() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            close(success: false)
            return
        }

        let audioTypes: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .aiff]
        let typeIdentifiers = audioTypes.map { $0.identifier }

        guard let provider = attachments.first(where: { provider in
            typeIdentifiers.contains(where: { provider.hasItemConformingToTypeIdentifier($0) })
        }) else {
            close(success: false)
            return
        }

        let matchedType = typeIdentifiers.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) ?? UTType.audio.identifier

        provider.loadFileRepresentation(forTypeIdentifier: matchedType) { [weak self] url, error in
            guard let self, let sourceURL = url, error == nil else {
                DispatchQueue.main.async { self?.close(success: false) }
                return
            }

            do {
                let destination = try self.copyToSharedContainer(from: sourceURL)
                self.writePendingFlag(audioPath: destination.lastPathComponent)
                DispatchQueue.main.async {
                    self.openMainApp()
                    self.close(success: true)
                }
            } catch {
                print("❌ [ShareExt] Failed to copy audio: \(error)")
                DispatchQueue.main.async { self.close(success: false) }
            }
        }
    }

    private func copyToSharedContainer(from sourceURL: URL) throws -> URL {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw ShareError.noContainer
        }

        let sharedFolder = containerURL.appendingPathComponent(sharedFolderName)
        try FileManager.default.createDirectory(at: sharedFolder, withIntermediateDirectories: true)

        let filename = sourceURL.lastPathComponent
        let destination = sharedFolder.appendingPathComponent(filename)

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        print("✅ [ShareExt] Copied audio to: \(destination.lastPathComponent)")
        return destination
    }

    private func writePendingFlag(audioPath: String) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

        let flagFile = containerURL.appendingPathComponent("pending_audio.txt")
        try? audioPath.write(to: flagFile, atomically: true, encoding: .utf8)
        print("✅ [ShareExt] Wrote pending flag: \(audioPath)")
    }

    private func openMainApp() {
        let urlString = "snipnote://import-shared-audio"
        guard let url = URL(string: urlString) else { return }

        var responder: UIResponder? = self
        while let next = responder?.next {
            if let application = next as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = next
        }

        let selector = NSSelectorFromString("openURL:")
        responder = self
        while let next = responder?.next {
            if next.responds(to: selector) {
                next.perform(selector, with: url)
                return
            }
            responder = next
        }
    }

    private func close(success: Bool) {
        if success {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } else {
            extensionContext?.cancelRequest(withError: NSError(domain: "com.snipnote.share", code: 1))
        }
    }

    private enum ShareError: Error {
        case noContainer
    }
}
