import HeathyCore

struct ScanObservationTests {
    func testWaitingForFirstScanIsNotAnAssessmentFailure() {
        expect(DistanceReading.label(sample: nil, reference: nil, isLive: false) == "等待检测")
        expect(DistanceReading.label(sample: nil, reference: nil, isLive: true) == "正在识别人脸")
    }

    func testCompletedMeasurementIsClearlyMarkedAsPrevious() {
        let reference = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "camera")
        expect(DistanceReading.label(sample: .valid(faceWidth: 0.2), reference: reference, isLive: false) == "最近检测：与参考距离接近")
        expect(DistanceReading.label(sample: .valid(faceWidth: 0.27), reference: reference, isLive: false) == "最近检测：比参考位置更靠近")
        expect(DistanceReading.label(sample: .unavailable, reference: reference, isLive: false) == "最近检测：未获取有效人脸")
        expect(DistanceReading.label(sample: .valid(faceWidth: 0.2), reference: nil, isLive: false) == "需要个人校准")
    }

    func testMissedFinalFrameDoesNotEraseSuccessfulScan() {
        var scan = ScanObservation()
        scan.add(.valid(faceWidth: 0.2), message: "")
        scan.add(.unavailable, message: "未检测到人脸，请面向镜头。")
        expect(scan.lastValidSample == .valid(faceWidth: 0.2))
        expect(scan.receivedSamples == 2)
        expect(scan.failureMessage == nil)
    }

    func testFailedScanKeepsSpecificFailureReason() {
        var scan = ScanObservation()
        scan.add(.unavailable, message: "未检测到人脸。")
        scan.add(.unavailable, message: "画面中有多人，请独自入镜。")
        expect(scan.lastValidSample == nil)
        expect(scan.failureMessage == "画面中有多人，请独自入镜。")
    }

    func testNoAnalysisResultsExplainsFiveSecondTimeout() {
        let scan = ScanObservation()
        expect(scan.failureMessage?.contains("5 秒内未收到分析结果") == true)
    }

    func testNewScanCannotReuseAnOlderMeasurement() {
        var first = ScanObservation()
        first.add(.valid(faceWidth: 0.2), message: "")
        var next = ScanObservation()
        next.add(.unavailable, message: "未检测到人脸。")
        expect(first.lastValidSample != nil)
        expect(next.lastValidSample == nil)
        expect(next.failureMessage == "未检测到人脸。")
    }
}
