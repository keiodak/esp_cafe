// ToneMaker.swift — coco duo (k.odk)
// Sounds the Cafe can't make itself, made here and written onto its tape (one tape = 131072 samples at its clock):
//  STRETCH  an audio file stretched ×4 … ×60 (Paulstretch: the spectrum kept, the phases thrown away), laid in a
//           circle so the tape loops without a seam — a word or a knock becomes a still cloud
//  CHORDS   the tape cut in 16 slices, a chord in each (a progression in a key): where the Cafe reads is the harmony

import Foundation
import AVFoundation
import Accelerate

enum ToneMaker {
    static let stretches: [Double] = [4, 10, 25, 60]
    static let sets = ["MAJ7", "MINOR", "SERIES", "CLUSTER"]
    static let keys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // MARK: the file, mono, at the Cafe's clock

    /// up to `maxCount` samples from where the sound starts (the silence before it skipped)
    static func mono(url: URL, rate: Double, maxCount: Int) throws -> [Float] {
        let f = try AVAudioFile(forReading: url)
        let fmt = f.processingFormat
        let srcRate = fmt.sampleRate
        let frames = AVAudioFrameCount(min(Double(f.length), 60 * srcRate))
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else {
            throw AudioLoader.Failure(errorDescription: "empty or unreadable file")
        }
        try f.read(into: buf, frameCount: frames)
        let n = Int(buf.frameLength), ch = Int(fmt.channelCount)
        guard n > 0, ch > 0, let data = buf.floatChannelData else { throw AudioLoader.Failure(errorDescription: "no audio in the file") }
        var m = [Float](repeating: 0, count: n)
        for c in 0..<ch { let p = data[c]; for i in 0..<n { m[i] += p[i] / Float(ch) } }
        var peak: Float = 0
        for v in m { peak = max(peak, abs(v)) }
        guard peak > 0.0001 else { throw AudioLoader.Failure(errorDescription: "the file is silent") }
        let start = m.firstIndex { abs($0) > peak * 0.05 } ?? 0
        let step = srcRate / rate
        let outN = min(maxCount, Int(Double(n - start) / step))
        guard outN > 64 else { throw AudioLoader.Failure(errorDescription: "the file is too short") }
        var out = [Float](repeating: 0, count: outN)
        for i in 0..<outN {
            let pos = Double(start) + Double(i) * step
            let j = min(Int(pos), n - 1)
            let fr = Float(pos - Double(j))
            let a = m[j], b = j + 1 < n ? m[j + 1] : a
            out[i] = (a + (b - a) * fr) / peak
        }
        return out
    }

    /// floats (about ±1) -> the tape's 12-bit words, brought up to the Cafe's level
    static func tape(_ x: [Float]) -> [UInt16] {
        var peak: Float = 0
        for v in x { peak = max(peak, abs(v)) }
        let g: Float = peak > 0.00001 ? 0.9 / peak : 1
        return x.map { UInt16(max(0, min(4095, 2048 + Int(($0 * g * 2047).rounded())))) }
    }

    // MARK: STRETCH

