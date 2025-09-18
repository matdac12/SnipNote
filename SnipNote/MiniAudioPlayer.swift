//
//  MiniAudioPlayer.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 03/08/25.
//

import SwiftUI

struct MiniAudioPlayer<T>: View where T: AnyObject {
    @ObservedObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    let item: T
    let loadAction: (T) async -> Void
    
    @State private var isExpanded = false
    @State private var showFullPlayer = false
    @Namespace private var animation
    
    private var playerWidth: CGFloat {
        isExpanded ? 200 : 44
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Play/Pause Button
            Button(action: {
                Task {
                    await loadAction(item)
                }
            }) {
                if audioPlayer.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(themeManager.currentTheme.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .disabled(audioPlayer.isLoading)
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    // Progress Bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            Capsule()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)
                            
                            // Progress track
                            Capsule()
                                .fill(themeManager.currentTheme.accentColor)
                                .frame(width: geometry.size.width * audioPlayer.progress, height: 4)
                        }
                    }
                    .frame(height: 4)
                    
                    // Time labels
                    HStack {
                        Text(audioPlayer.formattedTime(audioPlayer.currentTime))
                            .themedCaption()
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Text(audioPlayer.formattedTime(audioPlayer.duration))
                            .themedCaption()
                            .monospacedDigit()
                    }
                }
                .frame(width: 140)
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal, isExpanded ? 12 : 0)
        .padding(.vertical, isExpanded ? 6 : 0)
        .background(
            Group {
                if isExpanded {
                    Capsule()
                        .fill(themeManager.currentTheme.materialStyle.opacity(0.8))
                        .overlay(
                            Capsule()
                                .strokeBorder(themeManager.currentTheme.accentColor.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        )
        .onTapGesture {
            if isExpanded {
                showFullPlayer = true
            }
        }
        .sensoryFeedback(.impact, trigger: audioPlayer.isPlaying)
        .onChange(of: audioPlayer.isPlaying) { _, isPlaying in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isExpanded = isPlaying
            }
        }
        .sheet(isPresented: $showFullPlayer) {
            if let meeting = item as? Meeting {
                AudioPlayerSheet(audioPlayer: audioPlayer, meeting: meeting)
                    .environmentObject(themeManager)
            }
        }
    }
}