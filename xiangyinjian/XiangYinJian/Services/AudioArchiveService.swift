import Foundation
import AVFoundation
import Combine

/// 线程安全的 16kHz / 16bit / 单声道 PCM 录音缓冲区。
final class AudioRecordingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pcm = Data()

    func reset() {
        lock.lock()
        pcm = Data()
        lock.unlock()
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        pcm.append(data)
        lock.unlock()
    }

    /// 只接入本 App 生成的 16kHz/16bit/单声道 WAV，用于识别引擎回退时接续原声。
    func appendRecording(_ wav: Data) {
        guard wav.count > 44,
              String(data: wav.prefix(4), encoding: .ascii) == "RIFF",
              String(data: wav[36..<40], encoding: .ascii) == "data" else { return }
        append(Data(wav.dropFirst(44)))
    }

    func wavData() -> Data? {
        lock.lock()
        let snapshot = pcm
        lock.unlock()
        guard !snapshot.isEmpty else { return nil }
        return Self.makeWAV(from: snapshot)
    }

    private static func makeWAV(from pcm: Data) -> Data {
        let sampleRate: UInt32 = 16_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcm.count)

        var result = Data()
        result.append("RIFF".data(using: .ascii)!)
        result.appendLittleEndian(UInt32(36) + dataSize)
        result.append("WAVE".data(using: .ascii)!)
        result.append("fmt ".data(using: .ascii)!)
        result.appendLittleEndian(UInt32(16))
        result.appendLittleEndian(UInt16(1))
        result.appendLittleEndian(channels)
        result.appendLittleEndian(sampleRate)
        result.appendLittleEndian(byteRate)
        result.appendLittleEndian(blockAlign)
        result.appendLittleEndian(bitsPerSample)
        result.append("data".data(using: .ascii)!)
        result.appendLittleEndian(dataSize)
        result.append(pcm)
        return result
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

/// 播放声音卡片中保存的真实原声。
@MainActor
final class VoiceRecordingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = VoiceRecordingPlayer()

    @Published private(set) var playingPath: String?
    @Published var errorMessage: String?
    private var player: AVAudioPlayer?
    private var ownsAudioSession = false

    func toggle(relativePath: String) {
        errorMessage = nil
        if playingPath == relativePath {
            stop()
            return
        }
        stop()
        SpeechService.shared.stop()
        guard let url = AppFileStore.mediaURL(for: relativePath),
              FileManager.default.fileExists(atPath: url.path) else {
            reportMissingAudio()
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            ownsAudioSession = true
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            guard player.prepareToPlay(), player.play() else {
                reportPlaybackFailure()
                return
            }
            self.player = player
            playingPath = relativePath
        } catch {
            reportPlaybackFailure()
        }
    }

    func reportMissingAudio() {
        stop()
        errorMessage = LanguageManager.shared.current == .zh
            ? "录音文件不存在，无法播放原声。原文仍保留；修复版丢失时可重新修复。"
            : "The recording is missing. Your text is retained. A missing repaired recording can be generated again."
    }

    private func reportPlaybackFailure() {
        stop()
        errorMessage = LanguageManager.shared.current == .zh
            ? "录音播放失败，请检查音频输出后重试。文件可能已损坏。"
            : "The recording could not be played. Check your audio output and retry. The file may be damaged."
    }

    func stop() {
        player?.stop()
        player = nil
        playingPath = nil
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            if flag { self.stop() } else { self.reportPlaybackFailure() }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.reportPlaybackFailure()
        }
    }
}

enum DialectASRPolicy {
    static func shouldUseIFlytek(for dialect: String) -> Bool {
        dialect != "普通话" && IFlytekDialectConfiguration.supports(dialect) && AppKeys.iFlytekConfigured
    }
}
