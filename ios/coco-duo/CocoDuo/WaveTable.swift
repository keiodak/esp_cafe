// WaveTable.swift — coco duo (k.odk)
// WAVE (BLE mode 6): an audio file -> a wavetable for the Cafe: 64 frames of 256 samples (one cycle each), taken at
// 64 even places through the file. At each place the pitch is found (autocorrelation, 40 Hz … 1 kHz) and exactly
// one period, from an upward zero crossing, is stretched to 256 samples — so the table walks through the file's
// timbres. Where no pitch is found (noise, breath) the nearest pitched cycle is used. Each frame: DC out, the top
// gently rounded, blended a little with its neighbours, all at the same loudness (steady, no bursts). -> 16384 twelve-bit samples for the start of the tape ("W").

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
        guard n > win + maxLag + 4 else { throw AudioLoader.Failure(errorDescription: "the file is too short") }
        // 1) one cycle per place; a place with no clear pitch (noise, breath) is left empty for now
        var cycles = [[Float]?](repeating: nil, count: frames)
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
            guard best > 0 && bestR > 0.6 else { continue }
            // one period from an upward zero crossing, stretched to 256
            var z = start
            while z < start + best && !(mono[z] <= 0 && mono[z + 1] > 0) { z += 1 }
            var cyc = [Float](repeating: 0, count: size)
            for k in 0..<size {
                let pos = Double(z) + Double(k) * Double(best) / Double(size)
                let j = min(Int(pos), n - 2), fr = Float(pos - Double(j))
                cyc[k] = mono[j] + (mono[j + 1] - mono[j]) * fr
            }
            cycles[fi] = cyc
        }
        // 2) the empty places take the nearest pitched cycle (a steady tone instead of a burst of noise)
        let found = cycles.indices.filter { cycles[$0] != nil }
        guard !found.isEmpty else { throw AudioLoader.Failure(errorDescription: "no pitch found in the file") }
        for fi in 0..<frames where cycles[fi] == nil {
            let near = found.min { abs($0 - fi) < abs($1 - fi) }!
            cycles[fi] = cycles[near]
        }
        // 3) each cycle: DC out, the seam closed, the top gently rounded (two passes of a 1-2-1 filter, round the cycle)
        var tab = cycles.map { $0! }
        for fi in 0..<frames {
            var c = tab[fi]
            let dc = c.reduce(0, +) / Float(size)
            for k in 0..<size { c[k] -= dc }
            for _ in 0..<2 {
                var t = c
                for k in 0..<size { t[k] = 0.25 * c[(k + size - 1) % size] + 0.5 * c[k] + 0.25 * c[(k + 1) % size] }
                c = t
            }
            tab[fi] = c
        }
        // 4) neighbouring frames blended a little (1-2-1): moving through the table does not jump
        var smooth = tab
        for fi in 0..<frames {
            let a = tab[max(0, fi - 1)], b = tab[fi], c = tab[min(frames - 1, fi + 1)]
            for k in 0..<size { smooth[fi][k] = 0.25 * a[k] + 0.5 * b[k] + 0.25 * c[k] }
        }
        // 5) every frame at the same loudness (RMS), the peak kept under the ceiling
        var out = [UInt16](repeating: 2048, count: frames * size)
        for fi in 0..<frames {
            let c = smooth[fi]
            var sq: Float = 0, pk: Float = 0
            for v in c { sq += v * v; pk = max(pk, abs(v)) }
            let rms = (sq / Float(size)).squareRoot()
            var g: Float = rms > 1e-5 ? 0.33 / rms : 0
            if pk * g > 0.95 { g = 0.95 / pk }
            for k in 0..<size {
                out[fi * size + k] = UInt16(max(0, min(4095, 2048 + Int((c[k] * g * 2047).rounded()))))
            }
        }
        return out
    }
}
