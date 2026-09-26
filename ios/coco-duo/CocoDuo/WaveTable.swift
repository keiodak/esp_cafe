// WaveTable.swift — coco duo (k.odk)
// WAVE (BLE mode 6): an audio file -> a wavetable for the Cafe: 64 frames of 256 samples (one cycle each), taken at
// 64 even places through the file. At each place the pitch is found (autocorrelation, 40 Hz … 1 kHz) and exactly
// one period, from an upward zero crossing, is stretched to 256 samples — so the table walks through the file's
// timbres. Where no pitch is found (noise, breath) 256 samples are taken as they are. Each frame: DC out, the seam
// smoothed (the end runs into the start), levelled. -> 16384 twelve-bit samples for the start of the tape ("W").

import Foundation
import AVFoundation

enum WaveTable {
    static let frames = 64, size = 256

    static func make(url: URL) throws -> [UInt16] {
        let f = try AVAudioFile(forReading: url)
        let fmt = f.processingFormat
        let sr = fmt.sampleRate
        let want = min(f.length, AVAudioFramePosition(sr * 60))             // the first minute is plenty
        guard want > 2048, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(want)) else {
            throw AudioLoader.Failure(errorDescription: "the file is too short")
        }
        try f.read(into: buf, frameCount: AVAudioFrameCount(want))
        let n = Int(buf.frameLength), ch = Int(fmt.channelCount)
        guard n > 2048, let data = buf.floatChannelData else { throw AudioLoader.Failure(errorDescription: "no audio in the file") }
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<ch { let p = data[c]; for i in 0..<n { mono[i] += p[i] / Float(ch) } }

        let minLag = Int(sr / 1000), maxLag = Int(sr / 40), win = 2048
        var out = [UInt16](repeating: 2048, count: frames * size)
        for fi in 0..<frames {
            let start = min(n - win - maxLag - 1, max(0, Int(Double(fi) / Double(frames - 1) * Double(n - win - maxLag - 1))))
            // the period: the best normalised autocorrelation between 1 ms and 25 ms
            var best = 0, bestR: Float = 0
            var e0: Float = 0
            for i in 0..<win { e0 += mono[start + i] * mono[start + i] }
            if e0 > 1e-6 {
                var lag = minLag
                while lag <= maxLag {
                    var r: Float = 0, e1: Float = 0
                    var i = 0
                    while i < win { let a = mono[start + i], b = mono[start + i + lag]; r += a * b; e1 += b * b; i += 2 }
                    let nr = r / max(1e-9, (e0 * 0.5 * e1).squareRoot())
                    if nr > bestR { bestR = nr; best = lag }
                    lag += 1
                }
            }
            var cyc = [Float](repeating: 0, count: size)
            if best > 0 && bestR > 0.55 {
                // one period from an upward zero crossing, stretched to 256
                var z = start
                while z < start + best && !(mono[z] <= 0 && mono[z + 1] > 0) { z += 1 }
                for k in 0..<size {
                    let pos = Double(z) + Double(k) * Double(best) / Double(size)
                    let j = min(Int(pos), n - 2), fr = Float(pos - Double(j))
                    cyc[k] = mono[j] + (mono[j + 1] - mono[j]) * fr
                }
            } else {
                for k in 0..<size { cyc[k] = mono[min(n - 1, start + k)] }
            }
            // DC out, the seam smoothed over 16 samples, levelled to the full range
            let dc = cyc.reduce(0, +) / Float(size)
            for k in 0..<size { cyc[k] -= dc }
            let seam = 16
            for k in 0..<seam {
                let w = Float(k) / Float(seam)
                cyc[size - seam + k] = cyc[size - seam + k] * (1 - w) + cyc[k] * w * 0.5 + cyc[size - seam + k] * w * 0.5
            }
            var pk: Float = 0
            for v in cyc { pk = max(pk, abs(v)) }
            let g: Float = pk > 1e-5 ? 0.92 / pk : 0
            for k in 0..<size {
                out[fi * size + k] = UInt16(max(0, min(4095, 2048 + Int((cyc[k] * g * 2047).rounded()))))
            }
        }
        return out
    }
}
