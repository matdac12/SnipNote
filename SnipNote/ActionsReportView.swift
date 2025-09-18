//
//  ActionsReportView.swift
//  SnipNote
//
//  Created by Claude on 07/13/25.
//

import SwiftUI

struct ActionsReportView: View {
    let reportContent: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showingCopyConfirmation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "[ ACTIONS REPORT ]" : "Actions Report")
                        .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.accentColor)
                    
                    Spacer()
                    
                    Button(themeManager.currentTheme.headerStyle == .brackets ? "CLOSE" : "Close") {
                        dismiss()
                    }
                    .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        Rectangle()
                            .stroke(themeManager.currentTheme.accentColor, lineWidth: 1)
                    )
                }
                .padding()
                .background(themeManager.currentTheme.materialStyle)
                
                // Report Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(reportContent)
                            .themedBody()
                            .foregroundColor(themeManager.currentTheme.textColor)
                            .padding()
                            .textSelection(.enabled)
                    }
                }
                .themedBackground()
                
                // Footer with Copy button
                HStack {
                    Spacer()
                    
                    Button(action: {
                        UIPasteboard.general.string = reportContent
                        showingCopyConfirmation = true
                        
                        // Hide confirmation after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showingCopyConfirmation = false
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: showingCopyConfirmation ? "checkmark" : "doc.on.doc")
                            Text(showingCopyConfirmation ? (themeManager.currentTheme.headerStyle == .brackets ? "COPIED!" : "Copied!") : (themeManager.currentTheme.headerStyle == .brackets ? "COPY REPORT" : "Copy Report"))
                        }
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.accentColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(themeManager.currentTheme.accentColor.opacity(0.2))
                        .overlay(
                            Rectangle()
                                .stroke(themeManager.currentTheme.accentColor, lineWidth: 1)
                        )
                        .cornerRadius(themeManager.currentTheme.cornerRadius / 2)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(themeManager.currentTheme.materialStyle)
            }
            .themedBackground()
            .navigationBarHidden(true)
        }
        .presentationDetents([.large])
        .presentationBackground(themeManager.currentTheme.backgroundColor)
    }
}

// Preview
struct ActionsReportView_Previews: PreviewProvider {
    static var previews: some View {
        ActionsReportView(reportContent: """
        # Actions Report
        
        ## Executive Summary
        You have 5 pending actions and 3 completed actions across 1 meeting.
        
        ## Priority Breakdown
        - **High Priority**: 2 actions (urgent attention needed)
        - **Medium Priority**: 2 actions
        - **Low Priority**: 1 action
        
        ## Recommendations
        1. Focus on the high priority items first
        2. Schedule time for the medium priority tasks
        3. Consider delegating or deferring low priority items
        """)
    }
}