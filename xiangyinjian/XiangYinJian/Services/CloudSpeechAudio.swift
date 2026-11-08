import Foundation

/// 云端 WAV 有时保留流式输出的长度占位值，下载完成后按真实 PCM 长度封口。
nonisolated enum CloudSpeechAudio {
    enum Failure: LocalizedError {
        case invalidWAV
        var errorDescription: String? { "The speech service returned invalid WAV audio." }
    }

    static func normalizedWAV(_ data: Data) throws -> Data {
        guard data.count >= 44, data.count <= 20 * 1024 * 1024,
              data.prefix(4) == Data("RIFF".utf8),
              data.subdata(in: 8..<12) == Data("WAVE".utf8) else { throw Failure.invalidWAV }
        var output = data
        func uint32(at offset: Int) -> Int {
            Int(data[offset]) | Int(data[offset + 1]) << 8
                | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
        }
        func writeLength(_ length: Int, at offset: Int) {
            for byte in 0..<4 { output[offset + byte] = UInt8((length >> (byte * 8)) & 0xff) }
        }
        // 已观察到 0x7fffffbf/0x7fffff9b 和常见 0xffffffff 占位形式。
        // 普通短文件长度不符仍应报错，避免把下载截断的音频当作完整结果。
        func isPlaceholder(_ length: Int) -> Bool { length >= 0x7fff0000 }
        let riffLength = uint32(at: 4)
        guard riffLength == data.count - 8 || isPlaceholder(riffLength) else { throw Failure.invalidWAV }
        var offset = 12
        var blockAlign = 0
        var foundAudio = false
        while offset + 8 <= data.count {
            let tag = data.subdata(in: offset..<offset + 4)
            let declaredLength = uint32(at: offset + 4)
            let start = offset + 8
            let remaining = data.count - start
            if tag == Data("data".utf8) {
                guard blockAlign > 0, !foundAudio else { throw Failure.invalidWAV }
                let length = isPlaceholder(declaredLength) ? remaining : declaredLength
                guard length > 0, length <= remaining, length % blockAlign == 0 else { throw Failure.invalidWAV }
                writeLength(length, at: offset + 4)
                foundAudio = true
                offset = start + length + length % 2
            } else {
                guard declaredLength <= remaining else { throw Failure.invalidWAV }
                if tag == Data("fmt ".utf8) {
                    guard declaredLength >= 16 else { throw Failure.invalidWAV }
                    let format = Int(data[start]) | Int(data[start + 1]) << 8
                    let channels = Int(data[start + 2]) | Int(data[start + 3]) << 8
                    let bits = Int(data[start + 14]) | Int(data[start + 15]) << 8
                    blockAlign = Int(data[start + 12]) | Int(data[start + 13]) << 8
                    guard format == 1, (1...2).contains(channels), bits == 16,
                          blockAlign == channels * 2,
                          uint32(at: start + 4) > 0,
                          uint32(at: start + 8) == uint32(at: start + 4) * blockAlign else { throw Failure.invalidWAV }
                }
                offset = start + declaredLength + declaredLength % 2
            }
        }
        guard foundAudio, offset == data.count else { throw Failure.invalidWAV }
        writeLength(data.count - 8, at: 4)
        return output
    }
}
