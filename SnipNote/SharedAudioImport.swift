//
//  SharedAudioImport.swift
//  SnipNote
//
//  Created by Codex on 06/03/26.
//

import Foundation

struct SharedAudioImportRequest: Identifiable, Hashable {
    enum Source: String, Hashable {
        case deepLink
        case fileShare
    }

    let id: UUID
    let url: URL
    let source: Source
    let receivedAt: Date

    init(
        id: UUID = UUID(),
        url: URL,
        source: Source,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.source = source
        self.receivedAt = receivedAt
    }
}

enum CreateMeetingActivityState: Hashable {
    case idle
    case recording
    case processing
}

struct CreateMeetingRoute: Identifiable, Hashable {
    let id: UUID
    let importRequest: SharedAudioImportRequest?

    init(id: UUID = UUID(), importRequest: SharedAudioImportRequest?) {
        self.id = id
        self.importRequest = importRequest
    }

    static func blankDraft() -> CreateMeetingRoute {
        CreateMeetingRoute(importRequest: nil)
    }

    static func imported(_ request: SharedAudioImportRequest) -> CreateMeetingRoute {
        CreateMeetingRoute(importRequest: request)
    }
}

enum SharedAudioImportRoutingDecision: Hashable {
    case present(CreateMeetingRoute)
    case replace(CreateMeetingRoute)
    case queue(SharedAudioImportRequest)
}

enum SharedAudioImportRouter {
    static func decision(
        activeRoute: CreateMeetingRoute?,
        activityState: CreateMeetingActivityState,
        incomingRequest: SharedAudioImportRequest
    ) -> SharedAudioImportRoutingDecision {
        let importedRoute = CreateMeetingRoute.imported(incomingRequest)

        guard activeRoute != nil else {
            return .present(importedRoute)
        }

        switch activityState {
        case .idle:
            return .replace(importedRoute)
        case .recording, .processing:
            return .queue(incomingRequest)
        }
    }

    static func nextQueuedRoute(
        activeRoute: CreateMeetingRoute?,
        queuedRequest: SharedAudioImportRequest?
    ) -> CreateMeetingRoute? {
        guard activeRoute == nil, let queuedRequest else {
            return nil
        }

        return .imported(queuedRequest)
    }
}
