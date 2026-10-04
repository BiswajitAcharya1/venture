import AVFoundation
import Foundation

// Convert the licensed public VOICED float text signal into a playback asset.
// Preserve the recorded vowel; only normalize gain and pad the tail to 5 s.
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let samples = try String(contentsOf: input, encoding: .utf8).split(whereSeparator: \.isWhitespace).compactMap { Float($0) }
guard samples.count >= 32_000, samples.allSatisfy({ $0.isFinite }) else { fatalError("Invalid source signal") }
let peak = samples.map(abs).max() ?? 0
guard peak > 0 else { fatalError("Silent example") }
let rate = 8_000.0
let frames = 40_000
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
buffer.frameLength = AVAudioFrameCount(frames)
for index in 0..<frames { buffer.floatChannelData![0][index] = index < samples.count ? samples[index] / peak * 0.7 : 0 }
let file = try AVAudioFile(forWriting: output, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
try file.write(from: buffer)
print("Prepared real vowel example: \(Double(frames) / rate) s")
