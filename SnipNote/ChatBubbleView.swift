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
                            .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                            .foregroundColor(themeManager.currentTheme.backgroundColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(themeManager.currentTheme.accentColor)
                            .cornerRadius(20)
                    } else {
                        Text(message.content)
                            .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                            .foregroundColor(themeManager.currentTheme.textColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(themeManager.currentTheme.materialStyle)
                            .cornerRadius(20)
                    }
                }
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .themedCaption()
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}