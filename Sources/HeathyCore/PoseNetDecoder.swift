import Foundation

/// PoseNet 0.75 / stride 16: heatmap channels and offset channels use COCO joint order.
public enum PoseNetDecoder {
    public static let modelID = "posenet075-s16-fit-v2"

    /// Undo centered square padding. Coordinates in the padding remain outside
    /// the image so the posture geometry rejects them rather than inventing a joint.
    public static func imagePoint(_ point: PosturePoint, width: Double, height: Double) -> PosturePoint? {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              point.x.isFinite, point.y.isFinite else { return nil }
        let side = max(width, height)
        let scaleX = width / side, scaleY = height / side
        return PosturePoint(x: (point.x - (1 - scaleX) / 2) / scaleX,
                            y: (point.y - (1 - scaleY) / 2) / scaleY, confidence: point.confidence)
    }

    public static func point(joint: Int, inputSize: Int, width: Int, height: Int,
                             heatmap: (Int, Int, Int) -> Double,
                             offsets: (Int, Int, Int) -> Double) -> PosturePoint? {
        guard (0..<17).contains(joint), inputSize > 0, width > 0, height > 0 else { return nil }
        var best = (x: 0, y: 0, confidence: -Double.infinity)
        for y in 0..<height {
            for x in 0..<width {
                let confidence = heatmap(joint, y, x)
                if confidence.isFinite && confidence > best.confidence { best = (x, y, confidence) }
            }
        }
        guard (0...1).contains(best.confidence) else { return nil }
        let x = (Double(best.x * 16) + offsets(joint + 17, best.y, best.x)) / Double(inputSize)
        let y = 1 - (Double(best.y * 16) + offsets(joint, best.y, best.x)) / Double(inputSize)
        guard x.isFinite, y.isFinite else { return nil }
        // Flip top-left model Y to bottom-left Y; imagePoint then removes padding.
        return PosturePoint(x: x, y: y, confidence: best.confidence)
    }
}
