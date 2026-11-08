import Foundation
import Speech
import AVFoundation
import Combine

/// 统一方言听写服务。已配置且已映射的方言优先使用讯飞，
/// 普通话、未映射方言及讯飞失败时使用 Apple Speech。
@MainActor
final class DictationService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isFinishing = false
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?
    /// 本次听写同步采集的原声（WAV）。
    @Published private(set) var recordedAudioData: Data?

    /// 识别完整收尾后回调。讯飞路径会等最终结果到达后再触发。
    var onFinished: ((String) -> Void)?

    private let appleParagraph = AppleParagraphRecognition()
    private let audioEngine = AVAudioEngine()
    private var hasAudioTap = false
    private var ownsAudioSession = false

    private let iFlytek = IFlytekASRService()
    private var iFlytekObservers = Set<AnyCancellable>()
    private var usingIFlytek = false
    private var didCompleteCurrentSession = false
    private var activeDialect = "普通话"

    private let recordingResampler = PCMResampler()
    private let recordingBuffer = AudioRecordingBuffer()
    private var sessionPrefix = ""
    private let lang = LanguageManager.shared
    private var sessionGeneration = 0
    private var assistantObserver: AnyCancellable?

    override init() {
        super.init()
        assistantObserver = NotificationCenter.default.publisher(for: .voiceAssistantWillOpen)
            .sink { [weak self] _ in self?.cancel() }
    }

    func toggle(dialect: String, existingText: String) {
        guard !isFinishing else { return }
        if isRecording {
            stop()
        } else {
            start(dialect: dialect, existingText: existingText)
        }
    }

    func start(dialect: String, existingText: String) {
        SpeechService.shared.stop()
        cancel()
        sessionGeneration += 1
        errorMessage = nil
        recordedAudioData = nil
        didCompleteCurrentSession = false
        isRecording = false
        activeDialect = dialect
        sessionPrefix = existingText.isEmpty ? "" : existingText + " "
        transcript = sessionPrefix
        recordingBuffer.reset()
        recordingResampler?.reset()

        if DialectASRPolicy.shouldUseIFlytek(for: dialect) {
            startIFlytek(dialect: dialect, existingText: existingText)
        } else {
            startApple(locale: Dialects.locale(for: dialect))
        }
    }

    // MARK: - 讯飞方言识别

    private func startIFlytek(dialect: String, existingText: String) {
        teardownApple(resetRecording: false)
        usingIFlytek = true
        isRecording = false
        iFlytekObservers.removeAll()
        // 先让服务清空上一轮 errorMessage，再订阅 Published，
        // 避免旧错误在新会话订阅时立即触发误回退。
        iFlytek.start(dialect: dialect, existingText: existingText)

        iFlytek.$transcript
            .sink { [weak self] text in
                guard let self, self.usingIFlytek else { return }
                self.transcript = text
            }
            .store(in: &iFlytekObservers)

        iFlytek.$isRecording
            .sink { [weak self] recording in
                guard let self, self.usingIFlytek else { return }
                self.isRecording = recording
            }
            .store(in: &iFlytekObservers)

        iFlytek.$isSessionFinished
            .dropFirst()
            .sink { [weak self] finished in
                guard let self, self.usingIFlytek, finished else { return }
                self.recordedAudioData = self.iFlytek.recordedAudioData
                self.isRecording = false
                self.isFinishing = false
                self.usingIFlytek = false
                self.completeSession()
                self.iFlytekObservers.removeAll()
            }
            .store(in: &iFlytekObservers)

        iFlytek.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] _ in
                guard let self, self.usingIFlytek else { return }
                let preservedText = self.transcript
                let previousAudio = self.iFlytek.snapshotRecording()
                if self.isFinishing || self.iFlytek.hasCapturedAudio {
                    self.recordedAudioData = previousAudio
                    self.usingIFlytek = false
                    self.iFlytekObservers.removeAll()
                    self.iFlytek.cancel()
                    self.isFinishing = false
                    self.isRecording = false
                    self.errorMessage = self.lang.tr("speech.incompleteParagraph")
                    return
                }
                self.usingIFlytek = false
                self.iFlytek.cancel()
                self.iFlytekObservers.removeAll()
                self.isRecording = false
                self.sessionPrefix = preservedText.isEmpty ? "" : preservedText + " "
                self.transcript = self.sessionPrefix
                self.recordingBuffer.reset()
                if let previousAudio { self.recordingBuffer.appendRecording(previousAudio) }
                self.recordingResampler?.reset()
                self.startApple(locale: Dialects.locale(for: self.activeDialect))
            }
            .store(in: &iFlytekObservers)
    }

    // MARK: - Apple Speech

    private func startApple(locale: String) {
        let generation = sessionGeneration
        usingIFlytek = false
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self, self.sessionGeneration == generation else { return }
                switch status {
                case .authorized:
                    self.requestMicAndBegin(locale: locale, generation: generation)
                case .denied:
                    self.errorMessage = self.lang.tr("speech.denied")
                case .restricted:
                    self.errorMessage = self.lang.tr("speech.restricted")
                case .notDetermined:
                    self.errorMessage = self.lang.tr("speech.notDetermined")
                @unknown default:
                    self.errorMessage = self.lang.tr("speech.unknown")
                }
            }
        }
    }

    private func requestMicAndBegin(locale: String, generation: Int) {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            beginApple(locale: locale)
        case .denied:
            errorMessage = lang.tr("speech.micDenied")
        case .undetermined:
            session.requestRecordPermission { granted in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGeneration == generation else { return }
                    if granted { self.beginApple(locale: locale) }
                    else { self.errorMessage = self.lang.tr("speech.micUndetermined") }
                }
            }
        @unknown default:
            errorMessage = lang.tr("speech.micUnknown")
        }
    }

    private func beginApple(locale: String) {
        let generation = sessionGeneration
        teardownApple(resetRecording: false)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            errorMessage = lang.tr("speech.noRecognizer")
            return
        }
        guard recognizer.isAvailable else {
            errorMessage = lang.tr("speech.unavailable")
            return
        }
        appleParagraph.start(recognizer: recognizer, prefix: sessionPrefix,
            onText: { [weak self] text in
                guard let self, self.sessionGeneration == generation else { return }
                self.transcript = text
            }, onError: { [weak self] error in
                guard let self, self.sessionGeneration == generation else { return }
                self.errorMessage = String(format: self.lang.tr("speech.recognizeFailed"), error.localizedDescription)
                self.isFinishing = false
                self.recordedAudioData = self.recordingBuffer.wavData()
                self.teardownApple(resetRecording: true)
            })

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            ownsAudioSession = true

            let node = audioEngine.inputNode
            let format = node.outputFormat(forBus: 0)
            let recordingResampler = self.recordingResampler
            let recordingBuffer = self.recordingBuffer
            let relay = appleParagraph.relay
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                guard buffer.frameLength > 0 else { return }
                relay.append(buffer)
                AudioLevelStore.shared.pushRaw(Double(buffer.normalizedLevel()))
                if let pcm = recordingResampler?.convert(buffer) {
                    recordingBuffer.append(pcm)
                }
            }
            hasAudioTap = true

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            transcript = sessionPrefix
        } catch {
            errorMessage = lang.tr("speech.recordFailed")
            teardownApple(resetRecording: true)
            return
        }

    }

    func stop() {
        guard !isFinishing else { return }
        if usingIFlytek {
            isFinishing = true
            let generation = sessionGeneration
            iFlytek.stop()
            Task { [weak self] in
                guard let self, self.sessionGeneration == generation, self.isFinishing else { return }
                let complete = await self.iFlytek.finish()
                guard self.sessionGeneration == generation, self.isFinishing else { return }
                if complete { return }
                self.recordedAudioData = self.iFlytek.snapshotRecording()
                self.usingIFlytek = false
                self.iFlytekObservers.removeAll()
                self.iFlytek.cancel()
                self.isFinishing = false
                self.isRecording = false
                self.errorMessage = self.lang.tr("speech.incompleteParagraph")
            }
        } else {
            guard isRecording else { cancel(); completeSession(); return }
            let generation = sessionGeneration
            isFinishing = true
            audioEngine.stop()
            if hasAudioTap { audioEngine.inputNode.removeTap(onBus: 0); hasAudioTap = false }
            isRecording = false
            recordedAudioData = recordingBuffer.wavData()
            Task { [weak self] in
                guard let self, self.sessionGeneration == generation,
                      self.isFinishing else { return }
                let complete = await self.appleParagraph.finish()
                guard self.sessionGeneration == generation, self.isFinishing else { return }
                self.isFinishing = false
                self.teardownApple(resetRecording: true)
                if complete { self.completeSession() }
                else { self.errorMessage = self.lang.tr("speech.incompleteParagraph") }
            }
        }
    }

    /// 等完整尾句后再提交绘本等依赖最终文本的操作。
    func finish() async -> String? {
        stop()
        let generation = sessionGeneration
        while isFinishing {
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return nil }
            guard generation == sessionGeneration else { return nil }
        }
        guard errorMessage == nil else { return nil }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 页面离开时立即释放资源，不再等待远程最终结果。
    func cancel() {
        sessionGeneration += 1
        isFinishing = false
        if usingIFlytek {
            usingIFlytek = false
            iFlytek.cancel()
            iFlytekObservers.removeAll()
        }
        teardownApple(resetRecording: true)
    }

    private func completeSession() {
        guard !didCompleteCurrentSession else { return }
        didCompleteCurrentSession = true
        onFinished?(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func teardownApple(resetRecording: Bool) {
        if audioEngine.isRunning { audioEngine.stop() }
        appleParagraph.cancel()
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }

        if resetRecording {
            isRecording = false
            if ownsAudioSession {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .default)
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                ownsAudioSession = false
            }
        }
    }
}
