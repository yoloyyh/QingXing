import CoreML
import HeathyCore
import Vision

/// Bundled PoseNet model; only the nose and two shoulders are decoded in memory.
final class PoseNetShoulderDetector {
    struct Points {
        let nose: PosturePoint?
        let left: PosturePoint
        let right: PosturePoint
    }
    enum Failure: LocalizedError {
        case missingModel, invalidOutput
        var errorDescription: String? {
            switch self {
            case .missingModel: return "肩部模型未加载，请重新打开完整的轻醒应用。"
            case .invalidOutput: return "肩部模型结果格式不可用，请重新打开应用。"
            }
        }
    }
    private var request: VNCoreMLRequest?

    func prepare() throws {
        guard request == nil else { return }
        guard let url = Bundle.main.url(forResource: "PoseNetMobileNet075S16FP16", withExtension: "mlmodelc") else {
            throw Failure.missingModel
        }
        let model = try MLModel(contentsOf: url)
        let prepared = VNCoreMLRequest(model: try VNCoreMLModel(for: model))
        prepared.imageCropAndScaleOption = .scaleFit
        request = prepared
    }

    func points(using handler: VNImageRequestHandler, imageWidth: Int, imageHeight: Int) throws -> Points {
        guard let request else { throw Failure.missingModel }
        try handler.perform([request])
        let results = request.results as? [VNCoreMLFeatureValueObservation] ?? []
        if CommandLine.arguments.contains("--check-shoulder-model") {
            print("MODEL OUTPUTS: " + results.map { "\($0.featureName)=\($0.featureValue.multiArrayValue?.shape ?? [])" }.joined(separator: ", "))
        }
        guard let heatmap = results.first(where: { $0.featureName == "heatmap" })?.featureValue.multiArrayValue,
              let offsets = results.first(where: { $0.featureName == "offsets" })?.featureValue.multiArrayValue,
              heatmap.shape.count == 3, offsets.shape.count == 3 else { throw Failure.invalidOutput }
        let grid = heatmap.shape[1].intValue
        // Vision may select any of the model's enumerated input sizes, rather than
        // the 513 default in modelDescription. Decode the size that actually ran.
        let inputSize = (grid - 1) * 16 + 1
        guard [257, 353, 513].contains(inputSize),
              heatmap.shape.map(\.intValue) == [17, grid, grid],
              offsets.shape.map(\.intValue) == [34, grid, grid] else { throw Failure.invalidOutput }
        func point(_ joint: Int) -> PosturePoint? {
            guard let point = PoseNetDecoder.point(joint: joint, inputSize: inputSize, width: grid, height: grid,
                heatmap: { channel, y, x in heatmap[[channel, y, x].map(NSNumber.init(value:))].doubleValue },
                offsets: { channel, y, x in offsets[[channel, y, x].map(NSNumber.init(value:))].doubleValue }) else { return nil }
            return PoseNetDecoder.imagePoint(point, width: Double(imageWidth), height: Double(imageHeight))
        }
        guard let left = point(5), let right = point(6) else { throw Failure.invalidOutput }
        return Points(nose: point(0), left: left, right: right)
    }

    static func checkBundledModel() throws {
        let detector = PoseNetShoulderDetector()
        try detector.prepare()
        var pixels: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 640, 480, kCVPixelFormatType_32BGRA, nil, &pixels) == kCVReturnSuccess,
              let pixels else { throw Failure.invalidOutput }
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) { memset(base, 0, CVPixelBufferGetDataSize(pixels)) }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        let result = try detector.points(using: VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up), imageWidth: 640, imageHeight: 480)
        print("MODEL BLANK CONFIDENCE: left=\(result.left.confidence), right=\(result.right.confidence)")
        guard result.left.confidence < 0.5, result.right.confidence < 0.5 else { throw Failure.invalidOutput }
        print("PASS: bundled PoseNet loads, predicts compatible heatmaps and offsets; blank image shoulders rejected")
    }
}
