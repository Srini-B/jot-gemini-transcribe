import AVFoundation
import Foundation

/// CAF → FLAC transcode at key-up. Measured: 5ms/14ms/231ms for 5s/30s/10min —
/// invisible inside the latency budget.
public enum FLACEncoder {
    public struct Output: Sendable {
        public let url: URL
        public let byteCount: Int
        public let encodeSeconds: Double
    }

    public enum EncodeError: Error {
        case readFailed(String)
        case writeFailed(String)
    }

    /// 16 kHz mono samples to FLAC bytes, through a temporary file.
    public static func encode(samples: [Int16], sampleRate: Double = 16_000) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voiceiq-\(UUID()).flac")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1]
        do {
            let writer = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
            var offset = 0
            while offset < samples.count {
                let count = min(65_536, samples.count - offset)
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                buffer.frameLength = AVAudioFrameCount(count)
                samples.withUnsafeBufferPointer { source in
                    buffer.int16ChannelData![0].update(from: source.baseAddress! + offset, count: count)
                }
                try writer.write(from: buffer)
                offset += count
            }
        } catch {
            throw EncodeError.writeFailed(String(describing: error))
        }
        return try Data(contentsOf: url)
    }

    public static func encode(cafURL: URL, flacURL: URL) throws -> Output {
        try encode(cafURL: cafURL, flacURL: flacURL, frameRange: nil)
    }

    public static func encode(cafURL: URL, flacURL: URL, frameRange: Range<AVAudioFramePosition>?) throws -> Output {
        let started = Date()
        try? FileManager.default.removeItem(at: flacURL)

        let reader: AVAudioFile
        do {
            reader = try AVAudioFile(forReading: cafURL, commonFormat: .pcmFormatInt16, interleaved: true)
        } catch {
            throw EncodeError.readFailed(String(describing: error))
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: reader.processingFormat.sampleRate,
            AVNumberOfChannelsKey: reader.processingFormat.channelCount,
        ]
        do {
            let writer = try AVAudioFile(
                forWriting: flacURL, settings: settings,
                commonFormat: .pcmFormatInt16, interleaved: true
            )
            let chunk = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 65_536)!
            // read(into:) can throw a spurious nilError at EOF with an Int16 client
            // format — guard on framePosition instead (probed on macOS 26).
            let range = frameRange ?? 0..<reader.length
            reader.framePosition = max(0, range.lowerBound)
            while reader.framePosition < min(reader.length, range.upperBound) {
                let count = min(chunk.frameCapacity, AVAudioFrameCount(range.upperBound - reader.framePosition))
                try reader.read(into: chunk, frameCount: count)
                if chunk.frameLength == 0 { break }
                try writer.write(from: chunk)
            }
        } catch {
            throw EncodeError.writeFailed(String(describing: error))
        }

        let bytes = ((try? FileManager.default.attributesOfItem(atPath: flacURL.path))?[.size] as? Int) ?? 0
        return Output(url: flacURL, byteCount: bytes, encodeSeconds: Date().timeIntervalSince(started))
    }
}
