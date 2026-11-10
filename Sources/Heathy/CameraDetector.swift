import AVFoundation
import CoreMedia
import HeathyCore
import Vision

enum CameraStatus: Equatable {
    case off, requesting, starting, running, stopping, denied
    case unavailable(String)
}

struct CameraChoice: Identifiable {
    let id: String
    let name: String
}

/// Only video is captured. Frames are analyzed in memory and never persisted.
final class CameraDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onStatus: ((CameraStatus) -> Void)?
    var onSession: ((AVCaptureSession?) -> Void)?
    var onSample: ((FrameFeatures, String, String, String?) -> Void)?
    var onStarted: ((TimeInterval) -> Void)?
    var onWindowEnded: (() -> Void)?
    private let queue = DispatchQueue(label: "local.qingxing.camera", qos: .utility)
    private let analysisQueue = DispatchQueue(label: "local.qingxing.analysis", qos: .utility)
    private let lock = NSLock()
    private var generation = 0
    private var session: AVCaptureSession?
    private var observers: [NSObjectProtocol] = []
    private struct CaptureIdentity {
        let token: Int
        let deviceID: String
        let output: ObjectIdentifier
        let window: CaptureWindow
        let includeBodyPose: Bool
    }
    private var activeCapture: CaptureIdentity?
    private var analysisGeneration = -1
    private var lastAnalysis = -Double.infinity
    private let shoulderDetector = PoseNetShoulderDetector()

    static func availableCameras() -> [CameraChoice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices.map { CameraChoice(id: $0.uniqueID, name: $0.localizedName) }
    }

    private func nextGeneration() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        return generation
    }

    private func isCurrent(_ token: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return token == generation
    }

    private func completeGeneration(_ token: Int) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard generation == token else { return nil }
        generation += 1
        return generation
    }

    private func publish(_ status: CameraStatus, token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.onStatus?(status)
        }
    }

    func start(cameraID: String, includeBodyPose: Bool = false) {
        let token = nextGeneration()
        onStatus?(.starting)
        queue.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.releaseSession()
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                self.publish(.denied, token: token)
                return
            }
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                mediaType: .video, position: .unspecified
            )
            guard let device = discovery.devices.first(where: { $0.uniqueID == cameraID }) else {
                self.publish(.unavailable("未找到所选摄像头，请重新选择。"), token: token)
                return
            }
            do {
                // Load the bundled model before opening the camera, outside its five-second window.
                if includeBodyPose { try? self.shoulderDetector.prepare() }
                guard self.isCurrent(token) else { return }
                let capture = AVCaptureSession()
                capture.beginConfiguration()
                if capture.canSetSessionPreset(.vga640x480) { capture.sessionPreset = .vga640x480 }
                let input = try AVCaptureDeviceInput(device: device)
                guard capture.canAddInput(input) else { throw CameraFailure.configuration }
                capture.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                guard capture.canAddOutput(output) else { throw CameraFailure.configuration }
                capture.addOutput(output)
                output.setSampleBufferDelegate(self, queue: self.analysisQueue)
                if let range = device.activeFormat.videoSupportedFrameRateRanges.min(by: { $0.minFrameRate < $1.minFrameRate }) {
                    try device.lockForConfiguration()
                    let fps = min(range.maxFrameRate, max(range.minFrameRate, 5))
                    let duration = CMTime(seconds: 1 / fps, preferredTimescale: 600)
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                    device.unlockForConfiguration()
                }
                capture.commitConfiguration()
                guard self.isCurrent(token) else { return }
                self.session = capture
                for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
                    let observer = NotificationCenter.default.addObserver(forName: name, object: capture, queue: nil) { [weak self] _ in
                        self?.queue.async { [weak self] in
                            self?.failWindow(token: token, message: "摄像头采集中断，请检查设备或权限后重试。")
                        }
                    }
                    self.observers.append(observer)
                }
                let window = CaptureWindow(startedAt: ProcessInfo.processInfo.systemUptime)
                self.lock.lock()
                self.activeCapture = CaptureIdentity(token: token, deviceID: device.uniqueID, output: ObjectIdentifier(output), window: window, includeBodyPose: includeBodyPose)
                self.lock.unlock()
                // Session control has its own queue: a slow Vision request cannot
                // hold the camera open past the scheduled stop.
                self.queue.asyncAfter(deadline: .now() + CaptureWindow.duration) { [weak self] in self?.finishWindow(token: token) }
                capture.startRunning()
                guard self.isCurrent(token) else { self.releaseSession(); return }
                guard !window.hasExpired(at: ProcessInfo.processInfo.systemUptime) else { self.finishWindow(token: token); return }
                guard capture.isRunning else {
                    self.failWindow(token: token, message: "摄像头未能启动，可以先使用休息计时。")
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(token) else { return }
                    self.onSession?(capture)
                    self.onStarted?(window.startedAt)
                    self.onStatus?(.running)
                }
            } catch {
                self.failWindow(token: token, message: "摄像头暂不可用，可以先使用休息计时。")
            }
        }
    }

    func stop() {
        let token = nextGeneration()
        onStatus?(.stopping)
        onSession?(nil)
        queue.async { [weak self] in
            guard let self else { return }
            self.releaseSession()
            self.publish(.off, token: token)
        }
    }

    func stopSynchronously() {
        _ = nextGeneration()
        queue.sync { releaseSession() }
    }

    private func finishWindow(token: Int) {
        guard let completed = completeGeneration(token) else { return }
        publish(.stopping, token: completed)
        releaseSession()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(completed) else { return }
            self.onSession?(nil)
            self.onStatus?(.off)
            self.onWindowEnded?()
        }
    }

    private func failWindow(token: Int, message: String) {
        guard let failed = completeGeneration(token) else { return }
        releaseSession()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(failed) else { return }
            self.onSession?(nil)
            self.onStatus?(.unavailable(message))
        }
    }

    private func releaseSession() {
        lock.lock()
        activeCapture = nil
        lock.unlock()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        guard let session else { return }
        if session.isRunning { session.stopRunning() }
        for output in session.outputs {
            (output as? AVCaptureVideoDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
        }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
        self.session = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        let identity = activeCapture
        lock.unlock()
        guard let identity, identity.output == ObjectIdentifier(output), isCurrent(identity.token) else { return }
        let token = identity.token
        let now = ProcessInfo.processInfo.systemUptime
        guard !identity.window.hasExpired(at: now) else { return }
        if analysisGeneration != token { analysisGeneration = token; lastAnalysis = -.infinity }
        guard now - lastAnalysis >= 0.5 else { return }
        lastAnalysis = now
        autoreleasepool {
            guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
            let signature = "\(identity.deviceID):\(CVPixelBufferGetWidth(pixels))x\(CVPixelBufferGetHeight(pixels))"
            let faces = VNDetectFaceRectanglesRequest()
            faces.revision = VNDetectFaceRectanglesRequestRevision3
            var features = FrameFeatures.unavailable
            var reason = "未检测到人脸，请让脸部完整进入所选摄像头。"
            var postureReason: String? = identity.includeBodyPose ? "未看清双肩，请让脸部与双肩完整入镜。" : nil
            var diagnosticConfidence: String?
            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
                try handler.perform([faces])
                if CommandLine.arguments.contains("--diagnose-distance") {
                    print("FACE_DIAGNOSTIC count=\(faces.results?.count ?? 0)")
                    for face in faces.results ?? [] {
                        print("FACE_DIAGNOSTIC confidence=\(face.confidence) width=\(face.boundingBox.width) yaw=\(face.yaw?.doubleValue.description ?? "missing")")
                    }
                }
                if CommandLine.arguments.contains("--diagnose-shoulders") { print("DIAGNOSTIC FACE COUNT: \(faces.results?.count ?? 0)") }
                if let results = faces.results, results.count == 1, let face = results.first {
                    if FaceDetectionQuality.accepts(confidence: Double(face.confidence)) {
                        var headPose: HeadPoseFeatures?
                        if identity.includeBodyPose, let pitch = face.pitch?.doubleValue {
                            let angles = HeadPoseFeatures(pitch: pitch, roll: face.roll?.doubleValue)
                            if angles.isValid { headPose = angles }
                        }
                        var posture: PostureFeatures?
                        // Missing shoulders must not discard a usable distance observation.
                        if identity.includeBodyPose {
                            do {
                                let points = try shoulderDetector.points(using: handler,
                                    imageWidth: CVPixelBufferGetWidth(pixels), imageHeight: CVPixelBufferGetHeight(pixels))
                                let left = points.left
                                let right = points.right
                                if CommandLine.arguments.contains("--diagnose-shoulders") {
                                    print("DIAGNOSTIC POSENET CONFIDENCE: left=\(left.confidence), right=\(right.confidence), nose=\(points.nose?.confidence ?? 0)")
                                    diagnosticConfidence = "left=\(left.confidence), right=\(right.confidence)"
                                }
                                if left.confidence < 0.5 || right.confidence < 0.5 {
                                    postureReason = "肩部关键点不够清晰，本轮暂不判断头肩。"
                                } else if let nose = points.nose, nose.confidence >= 0.5,
                                          !face.boundingBox.insetBy(dx: -0.02, dy: -0.02).contains(CGPoint(x: nose.x, y: nose.y)) {
                                    postureReason = "未能确认双肩与当前人脸对应，本轮暂不判断。"
                                } else {
                                    posture = PostureFeatures.measureFromFace(
                                        faceCenter: PosturePoint(x: face.boundingBox.midX, y: face.boundingBox.midY, confidence: Double(face.confidence)),
                                        faceWidth: face.boundingBox.width,
                                        aspectRatio: Double(CVPixelBufferGetWidth(pixels)) / Double(CVPixelBufferGetHeight(pixels)),
                                        left: left, right: right, pitch: face.pitch?.doubleValue,
                                        shoulderModel: PoseNetDecoder.modelID)
                                    postureReason = posture == nil ? "已定位双肩，但头肩几何信息不可用，请让肩部远离画面边缘。" : nil
                                }
                            } catch {
                                postureReason = (error as? PoseNetShoulderDetector.Failure)?.localizedDescription ?? "肩部识别未完成，请再检测一次（错误码 \((error as NSError).code)）。"
                            }
                        }
                        features = FrameFeatures(faceWidth: face.boundingBox.width, yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue, posture: posture, headPose: headPose)
                        reason = features.isValid ? "" : "无法确认正面人脸，请面向所选摄像头。"
                    } else { reason = "人脸识别置信度不足，请改善照明并保持脸部完整入镜。" }
                } else if (faces.results?.count ?? 0) > 1 { reason = "画面中有多人，暂时无法判断" }
            } catch { reason = "人脸识别未完成，请再检测 5 秒（错误码 \((error as NSError).code)）。" }
            guard isCurrent(token) else { return }
            let reportedPostureReason = diagnosticConfidence.map { (postureReason ?? "usable shoulders") + " [" + $0 + "]" } ?? postureReason
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent(token) else { return }
                self.onSample?(features, signature, reason, reportedPostureReason)
            }
        }
    }

    private enum CameraFailure: Error { case configuration }
}
