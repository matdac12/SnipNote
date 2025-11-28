//
//  MinimalistAnalysisView.swift
//  SnipNote
//
//  Created by Claude on 28/11/25.
//

import SwiftUI

struct MinimalistAnalysisView: View {
    let currentStep: Int  // 1=Overview, 2=Summary, 3=Actions, 4=Complete

    @EnvironmentObject var themeManager: ThemeManager

    private var theme: AppTheme { themeManager.currentTheme }

    private let steps = ["Generating overview", "Creating summary", "Extracting actions", "Complete"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Phase label
            Text("ANALYZING")
                .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                .tracking(2)
                .foregroundColor(theme.secondaryTextColor)

            Spacer().frame(height: 24)

            // Current step name
            Text(steps[min(currentStep - 1, steps.count - 1)])
                .font(.system(.title, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                .foregroundColor(theme.accentColor)
                .multilineTextAlignment(.center)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: currentStep)
                .id(currentStep)

            Spacer().frame(height: 32)

            // Step dots
            HStack(spacing: 12) {
                ForEach(1...4, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep
                              ? theme.accentColor
                              : theme.secondaryTextColor.opacity(0.2))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        MinimalistAnalysisView(currentStep: 2)
    }
    .environmentObject(ThemeManager.shared)
}
