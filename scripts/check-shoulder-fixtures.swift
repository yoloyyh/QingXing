import AVFoundation
import CoreGraphics
import Foundation
import Vision

/// Public TensorFlow fixtures only. This executable is never included in the app.
@main
enum ShoulderFixtureChecks {
    static func main() async throws {
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/pose-fixtures")
        let detector = PoseNetShoulderDetector()
        try detector.prepare()
        var checked = 0, passed = 0
        var largestError = 0.0
        var largestLatency = 0.0
        for source in ["pose_squats", "pose_1"] {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: folder.appendingPathComponent(source + ".mp4")))
            generator.appliesPreferredTrackTransform = true
            let image = try await generator.image(at: .zero).image
            let left: [Double], right: [Double], nose: [Double]
            if source == "pose_squats" {
                let reference = (try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("pose_squats.full.json"))) as! [[[Double]]])[0]
                left = reference[11]; right = reference[12]; nose = reference[0]
            } else {
                let reference = (try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("pose_1.json"))) as! [[String: [String: Double]]])[0]
                func point(_ name: String) -> [Double] { [reference[name]!["x"]!, reference[name]!["y"]!] }
                left = point("left_shoulder"); right = point("right_shoulder"); nose = point("nose")
            }
            let span = hypot(left[0] - right[0], left[1] - right[1])
            for aspect in [4.0 / 3, 16.0 / 9] {
                for factor in [2.4, 3.0, 4.0] {
                    for shift in [-0.15, 0.0, 0.15] {
                        let width = span * factor
                        let crop = CGRect(x: (left[0] + right[0]) / 2 - width / 2 + shift * span,
                            y: nose[1] - span * 0.5, width: width, height: width / aspect).integral
                            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
                        let clipped = image.cropping(to: crop)!
                        let height = Int(640 / aspect)
                        let context = CGContext(data: nil, width: 640, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                        context.interpolationQuality = .high
                        context.draw(clipped, in: CGRect(x: 0, y: 0, width: 640, height: height))
                        let sample = context.makeImage()!
                        let start = ProcessInfo.processInfo.systemUptime
                        let points = try detector.points(using: VNImageRequestHandler(cgImage: sample), imageWidth: sample.width, imageHeight: sample.height)
                        largestLatency = max(largestLatency, ProcessInfo.processInfo.systemUptime - start)
                        let actual = [points.left, points.right]
                        let expected = [left, right].map { (($0[0] - crop.minX) / crop.width, 1 - ($0[1] - crop.minY) / crop.height) }
                        let error = zip(actual, expected).map {
                            hypot(($0.0.x - $0.1.0) * crop.width, ($0.0.y - $0.1.1) * crop.height) / span
                        }.max()!
                        let accepted = actual.allSatisfy { $0.confidence >= 0.5 } && error < 0.12
                        checked += 1
                        if accepted { passed += 1 }
                        else { print("FAIL \(source) aspect=\(aspect) crop=\(factor)/\(shift) confidence=\(actual.map(\.confidence)) error=\(error)") }
                        largestError = max(largestError, error)
                    }
                }
            }
        }
        print("Public near-camera fixtures: \(passed)/\(checked); max reference error=\(largestError) shoulder spans; max inference=\(largestLatency * 1000) ms")
        guard passed == checked, checked == 36 else { exit(1) }
    }
}
