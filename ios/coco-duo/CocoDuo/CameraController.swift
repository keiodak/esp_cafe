import AVFoundation
import CoreVideo

/// フロントカメラの映像から「明るさ(輝度平均)」と「距離(顔の大きさから推定)」を
/// リアルタイムで取得し、クロージャで通知するコントローラー。
/// カメラ1フレームから取り出した値をひとまとめにしたもの。
/// 値ごとに個別のコールバックを呼ぶと、受け手側で1フレームにつき何度も
/// メインキューへディスパッチすることになり、SwiftUIの再描画が無駄に増える。
/// 1フレーム=1回にまとめるための入れ物。
struct CameraFrame {
    var brightness: Double
    var contrast: Double
    /// 前フレームがまだ無いときはnil。
    var motion: Double?
    /// 色差プレーンが取れなかったときはnil。
    var colorR: Double?
    var colorG: Double?
    var colorB: Double?
    /// モザイクが不要(太陽モードOFF)のときはnil。
    var mosaicBrightness: [[Double]]?
    var mosaicMotion: [[Double]]?
}

final class CameraController: NSObject {
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "cocoduo.camera.session")
    /// 現在セッションに繋がっている入力(前後切り替え時に外すため保持する)。
    private var currentInput: AVCaptureDeviceInput?
    /// 使いたいカメラの位置。setPosition()で変更する(既定は背面)。
    private var desiredPosition: AVCaptureDevice.Position = .back
    /// 使いたいフレームレート。setFrameRate()で変更する(既定は30fps)。
    private var desiredFPS: Int = 30
    private let outputQueue = DispatchQueue(label: "cocoduo.camera.output")
    private var isConfigured = false

    /// 1フレーム分の結果をまとめて1回だけ通知する。フレームごとに呼ばれる。
    var onFrameUpdate: ((CameraFrame) -> Void)?

    /// モザイク(太陽モード)が必要かどうか。falseのあいだは128マスの計算を丸ごと省く。
    /// メインスレッドから書かれ、カメラの出力キューから読まれるのでロックで保護する。
    private let flagLock = NSLock()
    private var _mosaicEnabled = false
    var mosaicEnabled: Bool {
        get { flagLock.lock(); defer { flagLock.unlock() }; return _mosaicEnabled }
        set { flagLock.lock(); _mosaicEnabled = newValue; flagLock.unlock() }
    }

    /// 動き量計算のための前フレームのサンプル値(輝度計算と同じ間引きグリッド)。
    private var previousLumaSamples: [UInt8]?
    /// 動き量計算のための前フレームのモザイク明るさ(4x8)。
    private var previousMosaicBrightness: [[Double]]?
    /// 動き量の時間方向スムージング(ノイズによるチラつきを均す)。立ち上がりは速く、
    /// 減衰はゆっくりにして「動きがあった直後だけ反応する」感触にする。
    private var smoothedMosaicMotion: [[Double]]?


    func start() {
        // 許可を明示的に取りに行く。これを呼ばなくてもセッション開始時にOSが聞いてくるが、
        // 一度拒否されていると黙って何も起きないままになる。ここで状態を握っておく。
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            beginSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.beginSession()
                } else {
                    print("CameraController: camera access was not granted")
                }
            }
        case .denied, .restricted:
            print("CameraController: camera access denied - allow it in Settings")
        @unknown default:
            beginSession()
        }
    }

    /// 起動画面のあいだに、セッションだけ先に組んでおく(開始はしない)。
    ///
    /// 初回の configureSession は端末の探索と入力の生成で数十msかかり、
    /// それがオーディオと同じ優先度で走るとプツッと鳴る。中央の月を押した
    /// その瞬間に払うのではなく、まだ音が気にならない起動直後に済ませておく。
    /// 許可がまだなら何もしない(ここで許可ダイアログを出したくない)。
    func warmSession() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }
            self.configureSession()
        }
    }

    private func beginSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            guard self.isConfigured else {
                print("CameraController: could not configure the session")
                return
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    /// 前面/背面カメラを切り替える。セッションが未構成ならconfigureSession時に反映され、
    /// 稼働中なら入力を差し替える(セッションは止めない)。
    func setPosition(_ position: AVCaptureDevice.Position) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.desiredPosition != position else { return }
            self.desiredPosition = position
            guard self.isConfigured else { return }

            self.session.beginConfiguration()
            if let old = self.currentInput {
                self.session.removeInput(old)
                self.currentInput = nil
            }
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.currentInput = input
                    }
                } catch {
                    print("CameraController: failed to switch camera — \(error)")
                }
            }
            self.applyConnectionSettings()
            self.applyFrameRate()
            self.session.commitConfiguration()
        }
    }

    /// フレームレートを変更する。低いほどキャプチャの消費電力が下がるが、
    /// カメラ由来の反応(色・モザイク吸い寄せ)がそのぶん粗くなる。
    func setFrameRate(_ fps: Int) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let clamped = max(1, min(fps, 60))
            // スライダーのドラッグ中は同じ値が連続で届くことがあるため、
            // 変化がなければデバイス設定(lockForConfiguration)を触らない。
            guard clamped != self.desiredFPS else { return }
            self.desiredFPS = clamped
            guard self.isConfigured else { return }
            self.applyFrameRate()
        }
    }

    /// 現在の入力デバイスへdesiredFPSを適用する。入力の差し替え後にも呼ぶこと
    /// (フレームレート設定はデバイスごとに持たれ、差し替えでリセットされるため)。
    private func applyFrameRate() {
        guard let device = currentInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let duration = CMTime(value: 1, timescale: CMTimeScale(desiredFPS))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            print("CameraController: failed to set frame rate — \(error)")
        }
    }

    /// 回転とミラーリングを現在のカメラ位置に合わせて設定する。
    /// 前面カメラは鏡像にする(左に動かすと画面上も左に反応する「鏡」の感覚に合わせる。
    /// モザイクの吸い寄せの左右も直感と一致する)。
    private func applyConnectionSettings() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        let portraitAngle: CGFloat = 90
        if connection.isVideoRotationAngleSupported(portraitAngle) {
            connection.videoRotationAngle = portraitAngle
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = (desiredPosition == .front)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configureSession() {
        // これを切らないと、キャプチャを開始した瞬間に AVCaptureSession が
        // アプリの AVAudioSession を自分で組み直す。カテゴリとバッファが
        // 作り直されるぶん出力が一瞬途切れて、プツッとノイズが乗る。
        // 映像しか撮らないので、音のセッションには一切触らせない。
        session.automaticallyConfiguresApplicationAudioSession = false
        session.beginConfiguration()
        // モザイクにしか使わないので、いちばん軽い枠で足りる。
        // 解像度を上げてもマス目の平均が滑らかになるだけで、起動が重くなる。
        session.sessionPreset = .low

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: desiredPosition) else {
            print("CameraController: no camera available for position \(desiredPosition.rawValue)")
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            }
        } catch {
            print("CameraController: failed to create device input — \(error)")
            session.commitConfiguration()
            return
        }

        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        applyConnectionSettings()
        applyFrameRate()

        session.commitConfiguration()
        isConfigured = (currentInput != nil)
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        processLuma(pixelBuffer: pixelBuffer)
    }

    // MARK: - 明るさ(輝度)・動き量(フレーム間差分)

    private func processLuma(pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let basePtr = yBase.assumingMemoryBound(to: UInt8.self)

        let strideStep = 8
        var samples: [UInt8] = []
        samples.reserveCapacity((width / strideStep + 1) * (height / strideStep + 1))
        var total = 0

        var row = 0
        while row < height {
            let rowPtr = basePtr + row * bytesPerRow
            var col = 0
            while col < width {
                let v = rowPtr[col]
                samples.append(v)
                total += Int(v)
                col += strideStep
            }
            row += strideStep
        }
        guard !samples.isEmpty else { return }

        // 明るさ: 今フレームの平均輝度。
        let average = Double(total) / Double(samples.count) / 255.0

        // コントラスト: 輝度サンプルのバラツキ(標準偏差)。平坦な景色ほど0に近く、
        // ゴチャゴチャした景色ほど1に近づく。
        let meanY = Double(total) / Double(samples.count)
        var varianceSum = 0.0
        for v in samples {
            let d = Double(v) - meanY
            varianceSum += d * d
        }
        let stddev = sqrt(varianceSum / Double(samples.count))
        let contrast = min(max(stddev / 80.0, 0.0), 1.0) // 80は目安のスケーリング係数

        // ここから先で得た値は、最後に CameraFrame としてまとめて1回だけ通知する。
        var frame = CameraFrame(brightness: average, contrast: contrast)

        // RGB: 色差(Cb/Cr)プレーンの平均から、輝度と合わせてYCbCr→RGB変換(BT.601, フルレンジ)。
        if let cbCrBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
            let cbCrWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
            let cbCrHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
            let cbCrBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let cbCrPtr = cbCrBase.assumingMemoryBound(to: UInt8.self)

            let chromaStride = 4
            var cbTotal = 0
            var crTotal = 0
            var chromaCount = 0
            var crow = 0
            while crow < cbCrHeight {
                let rowPtr = cbCrPtr + crow * cbCrBytesPerRow
                var ccol = 0
                while ccol < cbCrWidth {
                    let idx = ccol * 2 // Cb, Crが交互に並ぶインターリーブ形式
                    cbTotal += Int(rowPtr[idx])
                    crTotal += Int(rowPtr[idx + 1])
                    chromaCount += 1
                    ccol += chromaStride
                }
                crow += chromaStride
            }

            if chromaCount > 0 {
                let avgCb = Double(cbTotal) / Double(chromaCount)
                let avgCr = Double(crTotal) / Double(chromaCount)

                let r = meanY + 1.402 * (avgCr - 128.0)
                let g = meanY - 0.344136 * (avgCb - 128.0) - 0.714136 * (avgCr - 128.0)
                let b = meanY + 1.772 * (avgCb - 128.0)

                frame.colorR = min(max(r / 255.0, 0.0), 1.0)
                frame.colorG = min(max(g / 255.0, 0.0), 1.0)
                frame.colorB = min(max(b / 255.0, 0.0), 1.0)
            }
        }

        // 動き量: 前フレームの同じ間引きグリッドとの平均絶対差分。
        if let prev = previousLumaSamples, prev.count == samples.count {
            var diffTotal = 0
            for i in 0..<samples.count {
                diffTotal += abs(Int(samples[i]) - Int(prev[i]))
            }
            let diffAverage = Double(diffTotal) / Double(samples.count) / 255.0
            // 生の差分は小さい値になりがちなので、感度を上げてから0...1にクランプする。
            frame.motion = min(max(diffAverage * 6.0, 0.0), 1.0)
        }

        previousLumaSamples = samples

        // --- 超低解像度モザイク: 全体を縦4×横8(=1パッドあたり縦2×横2=4マス)に分割し、
        //     各マスの平均輝度と、前フレームとの差分(動き量)を計算する。
        //     太陽モードがOFFのあいだは誰も見ないので、丸ごと省いて通知だけ返す。
        guard mosaicEnabled else {
            previousMosaicBrightness = nil
            smoothedMosaicMotion = nil
            onFrameUpdate?(frame)
            return
        }

        let gridRows = 8
        let gridCols = 16
        var mosaicBrightness = Array(repeating: Array(repeating: 0.0, count: gridCols), count: gridRows)
        var cellSums = Array(repeating: Array(repeating: 0, count: gridCols), count: gridRows)
        var cellCounts = Array(repeating: Array(repeating: 0, count: gridCols), count: gridRows)

        // マス数が増えた分、サンプリング間隔を細かくして解像度を確保する。
        let mosaicStride = 6
        var mrow = 0
        while mrow < height {
            let rowPtr = basePtr + mrow * bytesPerRow
            let gridRow = min(gridRows - 1, mrow * gridRows / height)
            var mcol = 0
            while mcol < width {
                let gridCol = min(gridCols - 1, mcol * gridCols / width)
                cellSums[gridRow][gridCol] += Int(rowPtr[mcol])
                cellCounts[gridRow][gridCol] += 1
                mcol += mosaicStride
            }
            mrow += mosaicStride
        }

        for r in 0..<gridRows {
            for c in 0..<gridCols {
                guard cellCounts[r][c] > 0 else { continue }
                mosaicBrightness[r][c] = Double(cellSums[r][c]) / Double(cellCounts[r][c]) / 255.0
            }
        }

        var mosaicMotion = Array(repeating: Array(repeating: 0.0, count: gridCols), count: gridRows)
        if let prevMosaic = previousMosaicBrightness, prevMosaic.count == gridRows, prevMosaic.first?.count == gridCols {
            for r in 0..<gridRows {
                for c in 0..<gridCols {
                    let diff = abs(mosaicBrightness[r][c] - prevMosaic[r][c])
                    // ごく小さな差分(センサーノイズ相当)は切り捨ててから感度を掛ける。
                    let denoised = max(0.0, diff - 0.008)
                    mosaicMotion[r][c] = min(denoised * 10.0, 1.0)
                }
            }
        }
        previousMosaicBrightness = mosaicBrightness

        // 時間方向のスムージング: 立ち上がりは速く(動きに素早く反応)、
        // 減衰はゆっくり(ノイズでピクピク戻らず、動きがあった余韻が残る)。
        if smoothedMosaicMotion == nil {
            smoothedMosaicMotion = mosaicMotion
        } else {
            for r in 0..<gridRows {
                for c in 0..<gridCols {
                    let target = mosaicMotion[r][c]
                    let current = smoothedMosaicMotion![r][c]
                    let coeff = target > current ? 0.6 : 0.15
                    smoothedMosaicMotion![r][c] = current + (target - current) * coeff
                }
            }
        }
        frame.mosaicBrightness = mosaicBrightness
        frame.mosaicMotion = smoothedMosaicMotion
        onFrameUpdate?(frame)
    }

}
