import AVFoundation
import Combine
import CoreImage
import Vision

enum FaceCapturePosition: Equatable, Sendable {
    case noFace
    case tooFar
    case tooClose
    case offCenter
    case ready

    static func classify(bounds: CGRect) -> FaceCapturePosition {
        guard !bounds.isEmpty else { return .noFace }
        if bounds.width < 0.40 { return .tooFar }
        if bounds.width > 0.78 { return .tooClose }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if abs(center.x - 0.5) > 0.14 || abs(center.y - 0.48) > 0.18 { return .offCenter }
        return .ready
    }
}

final class EyeTrackingService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum PupilSamplingPhase: Sendable {
        case idle
        case baseline
        case bright
        case gaze
    }

    let session = AVCaptureSession()

    @Published private(set) var faceDetected = false
    @Published private(set) var leftEye = CGPoint(x: 0.4, y: 0.43)
    @Published private(set) var rightEye = CGPoint(x: 0.6, y: 0.43)
    @Published private(set) var leftEyeContour: [CGPoint] = []
    @Published private(set) var rightEyeContour: [CGPoint] = []
    @Published private(set) var faceBounds = CGRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7)
    @Published private(set) var capturePosition: FaceCapturePosition = .noFace
    @Published private(set) var confidence: Double = 0
    @Published private(set) var fixationStability: Double = 0
    @Published private(set) var blinkCount = 0
    @Published private(set) var sampleCount = 0
    @Published private(set) var pupilSampleCount = 0
    @Published private(set) var baselinePupilSampleCount = 0
    @Published private(set) var brightPupilSampleCount = 0
    @Published private(set) var currentPupilDiameter: Double?
    @Published private(set) var pupilSymmetry: Double?
    @Published private(set) var pupilResponse: Double?
    @Published private(set) var pupilVariability: Double?
    @Published private(set) var currentGazePoint: CGPoint?
    @Published private(set) var gazeSampleCount = 0
    @Published private(set) var permissionDenied = false

    private let queue = DispatchQueue(label: "com.venture.eye-tracking", qos: .userInitiated)
    private var configured = false
    private var isProcessingFrame = false
    private var eyeCenterHistory: [CGPoint] = []
    private var eyesWereClosed = false
    private var frameIndex = 0
    private var pupilSamplingPhase: PupilSamplingPhase = .idle
    private var baselinePupilSamples: [Double] = []
    private var brightPupilSamples: [Double] = []
    private let imageContext = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
    private lazy var mediaPipe = try? MediaPipeIrisTracker()
    private let landmarkRequest = VNDetectFaceLandmarksRequest()
    private var lastProcessTime = Date.distantPast
    private let minimumFrameInterval: TimeInterval = 1.0 / 6.0
    private var isMemoryPressureHigh = false

    override init() {
        super.init()
        landmarkRequest.revision = VNDetectFaceLandmarksRequestRevision3
        MemoryPressureMonitor.shared.addHandler { [weak self] level in
            Task { @MainActor [weak self] in
                self?.handleMemoryPressure(level)
            }
        }
    }

    @MainActor
    private func handleMemoryPressure(_ level: MemoryPressureLevel) {
        switch level {
        case .normal:
            isMemoryPressureHigh = false
        case .warning, .critical:
            isMemoryPressureHigh = true
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func setPupilSamplingPhase(_ phase: PupilSamplingPhase) {
        queue.async { [weak self] in
            guard let self else { return }
            if phase == .baseline {
                baselinePupilSamples.removeAll(keepingCapacity: true)
                brightPupilSamples.removeAll(keepingCapacity: true)
                DispatchQueue.main.async {
                    self.baselinePupilSampleCount = 0
                    self.brightPupilSampleCount = 0
                    self.currentPupilDiameter = nil
                    self.pupilResponse = nil
                    self.pupilVariability = nil
                }
            }
            if phase == .gaze {
                DispatchQueue.main.async {
                    self.gazeSampleCount = 0
                    self.currentGazePoint = nil
                }
            }
            pupilSamplingPhase = phase
        }
    }

    func start() async {
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            authorized = false
        }

        guard authorized else {
            await MainActor.run { permissionDenied = true }
            return
        }

        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                let ready = self.configureIfNeeded()
                if ready {
                    self.session.startRunning()
                } else {
                    DispatchQueue.main.async { self.permissionDenied = true }
                }
                continuation.resume()
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureIfNeeded() -> Bool {
        guard !configured else { return !session.inputs.isEmpty && !session.outputs.isEmpty }
        session.beginConfiguration()
        session.sessionPreset = .medium
        defer {
            session.commitConfiguration()
            configured = true
        }

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else { return false }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            connection.videoRotationAngle = 90
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingFrame, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastProcessTime)
        let shouldProcess: Bool
        switch pupilSamplingPhase {
        case .idle:
            shouldProcess = elapsed >= 1.0 / 3.0
        case .baseline, .bright:
            shouldProcess = elapsed >= minimumFrameInterval
        case .gaze:
            shouldProcess = elapsed >= 1.0 / 10.0
        }

        guard shouldProcess else { return }
        lastProcessTime = now

        isProcessingFrame = true
        frameIndex += 1

        guard let tracker = mediaPipe, let tracked = try? tracker.detect(pixelBuffer) else {
            isProcessingFrame = false
            DispatchQueue.main.async { self.faceDetected = false; self.capturePosition = .noFace }
            return
        }

        let request = landmarkRequest
        request.inputFaceObservations = nil
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:]).perform([request])

        guard let self = self else { return }
        guard let face = request.results?.first as? VNFaceObservation else {
            DispatchQueue.main.async {
                self.faceDetected = false
                self.capturePosition = .noFace
                self.leftEyeContour = []
                self.rightEyeContour = []
                self.confidence = max(0, self.confidence - 0.04)
            }
            self.isProcessingFrame = false
            return
        }

        let leftContour = tracked.left
        let rightContour = tracked.right
        let left = self.center(of: leftContour) ?? CGPoint(x: 0.4, y: 0.43)
        let right = self.center(of: rightContour) ?? CGPoint(x: 0.6, y: 0.43)
        let midpoint = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        let closed = self.eyeAspectRatio(leftContour) < 0.17 && self.eyeAspectRatio(rightContour) < 0.17
        self.eyeCenterHistory.append(midpoint)
        if self.eyeCenterHistory.count > 45 { self.eyeCenterHistory.removeFirst() }
        let stability = self.stability(of: self.eyeCenterHistory, faceWidth: face.boundingBox.width)
        let didBlink = closed && !self.eyesWereClosed
        self.eyesWereClosed = closed
        let shouldMeasurePupil = self.pupilSamplingPhase != .idle && !closed
        let pupilEstimate = shouldMeasurePupil
            ? self.pupilEstimate(pixelBuffer: pixelBuffer, face: face, tracked: tracked)
            : nil

        if let pupilEstimate {
            let average = (pupilEstimate.left.diameter + pupilEstimate.right.diameter) / 2
            switch self.pupilSamplingPhase {
            case .baseline:
                self.baselinePupilSamples.append(average)
            case .bright:
                self.brightPupilSamples.append(average)
            case .idle, .gaze:
                break
            }
            if self.baselinePupilSamples.count > 90 { self.baselinePupilSamples.removeFirst() }
            if self.brightPupilSamples.count > 180 { self.brightPupilSamples.removeFirst() }
        }

        let pupilSummary = self.pupilSummary(latest: pupilEstimate)
        let gazePoint = pupilEstimate.map {
            CGPoint(
                x: ($0.left.center.x + $0.right.center.x) / 2,
                y: ($0.left.center.y + $0.right.center.y) / 2
            )
        }

        let displayBounds = CGRect(
            x: face.boundingBox.minX,
            y: 1 - face.boundingBox.maxY,
            width: face.boundingBox.width,
            height: face.boundingBox.height
        )

        DispatchQueue.main.async {
            self.faceDetected = true
            self.leftEye = left
            self.rightEye = right
            self.leftEyeContour = leftContour
            self.rightEyeContour = rightContour
            self.faceBounds = displayBounds
            self.capturePosition = FaceCapturePosition.classify(bounds: displayBounds)
            self.sampleCount += 1
            self.fixationStability = stability
            if didBlink { self.blinkCount += 1 }
            if pupilEstimate != nil {
                self.pupilSampleCount += 1
                switch self.pupilSamplingPhase {
                case .baseline:
                    self.baselinePupilSampleCount = self.baselinePupilSamples.count
                case .bright:
                    self.brightPupilSampleCount = self.brightPupilSamples.count
                case .gaze:
                    self.gazeSampleCount += 1
                case .idle:
                    break
                }
                self.currentPupilDiameter = pupilSummary.currentDiameter
                self.pupilSymmetry = pupilSummary.symmetry
                self.pupilResponse = pupilSummary.response
                self.pupilVariability = pupilSummary.variability
                self.currentGazePoint = gazePoint
            }
            let landmarkQuality = leftContour.isEmpty || rightContour.isEmpty ? 0.55 : 1.0
            self.confidence = min(1, self.confidence + 0.02 * landmarkQuality)
        }
        self.isProcessingFrame = false
    }

    private struct PupilRegionEstimate {
        let diameter: Double
        let center: CGPoint
    }

    private struct PupilEstimate {
        let left: PupilRegionEstimate
        let right: PupilRegionEstimate
    }

    private func pupilEstimate(pixelBuffer: CVPixelBuffer, face: VNFaceObservation, tracked: MediaPipeIrisTracker.Eyes) -> PupilEstimate? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard
            let left = pupilDiameter(points: tracked.left.map { CGPoint(x: $0.x, y: 1 - $0.y) }, image: image),
            let right = pupilDiameter(points: tracked.right.map { CGPoint(x: $0.x, y: 1 - $0.y) }, image: image)
        else { return nil }
        return PupilEstimate(left: left, right: right)
    }

    private func pupilDiameter(
        in region: VNFaceLandmarkRegion2D?,
        face: VNFaceObservation,
        image: CIImage
    ) -> PupilRegionEstimate? {
        guard let region, region.pointCount >= 6 else { return nil }
        let points = region.normalizedPoints.map { point in
            CGPoint(
                x: face.boundingBox.minX + point.x * face.boundingBox.width,
                y: face.boundingBox.minY + point.y * face.boundingBox.height
            )
        }
        return pupilDiameter(points: points, image: image)
    }

    private func pupilDiameter(points: [CGPoint], image: CIImage) -> PupilRegionEstimate? {
        guard points.count >= 6 else { return nil }
        guard
            let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
            let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return nil }

        let normalizedRect = CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 0.001),
            height: max(maxY - minY, 0.001)
        )
        let extent = image.extent
        var cropRect = CGRect(
            x: extent.minX + normalizedRect.minX * extent.width,
            y: extent.minY + normalizedRect.minY * extent.height,
            width: normalizedRect.width * extent.width,
            height: normalizedRect.height * extent.height
        )
        cropRect = cropRect.insetBy(dx: cropRect.width * 0.17, dy: cropRect.height * 0.12)
        guard cropRect.width >= 8, cropRect.height >= 4 else { return nil }

        let outputWidth = 48
        let outputHeight = 24
        let translated = image
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
            .transformed(by: CGAffineTransform(
                scaleX: CGFloat(outputWidth) / cropRect.width,
                y: CGFloat(outputHeight) / cropRect.height
            ))
        var pixels = [UInt8](repeating: 0, count: outputWidth * outputHeight)
        imageContext.render(
            translated,
            toBitmap: &pixels,
            rowBytes: outputWidth,
            bounds: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight),
            format: .L8,
            colorSpace: nil
        )

        let centralPixels = pixels.enumerated().compactMap { index, luminance -> (Int, Int, UInt8)? in
            let x = index % outputWidth
            let y = index / outputWidth
            let dx = (Double(x) - Double(outputWidth - 1) / 2) / (Double(outputWidth) * 0.34)
            let dy = (Double(y) - Double(outputHeight - 1) / 2) / (Double(outputHeight) * 0.42)
            return dx * dx + dy * dy <= 1 ? (x, y, luminance) : nil
        }
        guard centralPixels.count > 40 else { return nil }
        let sortedLuminance = centralPixels.map(\.2).sorted()
        let threshold = sortedLuminance[max(0, Int(Double(sortedLuminance.count) * 0.22) - 1)]
        let dark = centralPixels.filter { $0.2 <= threshold }
        guard dark.count > 8 else { return nil }

        let meanX = dark.reduce(0.0) { $0 + Double($1.0) } / Double(dark.count)
        let meanY = dark.reduce(0.0) { $0 + Double($1.1) } / Double(dark.count)
        let radialVariance = dark.reduce(0.0) { partial, pixel in
            let dx = (Double(pixel.0) - meanX) / Double(outputWidth)
            let dy = (Double(pixel.1) - meanY) / Double(outputHeight)
            return partial + dx * dx + dy * dy
        } / Double(dark.count)
        return PupilRegionEstimate(
            diameter: max(0.04, min(0.42, sqrt(radialVariance) * 3.7)),
            center: CGPoint(
                x: min(1, max(0, meanX / Double(outputWidth - 1))),
                y: min(1, max(0, meanY / Double(outputHeight - 1)))
            )
        )
    }

    private func pupilSummary(latest: PupilEstimate?) -> (
        currentDiameter: Double?, symmetry: Double?, response: Double?, variability: Double?
    ) {
        let current = latest.map { ($0.left.diameter + $0.right.diameter) / 2 }
        let symmetry = latest.map { estimate in
            let larger = max(max(estimate.left.diameter, estimate.right.diameter), 0.01)
            return max(0, min(1, 1 - abs(estimate.left.diameter - estimate.right.diameter) / larger))
        }
        let baseline = robustMean(baselinePupilSamples)
        let bright = robustMean(brightPupilSamples)
        let response: Double?
        if let baseline, let bright, baselinePupilSamples.count >= 4, brightPupilSamples.count >= 6 {
            response = max(-0.5, min(0.8, (baseline - bright) / max(baseline, 0.01)))
        } else {
            response = nil
        }
        let combined = Array((baselinePupilSamples + brightPupilSamples).suffix(80))
        let variability: Double?
        if combined.count >= 6 {
            let mean = combined.reduce(0, +) / Double(combined.count)
            let deviation = sqrt(combined.reduce(0) { $0 + pow($1 - mean, 2) } / Double(combined.count))
            variability = min(1, deviation / max(mean, 0.01))
        } else {
            variability = nil
        }
        return (current, symmetry, response, variability)
    }

    private func robustMean(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        let sorted = values.sorted()
        let trim = values.count >= 10 ? values.count / 10 : 0
        let kept = sorted.dropFirst(trim).dropLast(trim)
        return kept.reduce(0, +) / Double(kept.count)
    }

    private func points(of region: VNFaceLandmarkRegion2D?, face: VNFaceObservation) -> [CGPoint] {
        guard let region, region.pointCount > 0 else { return [] }
        return region.normalizedPoints.map { point in
            CGPoint(
                x: face.boundingBox.minX + point.x * face.boundingBox.width,
                y: 1 - (face.boundingBox.minY + point.y * face.boundingBox.height)
            )
        }
    }

    private func center(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let localX = points.reduce(0) { $0 + $1.x } / CGFloat(points.count)
        let localY = points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
        return CGPoint(x: localX, y: localY)
    }

    private func eyeAspectRatio(_ points: [CGPoint]) -> CGFloat {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return 1 }
        return (maxY - minY) / max(maxX - minX, 0.001)
    }

    private func stability(of points: [CGPoint], faceWidth: CGFloat) -> Double {
        guard points.count > 6 else { return 0 }
        let meanX = points.reduce(0) { $0 + $1.x } / CGFloat(points.count)
        let meanY = points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
        let variance = points.reduce(CGFloat.zero) { partial, point in
            let dx = point.x - meanX
            let dy = point.y - meanY
            return partial + dx * dx + dy * dy
        } / CGFloat(points.count)
        let normalizedMovement = sqrt(variance) / max(faceWidth, 0.1)
        return max(0, min(1, 1 - Double(normalizedMovement / 0.055)))
    }
}
