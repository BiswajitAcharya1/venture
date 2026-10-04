import CoreVideo
import Foundation
import MediaPipeTasksVision

// Called only on the serial camera queue. Landmarks locate the eyes; they do
// not themselves measure pupil dilation or establish a disease probability.
final class MediaPipeIrisTracker {
    struct Eyes {
        let left: [CGPoint]
        let right: [CGPoint]
        let leftIris: [CGPoint]
        let rightIris: [CGPoint]
    }
    private let detector: FaceLandmarker
    init() throws {
        guard let path = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else { throw CocoaError(.fileNoSuchFile) }
        let options = FaceLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .image
        options.numFaces = 1
        options.minFaceDetectionConfidence = 0.6
        options.minFacePresenceConfidence = 0.6
        options.minTrackingConfidence = 0.6
        detector = try FaceLandmarker(options: options)
    }
    func detect(_ buffer: CVPixelBuffer) throws -> Eyes? {
        let image = try MPImage(pixelBuffer: buffer)
        guard let face = try detector.detect(image: image).faceLandmarks.first, face.count >= 478 else { return nil }
        func points(_ indices: [Int]) -> [CGPoint] {
            indices.map { CGPoint(x: CGFloat(face[$0].x), y: CGFloat(face[$0].y)) }
        }
        return Eyes(
            left: points([33, 160, 158, 133, 153, 144]),
            right: points([362, 385, 387, 263, 373, 380]),
            leftIris: points([469, 470, 471, 472]),
            rightIris: points([474, 475, 476, 477])
        )
    }
}
