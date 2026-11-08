import Foundation
import AVFoundation
import RNNoiseC

/// RNNoise 的循环神经网络在后台运行；原文件只读。
nonisolated enum VoiceRepairWorker {
    enum Failure: Error { case invalidAudio, conversion, model, tooLong }

    private static let processingLock = NSLock()

    static func repair(url: URL) throws -> Data {
        processingLock.lock()
        defer { processingLock.unlock() }
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw Failure.invalidAudio }
        guard Double(file.length) / file.processingFormat.sampleRate <= 300 else { throw Failure.tooLong }
        guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: format) else { throw Failure.conversion }
        try file.read(into: source)
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * 48_000 / file.processingFormat.sampleRate)) + 2048
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw Failure.conversion }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .endOfStream; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error, error == nil, converted.frameLength > 0,
              let channel = converted.floatChannelData?[0] else { throw Failure.conversion }
        guard let model = rnnoise_create() else { throw Failure.model }
        defer { rnnoise_destroy(model) }
        let count = Int(converted.frameLength)
        let frameSize = 480
        let frameCount = (count + frameSize - 1) / frameSize
        var input = [Float](repeating: 0, count: frameSize)
        var output = input
        var pcm = Data(capacity: count * 2)
        // RNNoise 有一帧延迟；丢弃首帧，再补一个空帧，保持录音时长。
        for frame in 0...frameCount {
            try Task.checkCancellation()
            for index in 0..<frameSize {
                let position = frame * frameSize + index
                input[index] = position < count ? channel[position] * 32768 : 0
            }
            input.withUnsafeBufferPointer { inputBuffer in
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    _ = rnnoise_process_frame(model, outputBuffer.baseAddress!, inputBuffer.baseAddress!)
                }
            }
            if frame > 0 {
                let remaining = min(frameSize, count - (frame - 1) * frameSize)
                for value in output.prefix(remaining) {
                    let sample = Int16(max(-32768, min(32767, value.isFinite ? value.rounded() : 0)))
                    append(sample, to: &pcm)
                }
            }
        }
        return wav(pcm)
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    private static func wav(_ pcm: Data) -> Data {
        var data = Data("RIFF".utf8)
        append(UInt32(36 + pcm.count), to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(48_000), to: &data)
        append(UInt32(96_000), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        append(UInt32(pcm.count), to: &data)
        data.append(pcm)
        return data
    }
}
