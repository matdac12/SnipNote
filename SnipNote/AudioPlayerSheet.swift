//
//  AudioPlayerSheet.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 03/08/25.
//

import SwiftUI

struct AudioPlayerSheet: View {
    @ObservedObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    var meeting: Meeting
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    init(audioPlayer: AudioPlayerManager, meeting: Meeting) {
        self.audioPlayer = audioPlayer
        self.meeting = meeting
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)
            
            // Header
            HStack {
                Button("Done") {
                    dismiss()
                }
                .foregroundColor(themeManager.currentTheme.accentColor)
                
                Spacer()
            }
            .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: 32) {
                    // Meeting Info
                    VStack(spacing: 16) {
                        // Audio visualization placeholder
                        RoundedRectangle(cornerRadius: 20)
                            .fill(LinearGradient(
                                colors: [
                                    themeManager.currentTheme.accentColor.opacity(0.3),
                                    themeManager.currentTheme.accentColor.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(height: 200)
                            .overlay(
                                Image(systemName: "waveform")
                                    .font(.system(size: 60))
                                    .foregroundColor(themeManager.currentTheme.accentColor)
                            )
                            .padding(.horizontal)
                        
                        // Meeting title and info
                        VStack(spacing: 8) {
                            Text(meeting.name.isEmpty ? "Untitled Meeting" : meeting.name)
                                .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                                .multilineTextAlignment(.center)

                            HStack {
                                if !meeting.location.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "location")
                                            .font(.caption)
                                        Text(meeting.location)
                                            .themedCaption()
                                    }
                                }

                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                        .font(.caption)
                                    Text(meeting.dateCreated.formatted(date: .abbreviated, time: .shortened))
                                        .themedCaption()
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Progress Section
                    VStack(spacing: 12) {
                        // Scrubber
                        VStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { isDragging ? dragValue : audioPlayer.currentTime },
                                    set: { newValue in
                                        dragValue = newValue
                                        if !isDragging {
                                            audioPlayer.seek(to: newValue)
                                        }
                                    }
                                ),
                                in: 0...audioPlayer.duration,
                                onEditingChanged: { editing in
                                    isDragging = editing
                                    if !editing {
                                        audioPlayer.seek(to: dragValue)
                                    }
                                }
                            )
                            .tint(themeManager.currentTheme.accentColor)
                            
                            // Time labels
                            HStack {
                                Text(audioPlayer.formattedTime(isDragging ? dragValue : audioPlayer.currentTime))
                                    .themedCaption()
                                    .monospacedDigit()
                                
                                Spacer()
                                
                                Text("-\(audioPlayer.formattedTime(audioPlayer.timeRemaining))")
                                    .themedCaption()
                                    .monospacedDigit()
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Playback Controls
                    HStack(spacing: 40) {
                        // Skip backward
                        Button(action: {
                            audioPlayer.skipBackward()
                        }) {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 34))
                                .foregroundColor(themeManager.currentTheme.accentColor)
                        }
                        .buttonStyle(.plain)
                        
                        // Play/Pause
                        Button(action: {
                            if audioPlayer.isPlaying {
                                audioPlayer.pause()
                            } else {
                                audioPlayer.play()
                            }
                        }) {
                            Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(themeManager.currentTheme.accentColor)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact, trigger: audioPlayer.isPlaying)
                        
                        // Skip forward
                        Button(action: {
                            audioPlayer.skipForward()
                        }) {
                            Image(systemName: "goforward.15")
                                .font(.system(size: 34))
                                .foregroundColor(themeManager.currentTheme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Additional Controls
                    VStack {
                        // Playback speed
                        Menu {
                            Button("0.5×") { audioPlayer.setPlaybackRate(0.5) }
                            Button("0.75×") { audioPlayer.setPlaybackRate(0.75) }
                            Button("1×") { audioPlayer.setPlaybackRate(1.0) }
                            Button("1.25×") { audioPlayer.setPlaybackRate(1.25) }
                            Button("1.5×") { audioPlayer.setPlaybackRate(1.5) }
                            Button("2×") { audioPlayer.setPlaybackRate(2.0) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "gauge")
                                    .font(.body)
                                Text("\(String(format: "%.2g", audioPlayer.playbackRate))×")
                                    .themedBody()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(themeManager.currentTheme.materialStyle)
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .themedBackground()
        .interactiveDismissDisabled(audioPlayer.isPlaying)
    }
}