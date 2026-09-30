import Foundation
import Testing
@testable import SnipNote

@MainActor
struct CloudTranscriptionSettingsTests {
  @Test func preferenceSurvivesStoreRecreation() throws {
    let name = "CloudTranscriptionSettingsTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = CloudTranscriptionSettings(defaults: defaults)
    settings.selectedProvider = .xai
    #expect(defaults.string(forKey: "cloudTranscription.provider") == "xai")
    #expect(CloudTranscriptionSettings(defaults: defaults).selectedProvider == .xai)
  }

  @Test func missingOrInvalidPreferenceUsesOpenAI() throws {
    let name = "CloudTranscriptionSettingsTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(CloudTranscriptionSettings(defaults: defaults).selectedProvider == .openai)
    defaults.set("unknown", forKey: "cloudTranscription.provider")
    #expect(CloudTranscriptionSettings(defaults: defaults).selectedProvider == .openai)
  }
}
