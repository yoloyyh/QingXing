import CoreML
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Resources/PoseNet/PoseNetMobileNet075S16FP16.mlmodel")
let destination = root.appendingPathComponent(".build/pose-model/PoseNetMobileNet075S16FP16.mlmodelc")
let compiled = try MLModel.compileModel(at: source)
defer { try? FileManager.default.removeItem(at: compiled) }
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
try FileManager.default.copyItem(at: compiled, to: destination)
print("Compiled bundled shoulder model")
