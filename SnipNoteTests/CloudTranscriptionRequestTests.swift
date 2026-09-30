import Foundation
import Testing
@testable import SnipNote

struct CloudTranscriptionRequestTests {
  @Test func providerRequestPreservesAuthenticationAndAudio() throws {
    var base = URLRequest(url: try #require(URL(string: "https://test.invalid/audio/transcriptions")))
    base.setValue("Bearer fixture-token", forHTTPHeaderField: "Authorization")
    base.setValue("fixture-anon", forHTTPHeaderField: "apikey")
    let audio = Data([0, 1, 255, 13, 10])
    let request = CloudTranscriptionRequest.make(baseRequest: base, audioData: audio, language: "it", provider: .xai, boundary: "fixture-boundary")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
    #expect(request.value(forHTTPHeaderField: "apikey") == "fixture-anon")
    #expect(request.value(forHTTPHeaderField: "X-SnipNote-Task") == "transcription")
    #expect(request.value(forHTTPHeaderField: "X-SnipNote-Transcription-Provider") == "xai")
    let body = try #require(request.httpBody)
    #expect(body.range(of: audio) != nil)
    let text = String(decoding: body, as: UTF8.self)
    #expect(!text.contains("name=\"model\""))
    let language = try #require(text.range(of: "name=\"language\""))
    let file = try #require(text.range(of: "name=\"file\""))
    #expect(language.lowerBound < file.lowerBound)
  }

  @Test func autoLanguageIsOmitted() throws {
    let base = URLRequest(url: try #require(URL(string: "https://test.invalid")))
    let request = CloudTranscriptionRequest.make(baseRequest: base, audioData: Data([1]), language: nil, provider: .openai, boundary: "boundary")
    let text = String(decoding: try #require(request.httpBody), as: UTF8.self)
    #expect(!text.contains("name=\"language\""))
    #expect(request.value(forHTTPHeaderField: "X-SnipNote-Transcription-Provider") == "openai")
  }
}
