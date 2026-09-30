import Combine
import Foundation

@MainActor
final class CloudTranscriptionSettings: ObservableObject {
  static let shared = CloudTranscriptionSettings()
  private static let preferenceKey = "cloudTranscription.provider"
  private let defaults: UserDefaults

  @Published var selectedProvider: CloudTranscriptionProvider {
    didSet { defaults.set(selectedProvider.rawValue, forKey: Self.preferenceKey) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    selectedProvider = defaults.string(forKey: Self.preferenceKey)
      .flatMap(CloudTranscriptionProvider.init(rawValue:)) ?? .xai
  }
}
