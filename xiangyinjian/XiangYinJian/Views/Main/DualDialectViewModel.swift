import Foundation
import Combine

// MARK: - ViewModel
@MainActor
final class DualDialectViewModel: ObservableObject {

    enum Side: Hashable { case a, b }

    struct SideState {
        var dialect: String
        var inputText: String = ""
        var translation: String = ""
        var translationDialect: String?
        var errorMessage: String?
        var isListening: Bool = false
        var isFinishing: Bool = false
        var isTranslating: Bool = false
    }

    @Published var sideA = SideState(dialect: "普通话")
    @Published var sideB = SideState(dialect: "粤语")

    private let translationService = TranslationManager()
    private let speechService = SpeechService.shared
    private var dictationA: DictationService? = nil
    private var dictationB: DictationService? = nil
    private var dictationObservers: [Side: Set<AnyCancellable>] = [:]
    private var translationTasks: [Side: Task<Void, Never>] = [:]
    private var translationGenerations: [Side: Int] = [:]
    private var speechObserver: AnyCancellable?

    init() {
        speechObserver = speechService.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    // MARK: - 方言设置
    func setDialect(_ dialect: String, for side: Side) {
        guard (side == .a ? sideA.dialect : sideB.dialect) != dialect else { return }
        stopWork()
        invalidateTranslation(for: .a)
        invalidateTranslation(for: .b)
        switch side {
        case .a: sideA.dialect = dialect
        case .b: sideB.dialect = dialect
        }
    }

    func setInput(_ text: String, for side: Side) {
        guard (side == .a ? sideA.inputText : sideB.inputText) != text else { return }
        cancelListening(for: side)
        invalidateTranslation(for: side)
        switch side {
        case .a: sideA.inputText = text
        case .b: sideB.inputText = text
        }
    }

    // MARK: - 语音识别
    func toggleListening(for side: Side) {
        guard !(side == .a ? sideA.isFinishing : sideB.isFinishing) else { return }
        switch side {
        case .a:
            if sideA.isListening {
                stopListening(for: .a)
            } else {
                startListening(for: .a)
            }
        case .b:
            if sideB.isListening {
                stopListening(for: .b)
            } else {
                startListening(for: .b)
            }
        }
    }

    private func startListening(for side: Side) {
        // 停止另一侧的识别，防止冲突
        let otherSide: Side = side == .a ? .b : .a
        cancelListening(for: otherSide)
        invalidateTranslation(for: otherSide, clearResult: false)
        cancelListening(for: side)
        invalidateTranslation(for: side)
        speechService.stop()
        VoiceRecordingPlayer.shared.stop()

        let dialect = side == .a ? sideA.dialect : sideB.dialect
        let dictation = DictationService()
        var observers = Set<AnyCancellable>()
        if side == .a { dictationA = dictation; sideA.inputText = ""; sideA.isListening = true }
        else { dictationB = dictation; sideB.inputText = ""; sideB.isListening = true }

        dictation.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self, weak dictation] text in
                guard let self, let dictation, !text.isEmpty,
                      (side == .a ? self.dictationA : self.dictationB) === dictation else { return }
                switch side {
                case .a:
                    self.sideA.inputText = text
                case .b:
                    self.sideB.inputText = text
                }
            }
            .store(in: &observers)

        dictation.$errorMessage
            .compactMap { $0 }
            .sink { [weak self, weak dictation] message in
                guard let self, let dictation,
                      (side == .a ? self.dictationA : self.dictationB) === dictation else { return }
                switch side {
                case .a:
                    self.sideA.isListening = false
                    self.sideA.isFinishing = false
                    self.sideA.errorMessage = message
                    if self.dictationA === dictation { self.dictationA = nil }
                case .b:
                    self.sideB.isListening = false
                    self.sideB.isFinishing = false
                    self.sideB.errorMessage = message
                    if self.dictationB === dictation { self.dictationB = nil }
                }
                self.dictationObservers[side] = nil
            }
            .store(in: &observers)

        dictation.onFinished = { [weak self, weak dictation] text in
            guard let self, let dictation,
                  (side == .a ? self.dictationA : self.dictationB) === dictation else { return }
            switch side {
            case .a:
                self.sideA.inputText = text
                self.sideA.isListening = false
                self.sideA.isFinishing = false
                if self.dictationA === dictation { self.dictationA = nil }
            case .b:
                self.sideB.inputText = text
                self.sideB.isListening = false
                self.sideB.isFinishing = false
                if self.dictationB === dictation { self.dictationB = nil }
            }
            self.dictationObservers[side] = nil
            self.translate(for: side)
        }

