import Foundation
import UIKit
import Contacts
import Combine

// MARK: - 语音指令服务
@MainActor
final class VoiceCommandService: NSObject, ObservableObject {

    static let shared = VoiceCommandService()

    @Published var isListening = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isFinishing = false
    private var finalResultReady = false
    @Published var feedbackMessage: String?
    @Published var showHelp = false
    private var listeningGeneration = 0
    @Published var recognizedText = ""
    @Published var lastCommand: VoiceCommand?
    @Published var errorMessage: String?

    private let lang = LanguageManager.shared
    private let dictation = DictationService()
    private var dictationObservers = Set<AnyCancellable>()
    /// 驱动悬浮按钮环形波形刷新，仅监听期间存在
    private var waveformTimer: Timer?

    private override init() {
        super.init()
    }

    // MARK: - 启动语音监听
    func startListening(dialect: String = "普通话") {
        stopListening()
        listeningGeneration += 1
        let generation = listeningGeneration
        isPreparing = true
        recognizedText = ""
        lastCommand = nil
        feedbackMessage = nil
        errorMessage = nil
        SpeechService.shared.stop()
        VoiceRecordingPlayer.shared.stop()
        NotificationCenter.default.post(name: .voiceAssistantWillOpen, object: nil)

        // 和翻译、绘本使用同一套方言识别，等待完整结果后才允许执行。
        dictation.onFinished = { [weak self] text in
            guard let self, self.listeningGeneration == generation else { return }
            self.isPreparing = false
            self.isListening = false
            self.finalResultReady = true
            self.recognizedText = text
            self.lastCommand = self.parseCommand(text)
            if self.lastCommand == nil { self.errorMessage = self.lang.tr("voice.noCommand") }
            self.stopWaveformTimer()
        }
        // 先清空听写服务的旧错误，再订阅 Published 的当前值。
        dictation.start(dialect: dialect, existingText: "")
        dictation.$transcript.sink { [weak self] text in
            guard let self, self.listeningGeneration == generation else { return }
            self.recognizedText = text
        }.store(in: &dictationObservers)
        dictation.$isRecording.sink { [weak self] recording in
            guard let self, self.listeningGeneration == generation else { return }
            self.isListening = recording
            if recording {
                self.isPreparing = false
                self.startWaveformTimer()
            } else {
                self.stopWaveformTimer()
            }
        }.store(in: &dictationObservers)
        dictation.$errorMessage.compactMap { $0 }.sink { [weak self] message in
            guard let self, self.listeningGeneration == generation else { return }
            self.stopListening()
            self.errorMessage = message == self.lang.tr("speech.incompleteParagraph")
                ? self.lang.tr("voice.incompleteCommand") : message
        }.store(in: &dictationObservers)
    }

    /// 不把半句识别结果当作最终指令，尤其不能丢掉末尾的否定词。
    func finishListening() async -> VoiceCommand? {
        guard !isFinishing, !isPreparing, errorMessage == nil else { return nil }
        guard isListening else { return finalResultReady ? lastCommand : nil }
        let generation = listeningGeneration
        isFinishing = true
        isListening = false
        stopWaveformTimer()
        let text = await dictation.finish()
        guard generation == listeningGeneration else { return nil }
        guard !Task.isCancelled else { stopListening(); return nil }
        stopListening()
        guard let text else {
            errorMessage = lang.tr("voice.incompleteCommand")
            return nil
        }
        recognizedText = text
        finalResultReady = true
        lastCommand = parseCommand(text)
        if lastCommand == nil { errorMessage = lang.tr("voice.noCommand") }
        return lastCommand
    }

    // MARK: - 停止监听
    func stopListening() {
        listeningGeneration += 1
        dictationObservers.removeAll()
        dictation.onFinished = nil
        dictation.cancel()
        isPreparing = false
        isFinishing = false
        finalResultReady = false
        lastCommand = nil
        isListening = false
        stopWaveformTimer()
    }

    // MARK: - 波形刷新
    //
    // 与翻译页同样的做法：音频线程只写原始电平，主线程定时器以 25fps 去取，
    // 避免每 ~20ms 一次的音频回调直接触发 SwiftUI 重绘。

    private func startWaveformTimer() {
        stopWaveformTimer()
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                AudioLevelStore.shared.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        waveformTimer = timer
    }

    private func stopWaveformTimer() {
        waveformTimer?.invalidate()
        waveformTimer = nil
        AudioLevelStore.shared.reset()
    }

    // MARK: - 指令解析
    func parseCommand(_ text: String) -> VoiceCommand? { VoiceCommandParser.parse(text) }

    /// 在执行前重新解析完整识别结果，所有近义判断均在本地完成。
    func commandForExecution() async -> VoiceCommand? {
        guard !Task.isCancelled, !isPreparing, !isFinishing, errorMessage == nil else { return nil }
        if isListening { return await finishListening() }
        guard finalResultReady else { return nil }
        lastCommand = VoiceCommandParser.parse(recognizedText)
        return lastCommand
    }

    var shouldDismissAfterExecution: Bool {
        guard let command = lastCommand else { return false }
        switch command {
        case .navigate, .goHome, .translate: return true
        default: return false
        }
    }

