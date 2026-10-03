//
//  MembershipPassView.swift
//  SnipNote
//
//  Wallet-style pass at the top of Settings: plan, minutes balance and email
//  on the front, all-time usage on the back.
//

import SwiftUI

enum ProPlan: CaseIterable {
    case weekly
    case monthly
    case annual

    init?(productIDs: Set<String>) {
        if productIDs.contains(where: { $0.contains("annual") }) {
            self = .annual
        } else if productIDs.contains(where: { $0.contains("monthly") }) {
            self = .monthly
        } else if productIDs.contains(where: { $0.contains("weekly") }) {
            self = .weekly
        } else {
            return nil
        }
    }

    var nameKey: String {
        switch self {
        case .weekly: return "settings.plan.weekly.name"
        case .monthly: return "settings.plan.monthly.name"
        case .annual: return "settings.plan.annual.name"
        }
    }

    var allowanceKey: String {
        switch self {
        case .weekly: return "settings.plan.weekly.allowance"
        case .monthly: return "settings.plan.monthly.allowance"
        case .annual: return "settings.plan.annual.allowance"
        }
    }
}

struct MembershipPassView: View {
    let isPro: Bool
    let plan: ProPlan?
    let balance: Int
    let email: String?
    let usage: UserUsage?

    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsUsage = false

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.6)) {
                showsUsage.toggle()
            }
        } label: {
            ZStack {
                front
                    .opacity(showsUsage ? 0 : 1)
                    .rotation3DEffect(.degrees(showsUsage && !reduceMotion ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                back
                    .opacity(showsUsage ? 1 : 0)
                    .rotation3DEffect(.degrees(showsUsage || reduceMotion ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(height: 186)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(localized("settings.pass.accessibilityHint"))
    }

    // MARK: - Faces

    private var front: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    caption("SnipNote")
                    Text(localized(isPro ? "settings.subscription.plan.pro" : "settings.subscription.plan.free"))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                caption(planBadge)
            }

            Spacer(minLength: 8)

            caption(localized("settings.pass.minutesLeft"))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(max(balance, 0))")
                    .font(.system(size: 36, weight: .bold))
                    .monospacedDigit()
                Text("min")
                    .font(.footnote.weight(.medium))
                    .opacity(0.8)
                if balance <= 0 {
                    Text(localized("settings.pass.outOfMinutes"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(red: 0.16, green: 0.1, blue: 0))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(red: 1, green: 0.7, blue: 0.25), in: Capsule())
                }
            }

            Spacer(minLength: 8)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    if let email {
                        Text(email)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    Text(localized(isPro ? "settings.pass.planLine.pro" : "settings.pass.planLine.free"))
                        .font(.caption2)
                        .opacity(0.75)
                }
                Spacer()
                caption(localized("settings.pass.tapForUsage"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(alignment: .trailing) { waveform.offset(x: 36, y: -10) }
        .background(frontBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: (isPro ? Self.proDeep : .black).opacity(0.35), radius: 14, y: 10)
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                caption(localized("settings.pass.usageTitle"))
                Spacer()
                caption(localized("settings.pass.allTime"))
            }
            Spacer(minLength: 0)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    stat(usage.map { "\($0.totalMeetings)" }, localized("settings.usage.meetingsCreated"))
                    stat(usage.map { "\($0.totalMeetingsTranscribed)" }, localized("settings.usage.meetingsTranscribed"))
                }
                GridRow {
                    stat(usage.map { Self.formatDuration($0.totalMeetingSeconds) }, localized("settings.usage.totalRecordingTime"))
                    stat(usage.map { "\($0.totalAiSummaries)" }, localized("settings.usage.aiSummaries"))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
    }

    // MARK: - Pieces

    private static let proLight = Color(red: 1.0, green: 0.6, blue: 0.38)
    private static let proMid = Color(red: 1.0, green: 0.42, blue: 0.21)
    private static let proDeep = Color(red: 0.85, green: 0.27, blue: 0.1)

    @ViewBuilder
    private var frontBackground: some View {
        if isPro {
            ZStack {
                LinearGradient(colors: [Self.proMid, Self.proDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Self.proLight, .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
            }
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.23), Color(white: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(white: 0.4), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
            }
        }
    }

    private var waveform: some View {
        HStack(spacing: 2) {
            ForEach(0..<28, id: \.self) { index in
                Capsule()
                    .frame(width: 3, height: Self.barHeight(index))
            }
        }
        .foregroundStyle(.white.opacity(0.28))
        .accessibilityHidden(true)
    }

    private static func barHeight(_ index: Int) -> CGFloat {
        let value = abs(sin(Double(index) * 0.7) * cos(Double(index) * 0.23))
        return 6 + 30 * value
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .kerning(0.8)
            .opacity(0.78)
    }

    private func stat(_ value: String?, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "–")
                .font(.system(size: 19, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .opacity(0.78)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planBadge: String {
        if isPro {
            return plan.map { localized($0.nameKey) } ?? "Pro"
        }
        return localized("settings.pass.planType.free")
    }

    private var accessibilitySummary: String {
        let planName = localized(isPro ? "settings.subscription.plan.pro" : "settings.subscription.plan.free")
        return "\(planName), \(max(balance, 0)) min"
    }

    static func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m \(totalSeconds % 60)s"
    }

    private func localized(_ key: String) -> String {
        localizationManager.localizedString(key)
    }
}
