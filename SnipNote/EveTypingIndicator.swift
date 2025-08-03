//
//  EveTypingIndicator.swift
//  SnipNote
//
//  Created by Eve AI Assistant on 03/08/25.
//

import SwiftUI

struct EveTypingIndicator: View {
    @State private var animationAmount = 0.0
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(themeManager.currentTheme.secondaryTextColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationAmount)
                    .opacity(animationAmount)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animationAmount
                    )
            }
        }
        .onAppear {
            animationAmount = 1.0
        }
    }
}