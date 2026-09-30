import Foundation

enum CloudTranscriptionProvider: String, Codable, CaseIterable, Identifiable, Sendable {
  case openai
  case xai

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .openai:
      return LocalizationManager.localizedAppString("settings.cloudTranscription.provider.openai")
    case .xai:
      return LocalizationManager.localizedAppString("settings.cloudTranscription.provider.xai")
    }
  }
}
