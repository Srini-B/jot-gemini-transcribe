#if os(macOS)
import AVFoundation
import CVoiceIQAEC
import Foundation

/// Removes the far side's echo from a recorded mic track with WebRTC's AEC3,
/// using the recorded system output as the reference. The owner's voice is
/// not in the reference, so it stays, including over the far side. This is
/// the approach FluidVoice's meeting capture uses, run after the meeting.
///
/// MEASURED 2026-09-27. On a Meet call through laptop speakers the far
/// side's echo sat 23.5 dB above the mic's room tone; after this it sat
/// 0.5 dB above. A 30-minute track takes about 3 s on an M-series Mac.
public enum EchoCanceller {
    public enum Failure: Error { case unsupportedFormat, processing(Int32) }

    /// How far the reference is moved earlier. The system tap starts after
    /// the mic (`MeetingEngine.startRecording`), so without this the echo can
    /// reach the mic before its reference, which no canceller can remove.
    /// AEC3 finds the remaining delay itself. MEASURED 2026-09-27: 100 ms
    /// left the far side's echo 1.7 dB lower than 0 ms on a Meet call.
    static let referenceLead = 0.1

    /// Writes the cancelled mic track to `output`. Returns the canceller's
    /// last echo-reduction estimate in dB.
    @discardableResult
    public static func cancel(mic: URL, system: URL, output: URL) throws -> Double {
        let micFile = try AVAudioFile(forReading: mic, commonFormat: .pcmFormatInt16, interleaved: true)
        let systemFile = try AVAudioFile(forReading: system, commonFormat: .pcmFormatInt16, interleaved: true)
        let format = micFile.processingFormat
        guard format.channelCount == 1, systemFile.processingFormat.sampleRate == format.sampleRate,
              let aec = voiceiq_aec_create(Int32(format.sampleRate)) else { throw Failure.unsupportedFormat }
        defer { voiceiq_aec_destroy(aec) }

        try? FileManager.default.removeItem(at: output)
        let writer = try AVAudioFile(forWriting: output, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let frame = Int(voiceiq_aec_frame_samples(aec))
        let block = AVAudioFrameCount(frame * 100)
        let micBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: block)!
        let systemBuffer = AVAudioPCMBuffer(pcmFormat: systemFile.processingFormat, frameCapacity: block)!
        systemFile.framePosition = min(systemFile.length, AVAudioFramePosition(referenceLead * format.sampleRate))
        var far = [Int16](repeating: 0, count: frame)

        while micFile.framePosition < micFile.length {
            let count = AVAudioFrameCount(min(Int64(block), micFile.length - micFile.framePosition))
            try micFile.read(into: micBuffer, frameCount: count)
            systemBuffer.frameLength = 0
            let systemCount = AVAudioFrameCount(min(Int64(count), systemFile.length - systemFile.framePosition))
            if systemCount > 0 { try systemFile.read(into: systemBuffer, frameCount: systemCount) }
            let near = micBuffer.int16ChannelData![0], reference = systemBuffer.int16ChannelData![0]
            let whole = Int(micBuffer.frameLength) / frame * frame
            for start in stride(from: 0, to: whole, by: frame) {
                for index in 0..<frame {
                    far[index] = start + index < Int(systemBuffer.frameLength) ? reference[start + index] : 0
                }
                let status = voiceiq_aec_process(aec, far, near + start)
                guard status == 0 else { throw Failure.processing(status) }
            }
            try writer.write(from: micBuffer)
        }
        return voiceiq_aec_erle_db(aec)
    }
}
#endif
