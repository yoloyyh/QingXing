import HeathyCore

struct FaceDetectionQualityTests {
    func testObservedForwardBackwardMovementKeepsUsableFaces() {
        let confidences = [0.78405744, 0.779999, 0.8238391, 0.84894234,
                           0.8443285, 0.76737684, 0.79026055, 0.8016097, 0.8106951]
        expect(confidences.allSatisfy { FaceDetectionQuality.accepts(confidence: $0) })
    }

    func testWeakConfidenceAndInvalidGeometryRemainRejected() {
        expect(!FaceDetectionQuality.accepts(confidence: 0.7043392))
        expect(!FaceDetectionQuality.accepts(confidence: .nan))
        expect(!FrameFeatures(faceWidth: 0.03, yaw: 0).isValid)
        expect(!FrameFeatures(faceWidth: 0.3, yaw: 0.8).isValid)
        expect(!FrameFeatures(faceWidth: 0.3, yaw: nil).isValid)
    }
}
