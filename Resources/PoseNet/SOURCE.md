# PoseNet shoulder model

Unmodified `PoseNetMobileNet075S16FP16.mlmodel` from Apple's PoseFinder sample:

- Documentation: https://developer.apple.com/documentation/coreml/detecting-human-body-poses-in-an-image
- Download: https://docs-assets.developer.apple.com/published/3e1c865293a0/DetectingHumanBodyPosesInAnImage.zip
- Retrieved: 2026-11-05
- SHA-256: `593cd60c316977f4bc8ec0ef51e6b5b7a11279d1ecf13f790f7d33a219e30383`
- Model: Apache 2.0, see ACKNOWLEDGMENTS.txt; sample license: LICENSE.txt.

Builds compile this model into the app bundle. The model supports enumerated 257/353/513 square inputs at stride 16. Vision selected 353×353 in the local 640×480 blank-image check, despite modelDescription listing a 513 default; decoding uses the actual validated output grid size. Runtime inference is local; there is no model download or network access. The decoder uses the sample's single-person heatmap maximum plus per-joint offsets, adapted to normalized bottom-left coordinates. Only nose and shoulders are decoded. Confidence and geometry acceptance remain separate from decoding.

Version `posenet075-s16-fit-v2` uses centered aspect-fit padding, matching the aspect-preserving approach in TensorFlow's upstream implementation rather than stretching the camera image. Decoded points are mapped back to the unpadded camera image; points in padding remain outside its valid bounds. Model weights are unchanged. The previous stretched-input reference is not reused for posture assessment.

The separate development regression uses public TensorFlow fixtures from https://github.com/tensorflow/tfjs-models/tree/master/pose-detection/test_data (`pose_squats.mp4`, `pose_squats.full.json`, `pose_1.mp4`, `pose_1.json`). These are downloaded only by the explicit development check, cached in `.build`, and never bundled in the app. Reference points are upstream regression outputs, not manually labeled clinical ground truth.
