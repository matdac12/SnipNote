//
//  AnalyticsService.swift
//  SnipNote
//
//  Anonymous usage analytics (MAT-1660). Events go to our own Supabase table through
//  the insert-only `track_analytics_event` RPC. A Guest has no session, so requests are
//  sent with the public anon key only and never carry a user token.
//

import Foundation

/// Product events. Only enums and buckets: never an email, account ID, meeting name,
/// transcript or anything derived from audio content. Keep the names in sync with the
/// allowlist in supabase/migrations/20261004180000_create_analytics_events.sql.
enum AnalyticsEvent {
    case appOpened
    case localRecordingStarted
    case localTranscriptCompleted(length: AnalyticsLengthBucket)
    case analysisUnavailable(reason: AnalyticsUnavailableReason)
    case cloudTrialPromptShown
    case cloudTrialClaimed
    case paywallViewed(paywall: AnalyticsPaywallKind, source: AnalyticsPaywallSource)
    case purchaseCompleted(kind: AnalyticsPurchaseKind, productID: String)

    var name: String {
        switch self {
        case .appOpened: return "app_opened"
        case .localRecordingStarted: return "local_recording_started"
        case .localTranscriptCompleted: return "local_transcript_completed"
        case .analysisUnavailable: return "analysis_unavailable"
        case .cloudTrialPromptShown: return "cloud_trial_prompt_shown"
        case .cloudTrialClaimed: return "cloud_trial_claimed"
        case .paywallViewed: return "paywall_viewed"
        case .purchaseCompleted: return "purchase_completed"
        }
    }

    /// Flat string values only. The server rejects anything longer than 40 characters
    /// or containing characters outside `A-Za-z0-9_.:-`.
    var properties: [String: String] {
        switch self {
        case .appOpened, .localRecordingStarted, .cloudTrialPromptShown, .cloudTrialClaimed:
            return [:]
        case .localTranscriptCompleted(let length):
            return ["length_bucket": length.rawValue]
        case .analysisUnavailable(let reason):
            return ["reason": reason.rawValue]
        case .paywallViewed(let paywall, let source):
            return ["paywall": paywall.rawValue, "source": source.rawValue]
        case .purchaseCompleted(let kind, let productID):
            return ["kind": kind.rawValue, "product_id": productID]
        }
    }
}

/// Coarse audio length, so exact durations are never sent.
enum AnalyticsLengthBucket: String {
    case under1Min = "under_1m"
    case oneToFiveMin = "1_5m"
    case fiveToFifteenMin = "5_15m"
    case fifteenToSixtyMin = "15_60m"
    case overSixtyMin = "over_60m"

    init(duration: TimeInterval) {
        switch duration {
        case ..<60: self = .under1Min
        case ..<300: self = .oneToFiveMin
        case ..<900: self = .fiveToFifteenMin
        case ..<3600: self = .fifteenToSixtyMin
        default: self = .overSixtyMin
        }
    }
}

/// Why Local mode could not produce a summary.
enum AnalyticsUnavailableReason: String {
    case device
    case setting
    case language
    case modelNotReady = "model_not_ready"
    case osUpdate = "os_update"
    case unknown
}

extension AnalysisUnavailableReason {
    var analyticsReason: AnalyticsUnavailableReason {
        switch self {
        case .deviceNotEligible: return .device
        case .appleIntelligenceNotEnabled: return .setting
        case .unsupportedLanguage: return .language
        case .modelNotReady: return .modelNotReady
        case .osUpdateRequired: return .osUpdate
        case .unknown: return .unknown
        }
    }
}

enum AnalyticsPaywallKind: String {
    case subscription
    case minutesPack = "minutes_pack"
}

/// Which screen opened a paywall.
enum AnalyticsPaywallSource: String {
    case home
    case meetings
    case settings
    case createMeeting = "create_meeting"
    case upgradePrompt = "upgrade_prompt"
    case unknown
}

enum AnalyticsPurchaseKind: String {
    case subscription
    case minutesPack = "minutes_pack"
}

final class AnalyticsService: @unchecked Sendable {
    static let shared = AnalyticsService()

    /// Settings toggle. Absent means on (default ON).
    static let enabledDefaultsKey = "analytics.enabled"
    private static let installIDDefaultsKey = "analytics.installID"
    /// Same key `OnboardingView` and `AuthenticationView` use for `hasCompletedOnboarding`.
    private static let onboardingCompletedDefaultsKey = "hasCompletedOnboarding"
    /// `app_opened` fires at launch and on foreground; a foreground within this window
    /// of the last one is not a new open.
    private static let appOpenedMinInterval: TimeInterval = 30 * 60

    private let defaults = UserDefaults.standard
    private let session: URLSession
    private let lock = NSLock()
    private var lastAppOpenedAt: Date?

    private init() {
        // Ephemeral: no cookies or cache, and nothing on disk besides our own UserDefaults keys.
        session = URLSession(configuration: .ephemeral)
    }

    static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool) ?? true
    }

    /// Fire-and-forget. Never blocks the caller, never throws, safe from any thread.
    static func track(_ event: AnalyticsEvent) {
        shared.track(event)
    }

    /// Drops the install ID, so turning analytics back on starts a fresh anonymous identity.
    static func resetInstallID() {
        UserDefaults.standard.removeObject(forKey: installIDDefaultsKey)
    }

    private func track(_ event: AnalyticsEvent) {
        // Single choke point: nothing is built, stored or sent while analytics is off.
        guard Self.isEnabled else { return }

        // Nothing leaves the device before onboarding is done. `OnboardingView` reports the
        // first `app_opened` when it finishes, because the launch one was skipped.
        guard defaults.bool(forKey: Self.onboardingCompletedDefaultsKey) else { return }

        if case .appOpened = event, !shouldSendAppOpened() { return }

        guard let body = requestBody(for: event) else { return }
        let eventName = event.name
        Task.detached(priority: .utility) { [session] in
            await Self.post(body, eventName: eventName, using: session)
        }
    }

    private func shouldSendAppOpened() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let last = lastAppOpenedAt, now.timeIntervalSince(last) < Self.appOpenedMinInterval {
            return false
        }
        lastAppOpenedAt = now
        return true
    }

    /// Random UUID kept on the device. Not an account ID and not derived from one.
    private func installID() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let existing = defaults.string(forKey: Self.installIDDefaultsKey), UUID(uuidString: existing) != nil {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: Self.installIDDefaultsKey)
        return created
    }

    private func requestBody(for event: AnalyticsEvent) -> Data? {
        var body: [String: Any] = [
            "p_install_id": installID(),
            "p_event": event.name,
            "p_platform": "ios\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)",
            "p_properties": event.properties
        ]
        // Marketing version only (e.g. "2.9"), never the build string.
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           version.range(of: #"^[0-9]+(\.[0-9]+){0,3}$"#, options: .regularExpression) != nil,
           version.count <= 16 {
            body["p_app_version"] = version
        }
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// The only place a network request is made. Uses the anon key and no user token,
    /// so it behaves the same for a Guest and for a signed-in user.
    private static func post(_ body: Data, eventName: String, using session: URLSession) async {
        guard isEnabled else { return }

        var request = URLRequest(url: SupabaseManager.supabaseURL.appendingPathComponent("rest/v1/rpc/track_analytics_event"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseManager.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseManager.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            _ = response
            #if DEBUG
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                print("⚠️ [Analytics] \(eventName) rejected with status \(http.statusCode)")
            }
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [Analytics] send failed: \(error.localizedDescription)")
            #endif
        }
    }
}
