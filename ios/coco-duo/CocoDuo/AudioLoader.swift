// AudioLoader.swift — coco duo (k.odk)
// An audio file -> the Cafe's tape: mono, resampled to the Cafe's clock, 12-bit (0…4095, 2048 = silence).

import Foundation
import AVFoundation

enum AudioLoader {
    struct Failure: LocalizedError { let errorDescription: String? }

    /// `rate` = the Cafe's current clock (samples per second). At most one tape (131072 samples).
    static func tapeSamples(url: URL, rate: Double) throws -> [UInt16] {
        let f = try AVAudioFile(forReading: url)
        let fmt = f.processingFormat                        // always float, one buffer per channel
        let srcRate = fmt.sampleRate
        let want = min(Double(f.length), Double(TAPE) * srcRate / rate + 2)
        let frames = AVAudioFrameCount(max(0, want))
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else {
            throw Failure(errorDescription: "empty or unreadable file")
        }
        try f.read(into: buf, frameCount: frames)
        let n = Int(buf.frameLength), ch = Int(fmt.channelCount)
        guard n > 0, ch > 0, let data = buf.floatChannelData else { throw Failure(errorDescription: "no audio in the file") }

        // mix down to mono
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<ch {
            let p = data[c]
            for i in 0..<n { mono[i] += p[i] }
        }
        var peak: Float = 0
        for i in 0..<n { mono[i] /= Float(ch); peak = max(peak, abs(mono[i])) }
        let gain: Float = peak > 0.0001 ? 0.9 / peak : 1          // bring it up to the Cafe's level

        // resample (straight lines between the file's samples) to the Cafe's clock
        let step = srcRate / rate
        let outN = min(TAPE, Int(Double(n) / step))
        var out = [UInt16](repeating: 2048, count: outN)
        for i in 0..<outN {
            let pos = Double(i) * step
            let j = min(Int(pos), n - 1)
            let fr = Float(pos - Double(j))
            let a = mono[j], b = j + 1 < n ? mono[j + 1] : a
            let v = (a + (b - a) * fr) * gain
            out[i] = UInt16(max(0, min(4095, 2048 + Int((v * 2047).rounded()))))
        }
        return out
    }
}
