//
//  MinimalistProcessingView.swift
//  SnipNote
//
//  Created by Claude on 28/11/25.
//

import SwiftUI

// MARK: - Processing Phase

enum MinimalistPhase {
    case uploading
    case transcribing
    case analyzing

    var label: String {
        switch self {
        case .uploading: return "Uploading"
        case .transcribing: return "Transcribing"
        case .analyzing: return "Analyzing"
        }
    }
}

// MARK: - Minimalist Processing View

struct MinimalistProcessingView: View {
    let phase: MinimalistPhase
    let progress: Double  // 0-100
    let stageDescription: String
    let estimatedTimeRemaining: String?
    let currentChunk: Int?
    let totalChunks: Int?
    let partialTranscript: String?  // nil for server-side

    @EnvironmentObject var themeManager: ThemeManager
    @State private var isBreathing = false

    private var theme: AppTheme { themeManager.currentTheme }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Phase label
            Text(phase.label.uppercased())
                .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                .tracking(2)
                .foregroundColor(theme.secondaryTextColor)

            Spacer().frame(height: 24)

            // Hero percentage
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(progress))")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(theme.accentColor)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: Int(progress))
                Text("%")
                    .font(.system(.title3, design: theme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(theme.secondaryTextColor)
            }

            Spacer().frame(height: 32)

            // Progress line
            MinimalistProgressBar(progress: progress, isBreathing: isBreathing)
                .frame(height: 3)
                .padding(.horizontal, 48)

            Spacer().frame(height: 24)

            // Stage description
            Text(stageDescription)
                .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)

            // Progressive info (appears after 25%)
            if progress >= 25 {
                Spacer().frame(height: 12)
                progressiveInfoRow
                    .transition(.opacity)
            }

            Spacer()

            // Subtle transcript preview (on-device only)
            if let transcript = partialTranscript, !transcript.isEmpty {
                subtleTranscriptPreview(transcript)
                    .padding(.bottom, 40)
            }
        }
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.3), value: progress >= 25)
        .onAppear { isBreathing = true }
    }

    @ViewBuilder
    private var progressiveInfoRow: some View {
        HStack(spacing: 8) {
            if let time = estimatedTimeRemaining {
                Text(time)
            }
            if let current = currentChunk, let total = totalChunks, total > 1 {
                if estimatedTimeRemaining != nil {
                    Text("•")
                }
                Text("Chunk \(current)/\(total)")
            }
        }
        .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default))
        .foregroundColor(theme.secondaryTextColor.opacity(0.6))
    }

    private func subtleTranscriptPreview(_ text: String) -> some View {
        Text("\"...\(String(text.suffix(80)))...\"")
            .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default))
            .italic()
            .foregroundColor(theme.secondaryTextColor.opacity(0.4))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }
}

// MARK: - Preview

#Preview {
    MinimalistProcessingView(
        phase: .transcribing,
        progress: 47,
        stageDescription: "Processing audio...",
        estimatedTimeRemaining: "~2m remaining",
        currentChunk: 3,
        totalChunks: 7,
        partialTranscript: "...and then the client mentioned that the deadline would need to be extended by at least two weeks..."
    )
    .environmentObject(ThemeManager.shared)
}
