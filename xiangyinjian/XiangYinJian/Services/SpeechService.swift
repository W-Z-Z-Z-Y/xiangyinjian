import Foundation
import AVFoundation
import Combine

@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = SpeechService()
    @Published private(set) var speakingText: String?
    @Published private(set) var pausedText: String?
    @Published private(set) var voiceAvailabilityMessage: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var cloudDialectEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cloudDialectEnabled, forKey: "cloudDialectEnabled")
            stop()
        }
    }
    @Published var speechRate: Float {
        didSet { UserDefaults.standard.set(Double(speechRate), forKey: "speechRate") }
    }
    @Published var useMaleVoice: Bool {
        didSet {
            UserDefaults.standard.set(useMaleVoice, forKey: "useMaleVoice")
            stop()
            _ = preferredVoice(for: "zh-CN")
        }
    }
    @Published var autoSpeakTranslation: Bool {
        didSet { UserDefaults.standard.set(autoSpeakTranslation, forKey: "autoSpeakTranslation") }
    }
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var cloudPlayer: AVAudioPlayer?
    private var synthesisTask: Task<Void, Never>?
    private var preparedAudioTask: Task<Data, Error>?
    private var playbackGeneration = 0
    private var pendingCloudChunks: [String] = []
    private var cloudRequest: CloudSpeechRequest?
    private var ownsAudioSession = false
    private var interruptionObserver: AnyCancellable?

    private struct CloudSpeechRequest {
        let dialect: String
        let gender: String
        let rate: Float
    }

    override init() {
        speechRate = Float(UserDefaults.standard.object(forKey: "speechRate") as? Double ?? 0.45)
        useMaleVoice = UserDefaults.standard.bool(forKey: "useMaleVoice")
        autoSpeakTranslation = UserDefaults.standard.object(forKey: "autoSpeakTranslation") as? Bool ?? true
        cloudDialectEnabled = UserDefaults.standard.object(forKey: "cloudDialectEnabled") as? Bool ?? true
        super.init()
        synthesizer.delegate = self
        interruptionObserver = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in self?.stop() }
            }
    }

    func speak(_ text: String, language: String = "zh-CN", rate: Float? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if isSpeaking(text) { stop(); return }
        stop()
        errorMessage = nil
        voiceAvailabilityMessage = nil
        VoiceRecordingPlayer.shared.stop()
        guard activateAudioSession() else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice(for: language)
        utterance.rate = rate ?? speechRate
        activeUtterance = utterance
        speakingText = text
        synthesizer.speak(utterance)
    }

    /// 方言名不能先折叠成 zh-CN，否则无法区分四川话与普通话音色。
    func speak(_ text: String, dialect: String, rate: Float? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if isSpeaking(text) { stop(); return }
        let dialect = dialect == "闽南话" ? "闽南语" : dialect
        let cloudSupported = ["四川话", "闽南语", "粤语", "东北话"].contains(dialect)
        if cloudSupported && cloudDialectEnabled {
            stop()
            errorMessage = nil
            voiceAvailabilityMessage = nil
            guard CloudGateway.shared.speechConfigured(for: dialect) else {
                errorMessage = localized(
                    "尚未配置方言朗读，请按项目配置指南配置云服务；也可关闭方言专用音色，使用系统音色。",
                    "Configure dialect speech using the project setup guide, or turn off dialect voices to use a system voice."
                )
                return
            }
            VoiceRecordingPlayer.shared.stop()
            if dialect == "闽南语" && !useMaleVoice {
                voiceAvailabilityMessage = localized(
                    "闽南语目前使用 Roy 男声，暂不支持女声切换。",
                    "Hokkien currently uses the Roy male voice; a female voice is not available."
                )
            } else if dialect == "东北话" && !useMaleVoice {
                voiceAvailabilityMessage = localized(
                    "东北话目前使用子阳男声，暂不支持女声切换。",
                    "Northeastern speech currently uses the Ziyang male voice; a female voice is not available."
                )
            }
            cloudRequest = CloudSpeechRequest(dialect: dialect, gender: useMaleVoice ? "male" : "female", rate: rate ?? speechRate)
            // 缩短首次等待，播放当前段时只预取下一段，空白段不发云请求。
            pendingCloudChunks = TranslationParagraph.chunks(text, limit: 180)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            speakingText = text
            playNextCloudChunk()
            return
        }

        speak(text, language: Dialects.locale(for: dialect), rate: rate)
        if !["普通话", "粤语"].contains(dialect), speakingText != nil {
            voiceAvailabilityMessage = localized(
                "当前使用系统中文音色，不保留\(dialect)口音。可播放保存的原声录音。",
                "Using a system Chinese voice without a \(LanguageManager.shared.dialectDisplayName(dialect)) accent. Play a saved original recording to hear the authentic voice."
            )
        }
    }

    private func playNextCloudChunk() {
        prepareNextCloudChunk()
        guard let request = cloudRequest, let audioTask = preparedAudioTask else {
            stop()
            return
        }
        let generation = playbackGeneration
        isLoading = true
        synthesisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await audioTask.value
                try Task.checkCancellation()
                guard generation == self.playbackGeneration else { return }
                self.preparedAudioTask = nil
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.enableRate = true
                player.rate = min(2, max(0.5, request.rate / 0.45))
                guard self.activateAudioSession() else {
                    self.stop()
                    return
                }
                self.cloudPlayer = player
                guard player.prepareToPlay(), player.play() else {
                    self.reportPlaybackFailure()
                    return
                }
                self.isLoading = false
                self.synthesisTask = nil
                self.prepareNextCloudChunk()
            } catch {
                guard generation == self.playbackGeneration, !Task.isCancelled else { return }
                self.stop()
                self.errorMessage = self.localized("方言朗读失败：", "Dialect speech failed: ") + error.localizedDescription
            }
        }
    }

    private func prepareNextCloudChunk() {
        guard preparedAudioTask == nil, let request = cloudRequest,
              !pendingCloudChunks.isEmpty else { return }
        let chunk = pendingCloudChunks.removeFirst()
        preparedAudioTask = Task {
            try Task.checkCancellation()
            return try await CloudGateway.shared.synthesize(text: chunk, dialect: request.dialect, gender: request.gender)
        }
    }

    private func activateAudioSession() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            ownsAudioSession = true
            return true
        } catch {
            errorMessage = localized("无法播放声音，请检查音频输出后重试。", "Audio could not be played. Check your audio output and retry.")
            return false
        }
    }

    private func localized(_ chinese: String, _ english: String) -> String {
        LanguageManager.shared.current == .zh ? chinese : english
    }

    private func reportPlaybackFailure() {
        stop()
        errorMessage = localized("方言音频无法播放，请重试。", "The dialect audio could not be played. Please retry.")
    }

    /// 防诈朗读：播放 → 暂停 → 从头播放。
    func toggleRestartingPlayback(_ text: String, language: String = "zh-CN") {
        if isSpeaking(text) {
            if cloudPlayer != nil {
                cloudPlayer?.pause()
                pausedText = text
                speakingText = nil
            } else if synthesizer.pauseSpeaking(at: .immediate) {
                pausedText = text
                speakingText = nil
            } else { stop() }
        } else {
            // speak 会清除暂停的旧任务，不使用 continueSpeaking。
            speak(text, language: language)
        }
    }

    func stop() {
        playbackGeneration += 1
        synthesisTask?.cancel()
        synthesisTask = nil
        preparedAudioTask?.cancel()
        preparedAudioTask = nil
        cloudRequest = nil
        pendingCloudChunks = []
        cloudPlayer?.delegate = nil
        cloudPlayer?.stop()
        cloudPlayer = nil
        isLoading = false
        activeUtterance = nil
        speakingText = nil
        pausedText = nil
        synthesizer.stopSpeaking(at: .immediate)
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
    }
    func isSpeaking(_ text: String) -> Bool { speakingText == text }
    func isPaused(_ text: String) -> Bool { pausedText == text }

    private func preferredVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let gender: AVSpeechSynthesisVoiceGender = useMaleVoice ? .male : .female
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.caseInsensitiveCompare(language) == .orderedSame && $0.gender == gender }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.identifier < $1.identifier
            }
        if let voice = voices.first {
            voiceAvailabilityMessage = nil
            return voice
        }
        voiceAvailabilityMessage = useMaleVoice
            ? LanguageManager.shared.tr("speech.maleUnavailable")
            : LanguageManager.shared.tr("speech.femaleUnavailable")
        return AVSpeechSynthesisVoice(language: language)
    }

    private func finish(_ utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }
        stop()
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish(utterance) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish(utterance) }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.cloudPlayer === player else { return }
            self.cloudPlayer = nil
            if flag { self.playNextCloudChunk() } else { self.reportPlaybackFailure() }
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.cloudPlayer === player else { return }
            self.reportPlaybackFailure()
        }
    }
}
