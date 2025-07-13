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
    @State private var showingCopyConfirmation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("[ ACTIONS REPORT ]")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    Button("CLOSE") {
                        dismiss()
                    }
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        Rectangle()
                            .stroke(.green, lineWidth: 1)
                    )
                }
                .padding()
                .background(.ultraThinMaterial)
                
                // Report Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(reportContent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.green)
                            .padding()
                            .textSelection(.enabled)
                    }
                }
                .background(.black)
                
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
                            Text(showingCopyConfirmation ? "COPIED!" : "COPY REPORT")
                        }
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.green.opacity(0.2))
                        .overlay(
                            Rectangle()
                                .stroke(.green, lineWidth: 1)
                        )
                        .cornerRadius(4)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .background(.black)
            .navigationBarHidden(true)
        }
        .presentationDetents([.large])
        .presentationBackground(.black)
    }
}

// Preview
struct ActionsReportView_Previews: PreviewProvider {
    static var previews: some View {
        ActionsReportView(reportContent: """
        # Actions Report
        
        ## Executive Summary
        You have 5 pending actions and 3 completed actions across 2 notes and 1 meeting.
        
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