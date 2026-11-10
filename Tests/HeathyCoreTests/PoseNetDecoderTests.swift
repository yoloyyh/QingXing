import Foundation
import HeathyCore

struct PoseNetDecoderTests {
    func testHeatmapPeakOffsetsMapBackToFullImage() {
        let point = PoseNetDecoder.point(joint: 5, inputSize: 513, width: 33, height: 33,
            heatmap: { joint, y, x in joint == 5 && y == 19 && x == 10 ? 0.91 : 0.1 },
            offsets: { channel, _, _ in channel == 5 ? -2.25 : 1.5 })
        expect(point != nil)
        if let point {
            expect(abs(point.x - 161.5 / 513) < 0.000001)
            expect(abs(point.y - (1 - 301.75 / 513)) < 0.000001)
            expect(point.confidence == 0.91)
        }
        let defaultSize = PoseNetDecoder.point(joint: 6, inputSize: 353, width: 23, height: 23,
            heatmap: { _, y, x in y == 12 && x == 8 ? 0.9 : 0.1 }, offsets: { _, _, _ in 0 })
        expect(abs((defaultSize?.x ?? 0) - 128.0 / 353) < 0.000001)
        expect(abs((defaultSize?.y ?? 0) - (1 - 192.0 / 353)) < 0.000001)
        let empty = PoseNetDecoder.point(joint: 6, inputSize: 513, width: 0, height: 33,
            heatmap: { _, _, _ in 0.9 }, offsets: { _, _, _ in 0 })
        expect(empty == nil)
    }

    func testInvalidAndUncertainModelPointsCannotBecomeShoulders() {
        expect(PoseNetDecoder.point(joint: 5, inputSize: 513, width: 33, height: 33,
            heatmap: { _, _, _ in .nan }, offsets: { _, _, _ in 0 }) == nil)
        expect(PoseNetDecoder.point(joint: 5, inputSize: 513, width: 33, height: 33,
            heatmap: { _, _, _ in 0.9 }, offsets: { _, _, _ in .infinity }) == nil)
        let uncertain = PoseNetDecoder.point(joint: 5, inputSize: 513, width: 33, height: 33,
            heatmap: { _, y, x in y == 19 && x == 10 ? 0.2 : 0.1 }, offsets: { _, _, _ in 0 })
        expect(uncertain?.confidence == 0.2)
        if let uncertain {
            expect(PostureFeatures.measureFromFace(faceCenter: .init(x: 0.5, y: 0.8), faceWidth: 0.2,
                aspectRatio: 4.0 / 3, left: uncertain, right: .init(x: 0.8, y: 0.4), pitch: nil) == nil)
        }
    }

    func testLetterboxCoordinatesReturnToWideAndPortraitImages() {
        let wide = PoseNetDecoder.imagePoint(.init(x: 0.3, y: 0.44375, confidence: 0.8), width: 640, height: 360)
        expect(abs((wide?.x ?? 0) - 0.3) < 0.000001)
        expect(abs((wide?.y ?? 0) - 0.4) < 0.000001)
        expect(wide?.confidence == 0.8)
        let portrait = PoseNetDecoder.imagePoint(.init(x: 0.44375, y: 0.6), width: 360, height: 640)
        expect(abs((portrait?.x ?? 0) - 0.4) < 0.000001)
        expect(abs((portrait?.y ?? 0) - 0.6) < 0.000001)
        let square = PoseNetDecoder.imagePoint(.init(x: 0.3, y: 0.4), width: 512, height: 512)
        expect(square?.x == 0.3 && square?.y == 0.4)
    }

    func testLetterboxPaddingCannotBecomeAnInFrameShoulder() {
        let padding = PoseNetDecoder.imagePoint(.init(x: 0.3, y: 0.1), width: 640, height: 360)
        expect(padding != nil && padding!.y < 0)
        if let padding {
            expect(PostureFeatures.measureFromFace(faceCenter: .init(x: 0.5, y: 0.75), faceWidth: 0.2,
                aspectRatio: 16.0 / 9, left: padding, right: .init(x: 0.8, y: 0.4), pitch: nil) == nil)
        }
        expect(PoseNetDecoder.imagePoint(.init(x: 0.5, y: 0.5), width: 0, height: 360) == nil)
    }

    func testShoulderModelsCannotShareOrRecoverAgainstOneReference() {
        let old = PostureFeatures(faceShoulderRatio: 0.4, headOffset: 0, headHeight: 0.5,
            shoulderTilt: 0, usesFaceCenter: true)
        let current = PostureFeatures(faceShoulderRatio: 0.4, headOffset: 0, headHeight: 0.5,
            shoulderTilt: 0, usesFaceCenter: true, shoulderModel: PoseNetDecoder.modelID)
        let sample = FrameFeatures(faceWidth: 0.2, posture: current)
        let baseline = Calibration(faceWidth: 0.2, faceShoulderRatio: old.faceShoulderRatio, cameraID: "test", postureReference: old)
        expect(PostureAssessment.evaluate(sample, reference: baseline) == .needsCalibration)
        expect(!PostureAssessment.isRecovered(sample, reference: baseline))
        expect(!old.isCurrentShoulderReference && current.isCurrentShoulderReference)
        let stretched = PostureFeatures(faceShoulderRatio: 0.4, headOffset: 0, headHeight: 0.5,
            shoulderTilt: 0, usesFaceCenter: true, shoulderModel: "posenet075-s16-v1")
        expect(!stretched.isCurrentShoulderReference)
        let stretchedBaseline = Calibration(faceWidth: 0.2, faceShoulderRatio: 0.4, cameraID: "test", postureReference: stretched)
        expect(PostureAssessment.evaluate(sample, reference: stretchedBaseline) == .needsCalibration)
        expect(!PostureAssessment.isRecovered(sample, reference: stretchedBaseline))
    }

    func testCalibrationPersistsTheModelAndRestartsOnModelChange() {
        let start = Date(timeIntervalSince1970: 1_000)
        let old = PostureFeatures(faceShoulderRatio: 0.4, headOffset: 0, headHeight: 0.5,
            shoulderTilt: 0, usesFaceCenter: true)
        let current = PostureFeatures(faceShoulderRatio: 0.4, headOffset: 0, headHeight: 0.5,
            shoulderTilt: 0, usesFaceCenter: true, shoulderModel: PoseNetDecoder.modelID)
        let session = CalibrationSession()
        for index in 0...2 {
            session.add(.init(faceWidth: 0.2, posture: old), at: start.addingTimeInterval(Double(index) / 2))
        }
        session.add(.init(faceWidth: 0.2, posture: current), at: start.addingTimeInterval(1.5))
        expect(session.postureReference == nil)
        for index in 4...6 {
            session.add(.init(faceWidth: 0.2, posture: current), at: start.addingTimeInterval(Double(index) / 2))
        }
        expect(session.postureReference?.shoulderModel == PoseNetDecoder.modelID)
        if let reference = session.reference(cameraID: "test"), let data = try? JSONEncoder().encode(reference),
           let decoded = try? JSONDecoder().decode(Calibration.self, from: data) {
            expect(decoded.postureReference?.isCurrentShoulderReference == true)
        } else { expect(false) }
    }
}
