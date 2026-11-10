public enum FaceDetectionQuality {
    public static func accepts(confidence: Double) -> Bool {
        // Five-second face-only diagnosis found stable frontal detections at
        // 0.767–0.790 during normal forward/backward movement. Geometry and
        // single-person checks remain independent requirements in the caller.
        confidence.isFinite && confidence >= 0.75 && confidence <= 1
    }
}
