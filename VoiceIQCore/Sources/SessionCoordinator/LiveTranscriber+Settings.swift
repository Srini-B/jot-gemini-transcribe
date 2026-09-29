import Foundation

extension LiveTranscriber {
    /// Builds a live session, or nil — which is the normal answer, since live is
    /// experimental and off by default.
    ///
    /// Kept out of the coordinator, which should know about neither the Keychain
    /// nor the Dictionary. Shared by the macOS and iOS apps.
    @MainActor
    public static func makeFromSettings() -> LiveTranscribing? {
        let settings = SettingsStore()
        guard settings.liveTranscriptionActive else { return nil }
        // A live path that is reliably broken is worse than one that is off: every
        // attempt costs a handshake and then the full upload anyway, so the user
        // pays latency on every dictation for a feature that never delivers. Stop
        // trying after a run of failures; a single success clears the streak, so a
        // bad hotel wifi heals itself without anyone touching a setting.
        let stats = LiveStats()
        if stats.shouldStopTrying {
            Log.transcription.info(
                "live disabled for now after \(stats.consecutiveFailures) consecutive failures — uploading instead"
            )
            return nil
        }
        // The gateways have no live socket, so the upload path carries the
        // whole dictation on those providers.
        let dictionary = DictionaryStore()
        let session: LiveTranscriptionSession
        let liveModel: String
        let route = settings.activeRoute
        if settings.transcriptionSource == .elevenLabs {
            // Any route: the socket is ElevenLabs', whoever writes afterwards.
            guard let key = KeychainStore.loadElevenLabsKey(), !key.isEmpty else { return nil }
            let dialect = ElevenLabsLiveDialect(keyterms: dictionary.sanitizedVocabulary(),
                                                noVerbatim: settings.smartTranscriptionEnabled)
            return LiveTranscriber(
                session: LiveTranscriptionSession(
                    transport: WebSocketTransport.elevenLabs(url: dialect.socketURL, apiKey: { key }),
                    dialect: dialect
                ),
                modelID: dialect.model,
                replacementRules: { DictionaryStore().replacementRules() }
            )
        }
        guard route.supportsLiveTranscription else { return nil }
        switch route.provider {
        case .gemini:
            guard let key = KeychainStore.loadAPIKey(), !key.isEmpty else { return nil }
            liveModel = settings.geminiConfig.liveModel
            session = LiveTranscriptionSession(
                transport: WebSocketTransport(apiKey: { key }),
                setup: LiveSetup(
                    model: liveModel,
                    smart: settings.smartTranscriptionEnabled,
                    // The same terms the batch path biases with, so switching modes
                    // does not quietly change how someone's name gets spelled.
                    customVocabulary: dictionary.vocabulary()
                )
            )
        case .openAI:
            guard let key = KeychainStore.loadOpenAIKey(), !key.isEmpty else { return nil }
            let config = settings.openAIConfig
            liveModel = config.liveModel
            session = LiveTranscriptionSession(
                transport: WebSocketTransport.openAI(apiKey: { key }),
                dialect: OpenAILiveDialect(model: liveModel, delay: config.liveDelay,
                                           keywords: dictionary.sanitizedVocabulary())
            )
        }
        return LiveTranscriber(
            session: session,
            modelID: liveModel,
            replacementRules: { DictionaryStore().replacementRules() }
        )
    }
}
