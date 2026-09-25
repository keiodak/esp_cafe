// CameraRig.swift — coco duo (k.odk)
// Camera mode, tuned like Sunnandæg: the camera is cut into an 8 × 16 mosaic, each of the 8 pads owns
// a 4 × 4 block, and every frame its pointer moves 30 % toward the cell that MOVES most / is BRIGHTEST / DARKEST.
// While it is on, fingers don't move the pads; the pads' moves are sent to the Cafes as usual.

import Foundation
import QuartzCore

/// what the pads draw (kept apart so the whole screen doesn't redraw every frame)
final class CameraState: ObservableObject {
    @Published var mosaicBrightness: [[Double]] = Array(repeating: Array(repeating: 0.5, count: 16), count: 8)
    @Published var cameraMotion: Double = 0.0
}

final class CameraRig: ObservableObject {
    static let attractNames = ["MOTION", "BRIGHT", "DARK"]

    @Published var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            controller.mosaicEnabled = enabled
            if enabled { controller.start() } else { controller.stop(); state.cameraMotion = 0 }
        }
    }
    /// 0 = MOTION / 1 = BRIGHT / 2 = DARK
    @Published var attractMode = 0
    @Published var usesFront = true { didSet { controller.setPosition(usesFront ? .front : .back) } }
    @Published var sensitivity = 0.5
    @Published var fps = 30 { didSet { controller.setFrameRate(fps) } }

    let state = CameraState()
    private let controller = CameraController()
    private var lastMosaic: Double = 0
    private var lastAttract: Double = 0

    /// the 8 pads, and what to do after a pad moved (send it to its Cafe)
    var axes: [PadAxis] = []
    var onPadMoved: ((Int) -> Void)?

    init() {
        controller.setPosition(.front)
        controller.onFrameUpdate = { [weak self] frame in
            guard let self, let grid = frame.mosaicBrightness else { return }
            let motion = frame.mosaicMotion
            DispatchQueue.main.async {
                guard self.enabled else { return }
                let now = CACurrentMediaTime()
                self.attract(brightness: grid, motion: motion ?? grid)    // every frame, like Sunnandæg
                let level = ((frame.motion ?? 0) * 20).rounded() / 20
                if abs(self.state.cameraMotion - level) > 0.01 { self.state.cameraMotion = level }
                guard now - self.lastMosaic >= 0.1 else { return }   // the mosaic redraws at most 10×/s
                self.lastMosaic = now
                self.state.mosaicBrightness = grid
            }
        }
    }

    func warm() { controller.warmSession() }

    /// each pad's pointer moves 30 % of the way toward the chosen cell of its 4 × 4 block
    private func attract(brightness: [[Double]], motion: [[Double]]) {
        guard axes.count == 8, brightness.count >= 8, brightness[0].count >= 16,
              motion.count >= 8, motion[0].count >= 16 else { return }
        // SENS 0.5 = Sunnandæg's fixed 0.22; higher = reacts to smaller movements
        let threshold = 0.02 + 0.40 * (1 - min(max(sensitivity, 0), 1))
        for i in 0..<8 {
            let r0 = (i / 4) * 4, c0 = (i % 4) * 4
            var bestRow = 0, bestCol = 0, best = -Double.infinity
            for dr in 0..<4 {
                for dc in 0..<4 {
                    let score: Double
                    switch attractMode {
                    case 1: score = brightness[r0 + dr][c0 + dc]
                    case 2: score = -brightness[r0 + dr][c0 + dc]
                    default: score = motion[r0 + dr][c0 + dc]
                    }
                    if score > best { best = score; bestRow = dr; bestCol = dc }
                }
            }
            if attractMode == 0 && best < threshold { continue }
            let tx = (Double(bestCol) + 0.5) / 4.0
            let ty = 1.0 - (Double(bestRow) + 0.5) / 4.0
            let a = axes[i]
            let nx = a.x + (tx - a.x) * 0.3, ny = a.y + (ty - a.y) * 0.3
            var moved = false
            if abs(a.x - nx) > 0.0005 { a.x = nx; moved = true }
            if abs(a.y - ny) > 0.0005 { a.y = ny; moved = true }
            if moved { onPadMoved?(i) }
        }
    }
}
