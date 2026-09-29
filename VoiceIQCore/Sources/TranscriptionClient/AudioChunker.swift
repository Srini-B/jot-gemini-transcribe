import AVFoundation
import Foundation

/// Splits a long CAF into request-sized frame ranges for the batch transcriber.
///
/// Recordings are unbounded now, but one inline interactions request is not:
/// 20 MB of base64 FLAC is roughly ten to twelve minutes of 16 kHz speech. Each
/// cut is moved back to the quietest 100 ms inside a short window before the
/// nominal boundary, so a chunk edge lands between words rather than through one.
enum AudioChunker {
    /// Nominal chunk length. Ten minutes was the previous whole-recording cap,
    /// so this request size has a long dogfood history.
    static let maxChunkSeconds: Double = 600
    /// How far back from the nominal boundary to look for silence.
    static let searchWindowSeconds: Double = 8
    static let hopSeconds: Double = 0.1

    static func ranges(cafURL: URL) throws -> [Range<AVAudioFramePosition>] {
        let file = try AVAudioFile(forReading: cafURL, commonFormat: .pcmFormatInt16, interleaved: true)
        let rate = file.processingFormat.sampleRate
        let total = file.length
        let maxFrames = AVAudioFramePosition(rate * maxChunkSeconds)
        guard total > maxFrames else { return [0..<total] }

        var ranges: [Range<AVAudioFramePosition>] = []
        var start: AVAudioFramePosition = 0
        while start < total {
            let nominal = start + maxFrames
            guard nominal < total else {
                ranges.append(start..<total)
                break
            }
            let cut = quietestFrame(in: file, before: nominal)
            ranges.append(start..<cut)
            start = cut
        }
        return ranges
    }

    /// The start of the lowest-RMS hop inside `[boundary - window, boundary]`.
    private static func quietestFrame(in file: AVAudioFile, before boundary: AVAudioFramePosition) -> AVAudioFramePosition {
        let rate = file.processingFormat.sampleRate
        let window = AVAudioFramePosition(rate * searchWindowSeconds)
        let hop = AVAudioFrameCount(rate * hopSeconds)
        let windowStart = max(0, boundary - window)
        let frames = AVAudioFrameCount(boundary - windowStart)
        guard frames > hop,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)
        else { return boundary }
        file.framePosition = windowStart
        do { try file.read(into: buffer, frameCount: frames) } catch { return boundary }
        guard let samples = buffer.int16ChannelData?[0], buffer.frameLength > hop else { return boundary }
        let channels = Int(file.processingFormat.channelCount)

        var best = boundary
        var bestEnergy = Double.infinity
        var offset: AVAudioFrameCount = 0
        while offset + hop <= buffer.frameLength {
            var energy = 0.0
            for i in Int(offset)..<Int(offset + hop) {
                let s = Double(samples[i * channels])
                energy += s * s
            }
            if energy < bestEnergy {
                bestEnergy = energy
                best = windowStart + AVAudioFramePosition(offset)
            }
            offset += hop
        }
        return best
    }
}