    /// Paulstretch onto one tape: frames of 4096 read slowly through `x`, their phases made random, laid back in a
    /// circle (the last frames overlap the first) so the tape loops without a seam
    static func stretch(_ x: [Float], by s: Double, count: Int = TAPE) -> [Float] {
        let N = 4096, half = N / 2, log2n = vDSP_Length(12)
        guard !x.isEmpty, let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        var win = [Float](repeating: 0, count: N)
        vDSP_hann_window(&win, vDSP_Length(N), Int32(vDSP_HANN_NORM))
        let hop = N / 4
        let frames = count / hop
        let hopIn = Double(hop) / s
        var out = [Float](repeating: 0, count: count)
        var frame = [Float](repeating: 0, count: N)
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        for f in 0..<frames {
            let at = Int(Double(f) * hopIn)
            for i in 0..<N { frame[i] = x[(at + i) % x.count] * win[i] }
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var z = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ctoz($0, 2, &z, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &z, 1, log2n, FFTDirection(FFT_FORWARD))
                    // keep each bin's size, throw its phase away (DC and Nyquist sit in [0]: only their sign)
                    rp[0] = abs(rp[0]) * (Bool.random() ? 1 : -1)
                    ip[0] = abs(ip[0]) * (Bool.random() ? 1 : -1)
                    for k in 1..<half {
                        let m = (rp[k] * rp[k] + ip[k] * ip[k]).squareRoot()
                        let ph = Float.random(in: 0..<(2 * .pi))
                        rp[k] = m * cos(ph); ip[k] = m * sin(ph)
                    }
                    vDSP_fft_zrip(setup, &z, 1, log2n, FFTDirection(FFT_INVERSE))
                    frame.withUnsafeMutableBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ztoc(&z, 1, $0, 2, vDSP_Length(half))
                        }
                    }
                }
            }
            let base = f * hop
            for i in 0..<N { out[(base + i) % count] += frame[i] * win[i] }
        }
        return out
    }

    // MARK: CHORDS

    /// the 16 chords of a set (semitones over the key's root, C3 = 48)
    static func progression(_ set: Int) -> [[Int]] {
        switch set {
        case 0:  // MAJ7: a soft major walk
            return [[0, 4, 7, 11, 14], [9, 12, 16, 19, 23], [5, 9, 12, 16, 19], [7, 11, 14, 17, 21],
                    [4, 7, 11, 14, 19], [9, 13, 16, 19, 23], [2, 5, 9, 12, 16], [7, 11, 14, 17, 21],
                    [0, 7, 11, 14, 16], [5, 9, 12, 16, 21], [10, 14, 17, 21, 24], [3, 7, 10, 14, 19],
                    [2, 5, 9, 12, 17], [7, 10, 14, 17, 22], [0, 4, 9, 11, 14], [0, 7, 11, 16, 19]]
        case 1:  // MINOR: dark, slow
            return [[0, 3, 7, 10, 14], [8, 12, 15, 19, 22], [5, 8, 12, 15, 19], [7, 10, 14, 17, 20],
                    [3, 7, 10, 14, 17], [10, 14, 17, 20, 24], [8, 12, 15, 18, 22], [7, 11, 14, 17, 20],
                    [0, 3, 7, 10, 15], [5, 8, 12, 15, 20], [1, 5, 8, 12, 15], [7, 11, 14, 17, 22],
                    [0, 3, 7, 14, 15], [8, 12, 15, 19, 24], [2, 5, 8, 12, 14], [7, 11, 14, 17, 23]]
        case 2:  // SERIES: the harmonic series climbing — slice k = overtones k … k+4 of the root (in cents)
            return (0..<16).map { k in (0..<5).map { j in -1000 - (k + j + 1) } }   // (negative = overtone number)
        default: // CLUSTER: stacked seconds and fourths, wandering
            var g = SystemRandomNumberGenerator()
            return (0..<16).map { _ in
                let r = Int.random(in: 0...11, using: &g)
                let steps = [[0, 2, 4, 7, 9], [0, 1, 5, 7, 12], [0, 5, 10, 14, 15], [0, 2, 3, 7, 14]].randomElement(using: &g)!
                return steps.map { $0 + r }
            }
        }
    }

    /// 16 slices, a chord in each: a few soft partials per note, a little detune, a fade at every edge
    static func chords(set: Int, key: Int, rate: Double, count: Int = TAPE) -> [Float] {
        let prog = progression(set)
        let slice = count / 16
        var out = [Float](repeating: 0, count: count)
        let root = 48 + key
        for (si, notes) in prog.enumerated() {
            let base = si * slice
            var freqs: [Double] = []
            for n in notes {
                if n <= -1000 {                                        // SERIES: an overtone of the root
                    let h = Double(-(n + 1000))
                    freqs.append(440 * pow(2, Double(root - 12 - 69) / 12) * h)
                } else {
                    freqs.append(440 * pow(2, Double(root + n - 69) / 12))
                }
            }
            for (vi, f0) in freqs.enumerated() {
                let det = 1 + (Double(vi % 3) - 1) * 0.0015            // (a little apart: it breathes)
                let amp = 0.22 / Double(freqs.count).squareRoot()
                for h in 1...6 {
                    let f = f0 * det * Double(h)
                    guard f < rate * 0.45 else { break }
                    let a = amp / pow(Double(h), 1.4)
                    let w = 2 * Double.pi * f / rate
                    let ph = Double.random(in: 0..<(2 * .pi))
                    for i in 0..<slice {
                        out[base + i] += Float(a * sin(w * Double(i) + ph))
                    }
                }
            }
            let fade = min(256, slice / 8)                              // (~8 ms each side: no click between slices)
            for i in 0..<fade {
                let g = Float(i) / Float(fade)
                out[base + i] *= g
                out[base + slice - 1 - i] *= g
            }
        }
        return out
    }
}
