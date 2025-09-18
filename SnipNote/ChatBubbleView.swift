//
//  ChatBubbleView.swift
//  SnipNote
//
//  Created by Eve AI Assistant on 03/08/25.
//

import SwiftUI

struct ChatBubbleView: View {
    let message: EveMessage
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Group {
                    if message.role == .user {
                        Text(message.content)
                            .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                            .foregroundColor(themeManager.currentTheme.backgroundColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(themeManager.currentTheme.accentColor)
                            .cornerRadius(20)
                            .shadow(color: themeManager.currentTheme.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                    } else {
                        Text(message.content)
                            .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .regular))
                            .foregroundColor(themeManager.currentTheme.textColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(themeManager.currentTheme.materialStyle)
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                    }
                }
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .light))
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor.opacity(0.7))
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}