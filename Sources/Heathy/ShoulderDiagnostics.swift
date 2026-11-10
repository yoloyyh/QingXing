import AppKit
import AVFoundation
import Darwin

/// Explicit CLI diagnostic: one existing five-second capture, numeric status only.
@MainActor
final class ShoulderDiagnostics {
    private let state: AppState
    private var frames = 0
    private var faces = 0
    private var shoulders = 0
    private var headFrames = 0
    private var reasons: [String: Int] = [:]
    private var finished = false
    private let originalReference: Data?

    init(state: AppState) {
        self.state = state
        originalReference = UserDefaults.standard.data(forKey: "qx.calibration")
    }

    func start() {
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        guard authorization == .authorized else {
            finish(error: "Camera is not already authorized (status \(authorization.rawValue)); no access requested")
            return
        }
        let choices = CameraDetector.availableCameras()
        let selected = choices.first { $0.id == state.selectedCameraID }
        guard let camera = selected ?? (state.selectedCameraID.isEmpty && choices.count == 1 ? choices.first : nil) else {
            finish(error: "The saved camera is unavailable or ambiguous; no camera opened")
            return
        }
        let previousSample = state.detector.onSample
        state.detector.onSample = { [self] sample, signature, message, postureMessage in
            previousSample?(sample, signature, message, postureMessage)
            frames += 1
            if sample.isValid { faces += 1 }
            if sample.supportsPosture { shoulders += 1 }
            if sample.supportsHeadPose { headFrames += 1 }
            if let reason = postureMessage, !reason.isEmpty { reasons[reason, default: 0] += 1 }
            if !message.isEmpty { reasons[message, default: 0] += 1 }
        }
        let previousEnd = state.detector.onWindowEnded
        state.detector.onWindowEnded = { [self] in
            previousEnd?()
            finish(error: nil)
        }
        let previousStatus = state.detector.onStatus
        state.detector.onStatus = { [self] status in
            previousStatus?(status)
            if case .unavailable(let message) = status { finish(error: message) }
            if case .denied = status { finish(error: "Camera permission unavailable") }
        }
        print("DIAGNOSTIC: opening only the saved camera for at most five seconds; no images saved or displayed in this report")
        fflush(stdout)
        // Do not call enableCamera/startCalibrationCapture: the reference stays untouched.
        state.detector.start(cameraID: camera.id, includeBodyPose: !CommandLine.arguments.contains("--diagnose-distance"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [self] in
            if !finished { state.detector.stop(); finish(error: "No completed capture callback") }
        }
    }

    private func finish(error: String?) {
        guard !finished else { return }
        finished = true
        let report: [String: Any] = [
            "analyzedFrames": frames, "validFaceFrames": faces, "usableShoulderFrames": shoulders,
            "usableHeadFrames": headFrames,
            "reasons": reasons, "error": error ?? "",
            "referenceUnchanged": originalReference == UserDefaults.standard.data(forKey: "qx.calibration"),
            "cameraRunning": state.cameraActive
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print("DIAGNOSTIC RESULT: " + text) }
        fflush(stdout)
        DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
    }
}
