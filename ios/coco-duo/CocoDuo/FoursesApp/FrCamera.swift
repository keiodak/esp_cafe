// FrCamera.swift — Fourses (k.odk)
// (in coco duo: the Fourses app as it is, inside FA — iOS · FOURSES)
// The camera: its live picture shows through the shapes, and each shape reads how bright it is inside (and what
// moves there) as its own voltage — a light-dependent source joined to what the shape covers.

import AVFoundation
import Combine
import Foundation
import QuartzCore

extension FA {
/// what the board draws from the camera (kept apart: it changes ~10x a second)
final class CameraState: ObservableObject {
    @Published var mosaic: [[Double]] = Array(repeating: Array(repeating: 0.5, count: 16), count: 8)
    /// each shape's light now (0…1), for the board to glow with
    @Published var shapeLight: [Double] = []
}

final class FrCamera: ObservableObject {
    @Published var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            controller.mosaicEnabled = enabled
            if enabled { controller.start() } else { running = false; controller.stop(); state.shapeLight = [] }
        }
    }
    /// the session is running: only then is the picture shown (a preview joined while the session is still being set
    /// up waits for it on the main thread — the first time, a freeze)
    @Published private(set) var running = false
    @Published var front = true { didSet { controller.setPosition(front ? .front : .back) } }
    var session: AVCaptureSession { controller.session }
    let state = CameraState()
    /// every frame's mosaic (8 × 16, 0…1)
    var onGrid: (([[Double]]) -> Void)?
    private let controller = CameraController()
    private var lastShown = 0.0

    init() {
        controller.setPosition(.front)                     // (the front camera, by default)
        controller.onRunning = { [weak self] on in
            DispatchQueue.main.async { guard let self else { return }; self.running = on && self.enabled }
        }
        controller.warmSession()                          // (the camera set up now, at launch, not when CAM is first pressed)
        controller.onFrameUpdate = { [weak self] frame in
            guard let self, let grid = frame.mosaicBrightness else { return }
            DispatchQueue.main.async {
                guard self.enabled else { return }
                self.onGrid?(grid)
                let t = CACurrentMediaTime()
                if t - self.lastShown >= 0.1 { self.lastShown = t; self.state.mosaic = grid }
            }
        }
    }
}
}
