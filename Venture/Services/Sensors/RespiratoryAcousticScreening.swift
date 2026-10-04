import Accelerate
import Foundation

struct RespiratoryAcousticScreenResult: Sendable, Equatable {
    let wheezeLikelihood: Double
    let recordingQuality: Double
    let breathSeconds: Double
    let airflowIrregularity: Double

    var classification: String {
        wheezeLikelihood >= 0.65
            ? "elevated wheeze-like acoustic pattern"
            : "lower wheeze-like acoustic pattern"
    }

    var needsFollowUp: Bool {
        wheezeLikelihood >= 0.65 && recordingQuality >= 0.45
    }
}

enum RespiratoryAcousticScreeningError: LocalizedError {
    case insufficientAudio
    case insufficientBreath
    case predictionFailed

    var errorDescription: String? {
        switch self {
        case .insufficientAudio:
            "Record a longer breathing sample before screening."
        case .insufficientBreath:
            "A usable breathing signal was not detected. Hold the phone close to the mouth or upper chest in a quiet room."
        case .predictionFailed:
            "The breathing audio features could not be processed."
        }
    }
}

enum RespiratoryAcousticScreeningEngine {
    private static let frameSize = 1_024
    private static let hop = 512
    private static var dftSetup: vDSP_DFT_Setup?
    private static var window: [Float]?
    private static var realIn: [Float]?
    private static var imaginaryIn: [Float]?
    private static var realOut: [Float]?
    private static var imaginaryOut: [Float]?

    private static func ensureBuffers() {
        if dftSetup == nil {
            dftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(frameSize), .FORWARD)
        }
        if window == nil {
            window = [Float](repeating: 0, count: frameSize)
            vDSP_hann_window(&window!, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
        }
        if realIn == nil {
            realIn = [Float](repeating: 0, count: frameSize)
            imaginaryIn = [Float](repeating: 0, count: frameSize)
            realOut = [Float](repeating: 0, count: frameSize)
            imaginaryOut = [Float](repeating: 0, count: frameSize)
        }
    }

    static func screen(samples: [Float], sampleRate: Double) throws -> RespiratoryAcousticScreenResult {
        guard sampleRate > 0, samples.count >= Int(sampleRate * 2) else {
            throw RespiratoryAcousticScreeningError.insufficientAudio
        }
        let centered = removeDC(samples)
        guard centered.count >= frameSize, let setup = dftSetup ?? { ensureBuffers(); return dftSetup }() else {
            throw RespiratoryAcousticScreeningError.insufficientAudio
        }

        ensureBuffers()
        var activeRMS: [Double] = []
        activeRMS.reserveCapacity(centered.count / hop)
        var wheezeFrames = 0
        var sustainedWheezeFrames = 0
        var previousWasWheeze = false
        var peakDominanceValues: [Double] = []
        peakDominanceValues.reserveCapacity(centered.count / hop)

        for start in stride(from: 0, through: centered.count - frameSize, by: hop) {
            for index in 0..<frameSize {
                realIn![index] = centered[start + index] * window![index]
            }

            let rms = sqrt(realIn!.reduce(0.0) { $0 + Double($1 * $1) } / Double(frameSize))
            guard rms > 0.004 else {
                previousWasWheeze = false
                continue
            }
            activeRMS.append(rms)

            for index in 0..<frameSize { imaginaryIn![index] = 0 }
            vDSP_DFT_Execute(setup, &realIn!, &imaginaryIn!, &realOut!, &imaginaryOut!)

            let lowerBin = max(2, Int(100 * Double(frameSize) / sampleRate))
            let upperBin = min(frameSize / 2 - 2, Int(3_000 * Double(frameSize) / sampleRate))
            let wheezeLower = max(lowerBin, Int(400 * Double(frameSize) / sampleRate))
            let wheezeUpper = min(upperBin, Int(1_600 * Double(frameSize) / sampleRate))
            guard lowerBin < upperBin, wheezeLower < wheezeUpper else { continue }

            var totalEnergy = 0.0
            var wheezeEnergy = 0.0
            var wheezePeak = 0.0
            for bin in lowerBin...upperBin {
                let magnitude = hypot(Double(realOut![bin]), Double(imaginaryOut![bin]))
                totalEnergy += magnitude
                if bin >= wheezeLower && bin <= wheezeUpper {
                    wheezeEnergy += magnitude
                    wheezePeak = max(wheezePeak, magnitude)
                }
            }
            guard totalEnergy > 0, wheezeEnergy > 0 else { continue }

            let bandRatio = wheezeEnergy / totalEnergy
            let averageWheezeBin = wheezeEnergy / Double(wheezeUpper - wheezeLower + 1)
            let peakDominance = wheezePeak / max(averageWheezeBin, 1e-9)
            peakDominanceValues.append(peakDominance)

            let isWheezeLike = bandRatio >= 0.42 && peakDominance >= 5.5
            if isWheezeLike {
                wheezeFrames += 1
                if previousWasWheeze { sustainedWheezeFrames += 1 }
            }
            previousWasWheeze = isWheezeLike
        }

        let activeFrames = activeRMS.count
        let breathSeconds = Double(activeFrames * hop) / sampleRate
        guard breathSeconds >= 1 else { throw RespiratoryAcousticScreeningError.insufficientBreath }

        let wheezeFrameRatio = Double(wheezeFrames) / Double(max(activeFrames, 1))
        let sustainedRatio = Double(sustainedWheezeFrames) / Double(max(activeFrames - 1, 1))
        let dominance = min(1, max(0, ((peakDominanceValues.mean ?? 0) - 4) / 8))
        let likelihood = min(1, max(0, sustainedRatio * 0.55 + wheezeFrameRatio * 0.3 + dominance * 0.15))
        let meanRMS = activeRMS.mean ?? 0
        let irregularity = min(1, standardDeviation(activeRMS, mean: meanRMS) / max(meanRMS, 1e-6))
        let quality = min(1, max(0, (breathSeconds / 4) * min(1, meanRMS / 0.035)))

        guard likelihood.isFinite, quality.isFinite, irregularity.isFinite else {
            throw RespiratoryAcousticScreeningError.predictionFailed
        }
        return RespiratoryAcousticScreenResult(
            wheezeLikelihood: likelihood,
            recordingQuality: quality,
            breathSeconds: breathSeconds,
            airflowIrregularity: irregularity
        )
    }

    private static func removeDC(_ samples: [Float]) -> [Float] {
        var mean: Double = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(samples.count))
        var centered = [Float](repeating: 0, count: samples.count)
        var negMean = Float(-mean)
        vDSP_vsadd(samples, 1, &negMean, &centered, 1, vDSP_Length(samples.count))
        return centered
    }

    private static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        var variance: Double = 0
        var diff = [Double](repeating: 0, count: values.count)
        vDSP_vsubD(values, 1, &mean, &diff, 1, vDSP_Length(values.count))
        vDSP_measqv(diff, 1, &variance, vDSP_Length(values.count))
        return sqrt(variance)
    }
}

private extension Array where Element == Double {
    var mean: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}
