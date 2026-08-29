import Foundation
import Testing
@testable import SnipNote

/// Covers the cold-launch path: the app is opened *by* a share, so the import
/// request already exists before the meetings UI is on screen.
struct SharedAudioImportLaunchTests {

    @Test("Cold launch share opens Create Meeting with the request intact")
    func presentsImportOnColdLaunch() {
        let request = SharedAudioImportRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            url: URL(fileURLWithPath: "/tmp/import-launch.m4a"),
            source: .deepLink
        )

        let decision = SharedAudioImportRouter.decision(
            activeRoute: nil,
            activityState: .idle,
            incomingRequest: request
        )

        switch decision {
        case .present(let route):
            #expect(route.importRequest == request)
            #expect(route.importRequest?.source == .deepLink)
            #expect(route.importRequest?.url == request.url)
        default:
            Issue.record("Expected a cold-launch import to present Create Meeting")
        }
    }

    @Test("Share arriving during processing is queued, then replayed once create closes")
    func queuesImportArrivingDuringProcessing() {
        let request = SharedAudioImportRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            url: URL(fileURLWithPath: "/tmp/import-during-processing.m4a"),
            source: .fileShare
        )

        let decision = SharedAudioImportRouter.decision(
            activeRoute: .blankDraft(),
            activityState: .processing,
            incomingRequest: request
        )

        #expect(decision == .queue(request))

        let replayed = SharedAudioImportRouter.nextQueuedRoute(
            activeRoute: nil,
            queuedRequest: request
        )

        #expect(replayed?.importRequest == request)
    }

    @Test("A queued import is held back while Create Meeting is still open")
    func holdsQueuedImportWhileCreateIsOpen() {
        let request = SharedAudioImportRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            url: URL(fileURLWithPath: "/tmp/import-held.m4a"),
            source: .fileShare
        )

        let route = SharedAudioImportRouter.nextQueuedRoute(
            activeRoute: .blankDraft(),
            queuedRequest: request
        )

        #expect(route == nil)
    }

    @Test("Replacing an idle draft keeps the newest share, not the stale one")
    func newestShareWinsOverIdleDraft() {
        let stale = SharedAudioImportRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
            url: URL(fileURLWithPath: "/tmp/import-stale.m4a"),
            source: .fileShare
        )
        let newest = SharedAudioImportRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
            url: URL(fileURLWithPath: "/tmp/import-newest.m4a"),
            source: .fileShare
        )

        let decision = SharedAudioImportRouter.decision(
            activeRoute: .imported(stale),
            activityState: .idle,
            incomingRequest: newest
        )

        switch decision {
        case .replace(let route):
            #expect(route.importRequest == newest)
        default:
            Issue.record("Expected the newest share to replace the idle draft")
        }
    }
}
