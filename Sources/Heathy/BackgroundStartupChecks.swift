import AppKit
import CoreServices
import Foundation
import HeathyCore

@MainActor
enum BackgroundStartupChecks {
    static func run() throws {
        let suite = "local.qingxing.background-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let reference = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "offline:640x480", referenceDistanceCM: 60)
        defaults.set(try JSONEncoder().encode(reference), forKey: "qx.calibration")
        defaults.set("offline", forKey: "qx.camera")
        let now = Date()
        let first = AppState(defaults: defaults)
        first.restoreAutomaticChecks(at: now, cameraAuthorized: true)
        precondition(!first.checksEnabled && first.nextCheckAt == nil)
        first.shutdown()
        defaults.set(true, forKey: "qx.checksStarted")
        let restored = AppState(defaults: defaults)
        restored.restoreAutomaticChecks(at: now, cameraAuthorized: false)
        precondition(!restored.checksEnabled && restored.nextCheckAt == nil)
        precondition(!defaults.bool(forKey: "qx.checksStarted"))
        restored.restoreAutomaticChecks(at: now, cameraAuthorized: true)
        precondition(!restored.checksEnabled && restored.nextCheckAt == nil)
        // A new explicit choice is required after authorization was revoked.
        defaults.set(true, forKey: "qx.checksStarted")
        restored.restoreAutomaticChecks(at: now, cameraAuthorized: true)
        precondition(restored.checksEnabled && restored.manualTimerRunning && restored.nextCheckAt == now.addingTimeInterval(1_800))
        precondition(!restored.cameraActive && restored.cameraSession == nil)
        restored.shutdown()
        precondition(defaults.bool(forKey: "qx.checksStarted"))
        let restarted = AppState(defaults: defaults)
        restarted.restoreAutomaticChecks(at: now.addingTimeInterval(86_400), cameraAuthorized: true)
        precondition(restarted.nextCheckAt == now.addingTimeInterval(88_200))
        restarted.automaticChecks = false
        precondition(restarted.nextCheckAt == nil && !defaults.bool(forKey: "qx.checksStarted"))
        restarted.automaticChecks = true
        precondition(defaults.bool(forKey: "qx.checksStarted"))
        restarted.disableCamera()
        restarted.shutdown()
        defaults.set(true, forKey: "qx.checksStarted")
        defaults.set(true, forKey: "qx.automaticChecks")
        defaults.set("another-camera", forKey: "qx.camera")
        let mismatch = AppState(defaults: defaults)
        mismatch.restoreAutomaticChecks(at: now, cameraAuthorized: true)
        precondition(!mismatch.checksEnabled && mismatch.nextCheckAt == nil && !mismatch.cameraActive)
        precondition(!defaults.bool(forKey: "qx.checksStarted"))
        mismatch.disableCamera()
        precondition(!defaults.bool(forKey: "qx.checksStarted"))
        mismatch.shutdown()
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        precondition(!LoginLaunchController.isLoginLaunch(nil) && !LoginLaunchController.isLoginLaunch(event))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        precondition(LoginLaunchController.isLoginLaunch(event))
        print("PASS: explicit saved choice restores a 30-minute countdown across restart; permission or reference mismatch blocks it; stopping clears choice; no camera started")
        print("PASS: own login-launch event is distinguished from normal launch; no login item registration or visible windows in this check")
    }
}
