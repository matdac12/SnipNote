import Foundation
import Testing
@testable import SnipNote

struct SharedAudioImportRouterTests {

    @Test("Incoming shared audio opens create when no draft is active")
    func presentsImportedRouteWhenNoDraftExists() {
        let request = SharedAudioImportRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            url: URL(fileURLWithPath: "/tmp/import-1.m4a"),
            source: .fileShare
        )

        let decision = SharedAudioImportRouter.decision(
            activeRoute: nil,
            activityState: .idle,
            incomingRequest: request
        )

        switch decision {
        case .present(let route):
            #expect(route.importRequest == request)
        default:
            Issue.record("Expected the import to present a new create route")
        }
    }

    @Test("Incoming shared audio replaces an idle draft")
    func replacesIdleDraft() {
        let request = SharedAudioImportRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            url: URL(fileURLWithPath: "/tmp/import-2.m4a"),
            source: .fileShare
        )
        let activeRoute = CreateMeetingRoute.blankDraft()

        let decision = SharedAudioImportRouter.decision(
            activeRoute: activeRoute,
            activityState: .idle,
            incomingRequest: request
        )

        switch decision {
        case .replace(let route):
            #expect(route.importRequest == request)
        default:
            Issue.record("Expected the idle draft to be replaced")
        }
    }

    @Test("Incoming shared audio queues when recording is active")
    func queuesWhileRecording() {
        let request = SharedAudioImportRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            url: URL(fileURLWithPath: "/tmp/import-3.m4a"),
            source: .fileShare
        )
        let activeRoute = CreateMeetingRoute.blankDraft()

        let decision = SharedAudioImportRouter.decision(
            activeRoute: activeRoute,
            activityState: .recording,
            incomingRequest: request
        )

        #expect(decision == .queue(request))
    }

    @Test("Queued import becomes the next route after create closes")
    func presentsQueuedRouteWhenCreateCloses() {
        let request = SharedAudioImportRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            url: URL(fileURLWithPath: "/tmp/import-4.m4a"),
            source: .deepLink
        )

        let route = SharedAudioImportRouter.nextQueuedRoute(
            activeRoute: nil,
            queuedRequest: request
        )

        #expect(route?.importRequest == request)
    }
}
