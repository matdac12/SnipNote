//
//  AudioPlayerManager.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 03/08/25.
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
class AudioPlayerManager: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var playbackRate: Float = 1.0
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var currentMeetingId: UUID?
    
    private let skipInterval: TimeInterval = 15.0
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func loadAndPlayAudio(for meeting: Meeting) async {
        // If we're already playing this meeting, just toggle play/pause
        if currentMeetingId == meeting.id, let player = audioPlayer {
            if player.isPlaying {
                pause()
            } else {
                play()
            }
            return
        }
        
        // Stop current playback if any
        stop()
        
        isLoading = true
        errorMessage = nil
        currentMeetingId = meeting.id
        
        do {
            // Get signed URL from Supabase
            guard let audioURL = try await SupabaseManager.shared.getAudioURL(for: meeting.id) else {
                errorMessage = "Audio not found"
                isLoading = false
                return
            }
            
            // Download audio data
            let (data, _) = try await URLSession.shared.data(from: audioURL)
            
            // Create audio player
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            duration = audioPlayer?.duration ?? 0
            isLoading = false
            
            // Start playing
            play()
            
        } catch {
            errorMessage = "Failed to load audio: \(error.localizedDescription)"
            isLoading = false
            currentMeetingId = nil
        }
    }
    
    
    func play() {
        audioPlayer?.enableRate = true
        audioPlayer?.rate = playbackRate
        audioPlayer?.play()
        isPlaying = true
        startTimer()
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTimer()
        currentMeetingId = nil
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    func skipForward() {
        let newTime = min(currentTime + skipInterval, duration)
        seek(to: newTime)
    }
    
    func skipBackward() {
        let newTime = max(currentTime - skipInterval, 0)
        seek(to: newTime)
    }
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        audioPlayer?.rate = rate
        if rate != 1.0 {
            audioPlayer?.enableRate = true
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                self.currentTime = self.audioPlayer?.currentTime ?? 0
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var timeRemaining: TimeInterval {
        duration - currentTime
    }
    
    func formattedTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioPlayerManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopTimer()
        }
    }
}