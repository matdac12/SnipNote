//
//  HapticService.swift
//  SnipNote
//
//  Created by Claude on 01/12/25.
//

import UIKit

/// Service for providing haptic feedback throughout the app
class HapticService {
    static let shared = HapticService()
    private init() {}

    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    /// Prepare generators for immediate feedback
    func prepare() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
    }

    /// Light impact - for subtle interactions like button taps
    func light() {
        lightGenerator.impactOccurred()
    }

    /// Medium impact - for more significant actions like starting/stopping recording
    func medium() {
        mediumGenerator.impactOccurred()
    }

    /// Heavy impact - for major actions
    func heavy() {
        heavyGenerator.impactOccurred()
    }

    /// Success notification - for completed actions like processing complete
    func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    /// Warning notification - for alerts or warnings
    func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }

    /// Error notification - for failures
    func error() {
        notificationGenerator.notificationOccurred(.error)
    }
}