    @discardableResult
    func executeCommand(_ command: VoiceCommand, appState: AppState) -> Bool {
        finalResultReady = false
        lastCommand = nil
        feedbackMessage = nil
        errorMessage = nil
        switch command {
        case .call(let name): handleCall(name: name, appState: appState)
        case .videoCall(let name): handleVideoCall(name: name)
        case .translate(let text):
            guard !text.isEmpty else { errorMessage = lang.tr("voice.translationRequired"); return false }
            handleTranslate(text: text, appState: appState)
        case .goHome:
            appState.selectedTab = .translate
        case .navigate(let destination):
            switch destination {
            case .settings: appState.selectedTab = .profile
            case .tools: appState.selectedTab = .tools
            case .memory: appState.selectedTab = .memory
            case .antiScam, .phrases, .dualDialect:
                appState.selectedTab = .tools
                appState.moreNavigationTarget = destination == .antiScam ? .antiScam : destination == .phrases ? .phrases : .dualDialect
            case .history, .voiceCards, .archive, .storybook:
                appState.selectedTab = .memory
                switch destination {
                case .history: appState.memoryNavigationTarget = .history
                case .voiceCards: appState.memoryNavigationTarget = .voiceCards
                case .archive: appState.memoryNavigationTarget = .archive
                default: appState.memoryNavigationTarget = .storybook
                }
            }
        case .fontSize(let delta):
            ThemeManager.shared.fontScale = min(1.6, max(1, ThemeManager.shared.fontScale + delta))
            feedbackMessage = lang.tr("voice.fontChanged")
        case .voiceGender(let male):
            SpeechService.shared.useMaleVoice = male
            feedbackMessage = SpeechService.shared.voiceAvailabilityMessage ?? lang.tr(male ? "voice.maleChanged" : "voice.femaleChanged")
        case .speechSpeed(let delta):
            SpeechService.shared.speechRate = min(0.6, max(0.2, SpeechService.shared.speechRate + delta))
            feedbackMessage = lang.tr("voice.speedChanged")
        case .stopPlayback:
            SpeechService.shared.stop()
            VoiceRecordingPlayer.shared.stop()
            feedbackMessage = lang.tr("voice.stopped")
        case .help:
            showHelp = true
            return false
        case .unknown:
            errorMessage = lang.tr("voice.notUnderstood")
            return false
        }
        Haptic.select()
        return true
    }

    private func handleCall(name: String, appState: AppState) {
        // 先尝试用通讯录按姓名查号
        if !name.isEmpty && !["家人", "家里人", "家里"].contains(name) {
            let store = CNContactStore()
            store.requestAccess(for: .contacts) { granted, _ in
                guard granted else {
                    Task { @MainActor in self.errorMessage = self.lang.tr("voice.contactsDenied") }
                    return
                }
                let predicate = CNContact.predicateForContacts(matchingName: name)
                let keys = [CNContactPhoneNumbersKey as CNKeyDescriptor]
                if let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys),
                   let phone = contacts.first?.phoneNumbers.first?.value.stringValue {
                    Task { @MainActor in self.openPhone(phone) }
                } else {
                    // 联系人未匹配时提示重试，不替换为其他号码。
                    Task { @MainActor in self.errorMessage = self.lang.tr("voice.contactNotFound") }
                }
            }
            return
        }
        dialFamilyFallback(appState: appState)
    }

    private func dialFamilyFallback(appState: AppState) {
        let phone = appState.familyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty else {
            errorMessage = lang.tr("voice.familyPhoneRequired")
            return
        }
        openPhone(phone)
    }

    private func openPhone(_ phone: String) {
        let number = phone.filter { $0.isNumber || $0 == "+" }
        guard number.contains(where: { $0.isNumber }), let url = URL(string: "tel://\(number)") else {
            errorMessage = lang.tr("phone.invalid")
            return
        }
        UIApplication.shared.open(url) { success in
            Task { @MainActor in
                if success { self.feedbackMessage = self.lang.tr("phone.opened") }
                else { self.errorMessage = self.lang.tr("phone.openFailed") }
            }
        }
    }

    private func handleVideoCall(name: String) {
        // 打开微信（实际项目需要微信 URL Scheme 或集成视频通话SDK）
        if let url = URL(string: "weixin://") {
            UIApplication.shared.open(url) { success in
                Task { @MainActor in
                    if success { self.feedbackMessage = self.lang.tr("voice.videoOpened") }
                    else { self.errorMessage = self.lang.tr("voice.videoFailed") }
                }
            }
        }
    }

    private func handleTranslate(text: String, appState: AppState) {
        // 导航到翻译页面并自动填充文本
        appState.selectedTab = .translate
        NotificationCenter.default.post(
            name: .voiceCommandTranslate,
            object: nil,
            userInfo: ["text": text]
        )
    }

}

// MARK: - 通知名称
extension Notification.Name {
    static let voiceAssistantWillOpen = Notification.Name("voiceAssistantWillOpen")
    static let voiceCommandTranslate = Notification.Name("voiceCommandTranslate")
}
