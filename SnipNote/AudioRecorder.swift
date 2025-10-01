//
//  AudioRecorder.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation
import AVFoundation

#if canImport(AVFAudio)
import AVFAudio
#endif

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingLevel: Float = 0.0
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingSession = AVAudioSession.sharedInstance()
    private var levelTimer: Timer?
    
    override init() {
        super.init()
        setupRecordingSession()
    }
    
    private func setupRecordingSession() {
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)
            
            AVAudioApplication.requestRecordPermission { allowed in
                DispatchQueue.main.async {
                    if !allowed {
                        print("Recording permission denied")
                    }
                }
            }
        } catch {
            print("Failed to setup recording session: \(error)")
        }
    }
    
    func startRecording() -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsPath.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000, // Optimized for speech recognition (OpenAI standard)
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 64000 // 64kbps - sufficient for clear speech transcription
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            isRecording = true
            startLevelTimer()
            
            return audioURL
        } catch {
            print("Failed to start recording: \(error)")
            return nil
        }
    }
    
    func pauseRecording() {
        guard let recorder = audioRecorder, isRecording else { return }
        
        recorder.pause()
        isPaused = true
        stopLevelTimer()
    }
    
    func resumeRecording() {
        guard let recorder = audioRecorder, isPaused else { return }
        
        recorder.record()
        isPaused = false
        startLevelTimer()
    }
    
    func stopRecording() -> URL? {
        guard let recorder = audioRecorder else { return nil }
        
        recorder.stop()
        isRecording = false
        isPaused = false
        stopLevelTimer()
        
        return recorder.url
    }
    
    func cancelRecording() {
        guard let recorder = audioRecorder else { return }
        
        let recordingURL = recorder.url
        recorder.stop()
        isRecording = false
        isPaused = false
        stopLevelTimer()
        
        // Delete the recording file
        deleteRecording(at: recordingURL)
    }
    
    private func startLevelTimer() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.audioRecorder?.updateMeters()
            let level = self.audioRecorder?.averagePower(forChannel: 0) ?? -80
            
            DispatchQueue.main.async {
                self.recordingLevel = self.normalizeLevel(level)
            }
        }
    }
    
    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
        recordingLevel = 0.0
    }
    
    private func normalizeLevel(_ level: Float) -> Float {
        let minLevel: Float = -80
        let maxLevel: Float = 0
        
        let normalizedLevel = max(0, (level - minLevel) / (maxLevel - minLevel))
        return normalizedLevel
    }
    
    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording failed")
        }
    }
}
