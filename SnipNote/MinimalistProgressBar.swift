//
//  MinimalistProgressBar.swift
//  SnipNote
//
//  Created by Claude on 28/11/25.
//

import SwiftUI

struct MinimalistProgressBar: View {
    let progress: Double
    let isBreathing: Bool

    @EnvironmentObject var themeManager: ThemeManager

    private var theme: AppTheme { themeManager.currentTheme }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(theme.secondaryTextColor.opacity(0.12))

                // Fill
                Rectangle()
                    .fill(theme.accentColor)
                    .frame(width: max(0, geometry.size.width * (progress / 100)))
                    .opacity(isBreathing ? 0.85 : 1.0)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isBreathing)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        MinimalistProgressBar(progress: 45, isBreathing: true)
            .frame(height: 3)
            .padding(.horizontal, 48)

        MinimalistProgressBar(progress: 75, isBreathing: true)
            .frame(height: 3)
            .padding(.horizontal, 48)
    }
    .environmentObject(ThemeManager.shared)
}