        dictationObservers[side] = observers
        dictation.start(dialect: dialect, existingText: "")
    }

    private func stopListening(for side: Side) {
        switch side {
        case .a:
            sideA.isFinishing = true
            dictationA?.stop()
            sideA.isListening = false
        case .b:
            sideB.isFinishing = true
            dictationB?.stop()
            sideB.isListening = false
        }
    }

    private func cancelListening(for side: Side) {
        switch side {
        case .a:
            dictationA?.onFinished = nil
            dictationA?.cancel()
            dictationA = nil
            sideA.isListening = false
            sideA.isFinishing = false
        case .b:
            dictationB?.onFinished = nil
            dictationB?.cancel()
            dictationB = nil
            sideB.isListening = false
            sideB.isFinishing = false
        }
        dictationObservers[side] = nil
    }

    func cancelAllListening() {
        cancelListening(for: .a)
        cancelListening(for: .b)
    }

    func stopWork() {
        cancelAllListening()
        invalidateTranslation(for: .a, clearResult: false)
        invalidateTranslation(for: .b, clearResult: false)
    }

    private func invalidateTranslation(for side: Side, clearResult: Bool = true) {
        translationGenerations[side, default: 0] += 1
        translationTasks[side]?.cancel()
        translationTasks[side] = nil
        let state = side == .a ? sideA : sideB
        if speechService.isSpeaking(state.translation) { speechService.stop() }
        switch side {
        case .a:
            sideA.isTranslating = false
            if clearResult { sideA.translation = ""; sideA.translationDialect = nil; sideA.errorMessage = nil }
        case .b:
            sideB.isTranslating = false
            if clearResult { sideB.translation = ""; sideB.translationDialect = nil; sideB.errorMessage = nil }
        }
    }

    // MARK: - 翻译
    func translate(for side: Side) {
        let source = side == .a ? sideA : sideB
        let targetDialect = side == .a ? sideB.dialect : sideA.dialect
        let sourceDialect = source.dialect
        let text = source.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !source.isListening, !source.isFinishing else { return }
        invalidateTranslation(for: side)
        let generation = translationGenerations[side, default: 0]

        switch side {
        case .a: sideA.isTranslating = true
        case .b: sideB.isTranslating = true
        }

        translationTasks[side] = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.translationGenerations[side] == generation {
                    switch side {
                    case .a: self.sideA.isTranslating = false
                    case .b: self.sideB.isTranslating = false
                    }
                    self.translationTasks[side] = nil
                }
            }
            do {
                let result = try await self.translationService.translate(text, from: sourceDialect, to: targetDialect)
                try Task.checkCancellation()
                guard self.translationGenerations[side] == generation else { return }
                switch side {
                case .a:
                    self.sideA.translation = result
                    self.sideA.translationDialect = targetDialect
                case .b:
                    self.sideB.translation = result
                    self.sideB.translationDialect = targetDialect
                }
                if self.speechService.autoSpeakTranslation,
                   !self.sideA.isListening, !self.sideB.isListening,
                   !self.sideA.isFinishing, !self.sideB.isFinishing,
                   !VoiceCommandService.shared.isListening,
                   !VoiceCommandService.shared.isPreparing, !VoiceCommandService.shared.isFinishing {
                    self.speakTranslation(for: side)
                }
            } catch {
                guard !Task.isCancelled, self.translationGenerations[side] == generation else { return }
                let message = LanguageManager.shared.current == .zh
                    ? "翻译失败，请检查网络和服务配置后重试。"
                    : "Translation failed. Check your connection and service settings, then try again."
                switch side {
                case .a: self.sideA.errorMessage = message
                case .b: self.sideB.errorMessage = message
                }
            }
        }
    }

    // MARK: - 朗读
    func speakTranslation(for side: Side) {
        let state = side == .a ? sideA : sideB
        guard !state.translation.isEmpty, let targetDialect = state.translationDialect,
              !sideA.isListening, !sideB.isListening, !sideA.isFinishing, !sideB.isFinishing else { return }

        if speechService.isSpeaking(state.translation) {
            speechService.stop()
        } else {
            speechService.speak(state.translation, dialect: targetDialect)
        }
    }

    func isSpeaking(_ side: Side) -> Bool {
        let state = side == .a ? sideA : sideB
        return speechService.isSpeaking(state.translation)
    }
}

