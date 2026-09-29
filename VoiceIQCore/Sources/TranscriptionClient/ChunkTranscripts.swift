import AVFoundation
import Foundation

/// Transcripts of the chunks of one recording that have already come back,
/// keyed by the exact frame range each was cut at. A retry that chunks the
/// same CAF gets the same ranges and skips those requests; a different cut
/// (a changed chunk length, say) simply misses and re-sends. Lives next to
/// the audio as `chunks.json` and is deleted once every chunk is in.
struct ChunkTranscripts: Codable, Equatable {
    private var byRange: [String: String] = [:]

    var count: Int { byRange.count }

    subscript(range: Range<AVAudioFramePosition>) -> String? {
        get { byRange[Self.key(range)] }
        set { byRange[Self.key(range)] = newValue }
    }

    private static func key(_ range: Range<AVAudioFramePosition>) -> String {
        "\(range.lowerBound)-\(range.upperBound)"
    }

    static func read(from url: URL) -> ChunkTranscripts {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ChunkTranscripts.self, from: data)
        else { return ChunkTranscripts() }
        return decoded
    }

    func write(to url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
