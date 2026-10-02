import XCTest
@testable import VoiceIQCore

/// MAI Transcribe 2's Clean/Verbatim choice reaches Azure in each gateway's
/// own field shape, and decides whether a failed cleanup strips fillers.
final class MAITranscribeStyleTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "maiTranscribeStyle")
    }

    func testStyleDefaultsToClean() {
        UserDefaults.standard.removeObject(forKey: "maiTranscribeStyle")
        XCTAssertEqual(SettingsStore().maiTranscribeStyle, .clean)
        SettingsStore().setMAITranscribeStyle(.verbatim)
        XCTAssertEqual(SettingsStore().maiTranscribeStyle, .verbatim)
    }

    func testOpenRouterSendsTheStyleUnderEnhancedModeModelOptions() {
        let options = GeminiClient.maiAzureOptions(style: .clean, via: .openRouter)
        XCTAssertEqual(options as NSDictionary,
                       ["enhancedMode": ["modelOptions": ["transcribeStyle": "clean"]]] as NSDictionary)
    }

    func testVercelSendsTheStyleFlat() {
        let options = GeminiClient.maiAzureOptions(style: .verbatim, via: .vercel)
        XCTAssertEqual(options as NSDictionary, ["transcribeStyle": "verbatim"] as NSDictionary)
    }

    func testMeetingOptionsKeepDiarizationAndTimestamps() {
        let openRouter = GeminiClient.maiAzureOptions(style: .clean, via: .openRouter, diarize: true)
        XCTAssertEqual(openRouter as NSDictionary, [
            "diarization": ["enabled": true],
            "enhancedMode": ["modelOptions": ["timestamps": "word", "transcribeStyle": "clean"]],
        ] as NSDictionary)
        let vercel = GeminiClient.maiAzureOptions(style: .clean, via: .vercel, diarize: true)
        XCTAssertEqual(vercel as NSDictionary, [
            "diarization": ["enabled": true], "timestamps": "word", "transcribeStyle": "clean",
        ] as NSDictionary)
    }

    func testOnlyVerbatimMAITranscriptsGetTheFillerFallback() {
        let service = GeminiTranscriptionService(client: GeminiClient(apiKey: { nil }))
        let policy = SettingsStore.FormattingPolicy(nativeSmart: true, cleanupPass: true)
        SettingsStore().setMAITranscribeStyle(.clean)
        XCTAssertFalse(service.transcriptKeepsFillers(source: .maiTranscribe, policy: policy))
        SettingsStore().setMAITranscribeStyle(.verbatim)
        XCTAssertTrue(service.transcriptKeepsFillers(source: .maiTranscribe, policy: policy))
    }
}
