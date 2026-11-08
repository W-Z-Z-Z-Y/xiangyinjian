import SwiftUI
import Speech
import AVFoundation
import Network
import Combine

struct TranslationView: View {
    private enum Destination: Hashable { case settings, antiScam }
    private enum ScrollAnchor: Hashable { case scamWarning }
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var lang: LanguageManager
    @StateObject private var vm = TranslationViewModel()
    @State private var showResultFullScreen = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollViewReader { scrollProxy in
            page(scrollProxy: scrollProxy)
        }
    }

    private func page(scrollProxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: ElderlyMetrics.spacing) {
                    AppPageHeader(title: "乡音间", subtitle: lang.tr("design.translateSubtitle"), icon: "bubble.left.and.bubble.right")
                    TranslationDirectionToggleView(
                        preferredDialect: appState.preferredDialect,
                        isReverseMode: vm.isReverseMode,
                        onSelectDialect: { name in
                            vm.languageContextChanged()
                            Haptic.select()
                            appState.preferredDialect = name
                        }
                    ) {
                        Haptic.select()
                        withAnimation(.elderlyState) {
                            vm.isReverseMode.toggle()
                        }
                    }
                    TranslationInputCardView(
                        inputText: $vm.inputText,
                        isRecording: vm.isRecording,
                        showSpeechRetryHint: vm.showSpeechRetryHint,
                        speechStatusMessage: vm.speechStatusMessage,
                        onClear: {
                            vm.cancelSpeechInput()
                            vm.inputText = ""
                        },
                        onStartSpeech: { vm.beginHoldToTalk(dialect: appState.preferredDialect) },
                        onStopSpeech: { vm.endHoldToTalk() },
                        onRetrySpeech: {
                            vm.retrySpeech(dialect: appState.preferredDialect)
                        }
                    )
                    if !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        translateButton
                    }
                    if let warning = vm.scamWarning {
                        scamWarningCard(warning)
                            .id(ScrollAnchor.scamWarning)
                            .elderlyTransition(from: .top)
                    }
                    if let error = vm.inlineTranslationError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.captionElderly)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    QuickSceneCardView { scene in
                        vm.cancelSpeechInput()
                        vm.isReverseMode = true
                        vm.inputText = scene.text
                        vm.translate(dialect: appState.preferredDialect)
                    }
                    if !vm.result.isEmpty {
                        TranslationResultCardView(
                            resultText: vm.resultText,
                            resultDialect: vm.resultDialect,
                            isSpeaking: vm.isSpeaking,
                            onSpeak: { vm.speakResult() },
                            onCopy: {
                                UIPasteboard.general.string = vm.resultText
                                vm.alertMessage = lang.tr("translate.copied")
                                vm.showAlert = true
                            },
                            onShowFullScreen: { showResultFullScreen = true },
                            onSaveVoiceCard: { vm.saveVoiceCard() }
                        )
                        .elderlyTransition(from: .bottom)
                        if !vm.currentRecordingTags.isEmpty {
                            Label("记忆标签：" + vm.currentRecordingTags.joined(separator: "、"), systemImage: "tag")
                                .font(.captionElderly).foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    FamilyGreetingsPanelView { item in
                        vm.cancelSpeechInput()
                        vm.isReverseMode = true
                        vm.inputText = item.text
                        vm.translate(dialect: appState.preferredDialect)
                    }
                }
                .padding(ElderlyMetrics.cardPadding)
                .padding(.bottom, 84)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.scamWarning?.messageKey) { _, key in
                guard key != nil else { return }
                withAnimation(.elderlyState) {
                    scrollProxy.scrollTo(ScrollAnchor.scamWarning, anchor: .top)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .settings: SettingsView().toolbar(.visible, for: .navigationBar)
                case .antiScam: AntiScamView().toolbar(.visible, for: .navigationBar)
                }
            }
            // appState 通过 onAppear 注入 ViewModel（用户交互仅在 appear 后触发，安全）
            .onAppear {
                vm.appState = appState
                // 预热触觉引擎，去掉第一次点按钮时的震动延迟
                Haptic.prepare()
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceAssistantWillOpen)) { _ in
                vm.stopWork()
            }
            .onDisappear { vm.stopWork() }
            .onChange(of: appState.preferredDialect) { _, _ in vm.languageContextChanged() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { vm.stopWork() } }
            .onReceive(NotificationCenter.default.publisher(for: .voiceCommandTranslate)) { notification in
                if let text = notification.userInfo?["text"] as? String {
                    vm.cancelSpeechInput()
                    vm.inputText = text
                    vm.translate(dialect: appState.preferredDialect)
                }
            }
            .alert(lang.tr("common.alert"), isPresented: $vm.showAlert) {
                Button(lang.tr("translate.ok"), role: .cancel) {}
            } message: {
                Text(vm.alertMessage)
            }
            // 功能3：声音卡片保存成功提示
            .alert("", isPresented: $vm.showVoiceCardSaved) {
                Button(lang.tr("translate.ok"), role: .cancel) {}
            } message: {
                Text(lang.tr("voiceCard.saved"))
            }

            // 一键求助浮窗
            if !appState.familyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmergencyHelpButton(phone: appState.familyContactPhone)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .fullScreenCover(isPresented: $showResultFullScreen) {
            TranslationResultFullScreenView(
                resultText: vm.resultText,
                resultDialect: vm.resultDialect,
                isSpeaking: vm.isSpeaking,
                onClose: { showResultFullScreen = false },
                onSpeak: { vm.speakResult() }
            )
        }
    }

    // MARK: - 反诈提醒卡片
    private func scamWarningCard(_ warning: ScamWarning) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundColor(.statusWarning)
                Text(lang.tr("scam.title"))
                    .font(.title2Elderly)
                    .foregroundColor(.statusWarning)
                Spacer()
                Button {
                    withAnimation(.elderlyState) { vm.scamWarning = nil }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(lang.tr("scam.dismiss"))
            }
            Text(warning.message)
                .font(.bodyElderly)
                .foregroundColor(.textPrimary)
            if let tip = warning.tip {
                Text(tip)
                    .font(.captionElderly)
                    .foregroundColor(.textSecondary)
            }

            VStack(spacing: 10) {
                if warning.level == .high {
                    Button {
                        vm.callAntiScamHotline()
                    } label: {
                        Label(lang.tr("scam.call96110"), systemImage: "phone.fill")
                    }
                    .buttonStyle(ElderlyButtonStyle(background: .statusError))
                }

                if appState.familyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    NavigationLink(value: Destination.settings) {
                        Label(lang.tr("scam.setFamilyPhone"), systemImage: "person.crop.circle.badge.plus")
                            .font(.buttonElderly)
                            .foregroundColor(.accentElderly)
                            .frame(maxWidth: .infinity, minHeight: ElderlyMetrics.minTapTarget)
                            .elderlyCard()
                    }
                } else {
                    Button {
                        vm.alertFamily(phone: appState.familyContactPhone)
                    } label: {
                        Label(lang.tr("scam.alertFamily"), systemImage: "message.fill")
                    }
                    .buttonStyle(ElderlyButtonStyle(background: .accentSecondary))
                }
            }

            NavigationLink(value: Destination.antiScam) {
                Label(lang.tr("scam.viewGuide"), systemImage: "shield.lefthalf.filled")
                    .font(.buttonElderly)
                    .foregroundColor(.accentElderly)
            }
        }
        .padding(ElderlyMetrics.cardPadding)
        .elderlyCard()
        .overlay(
            RoundedRectangle(cornerRadius: ElderlyMetrics.cornerRadius)
                .stroke(warning.level == .high ? Color.statusError : Color.statusWarning, lineWidth: 2)
        )
    }

    // MARK: - 翻译按钮（功能1：方向感知）
    private var translateButton: some View {
        Button {
            vm.translate(dialect: appState.preferredDialect)
        } label: {
            if vm.isTranslating {
                HStack(spacing: 10) {
                    ProgressView().tint(.backgroundPrimary)
                    Text(lang.tr("translate.translating"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            } else {
                Text(vm.isReverseMode
                     ? String(format: lang.tr("translate.mandarinTo"), lang.dialectDisplayName(appState.preferredDialect))
                     : String(format: lang.tr("translate.toMandarin"), lang.dialectDisplayName(appState.preferredDialect)))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(ElderlyButtonStyle())
        .disabled(vm.isTranslating || vm.awaitingAppleFinal || vm.awaitingIFlytekFinal
                  || vm.isRecording
                  || vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel(vm.isTranslating ? lang.tr("translate.translatingHint") : lang.tr("translate.translate"))
        .accessibilityHint(vm.isReverseMode
            ? String(format: lang.tr("translate.mandarinTo"), lang.dialectDisplayName(appState.preferredDialect))
            : String(format: lang.tr("translate.toMandarin"), lang.dialectDisplayName(appState.preferredDialect)))
    }

}

// MARK: - ViewModel

@MainActor
final class TranslationViewModel: NSObject, ObservableObject {
    weak var appState: AppState?
    private let lang = LanguageManager.shared

    @Published var inputText: String = "" {
        didSet {
            if inputText != oldValue {
                invalidateTranslation()
                scamWarning = nil
            }
        }
    }
    @Published var result: String = ""
    @Published var resultDialect: String? = nil
    @Published var isRecording: Bool = false
    @Published var isTranslating: Bool = false
    @Published var speechStatusMessage: String? = nil
    @Published var showAlert: Bool = false
    @Published var alertMessage: String = ""
    @Published var scamWarning: ScamWarning? = nil
    @Published private(set) var inlineTranslationError: String?
    @Published var showSpeechRetryHint: Bool = false

    // 功能1：双向翻译模式（false=方言→普通话，true=普通话→方言）
    @Published var isReverseMode: Bool = false {
        didSet { if isReverseMode != oldValue { languageContextChanged() } }
    }

    // 功能3：声音卡片保存成功提示
    @Published var showVoiceCardSaved: Bool = false

    let speech = SpeechService.shared
    private let translator = TranslationManager()
    private var speechObserver: AnyCancellable?
    private var translationTask: Task<Void, Never>?
    private var translationGeneration = 0
    private struct CompletedTranslation {
        let source: String
        let text: String
        let sourceDialect: String
        let targetDialect: String
        let audioData: Data?
    }
    private var completedTranslation: CompletedTranslation?
    private var recordingDialect: String?

    // MARK: - 讯飞方言识别（按已配置的方言参数启用）
    private let iFlytekASR = IFlytekASRService()
    /// 本次录音走的是讯飞而非 Apple Speech
    private var usingIFlytek = false
    /// 讯飞末帧已发出，正在等最终结果回传
    @Published private(set) var awaitingIFlytekFinal = false
    /// 讯飞会话编号。每次发起递增，延时兜底任务据此判断自己是否已过期，
    /// 避免上一轮的检查误杀新一轮会话。
    private var iFlytekSessionID = 0
    private var iFlytekObservers: [AnyCancellable] = []

    /// 识别引擎诊断信息。直接显示在界面上，用于确认「到底走的哪个引擎」。
    ///
    /// 为什么不做成 NSLog：真机上调试区搜索往往看不到输出，而"讯飞静默回退
    /// 到 Apple"和"讯飞正常工作"在界面上完全一样，无法区分。放在界面上最直观。
    /// 发布前应移除或仅在 DEBUG 下显示。
    @Published var asrDiagnostic: String? = nil
    /// 本轮识别所用方言，供收尾时拼诊断信息
    private var dialectOfLastSession = ""

    private let appleParagraph = AppleParagraphRecognition()
    private var hasAudioTap = false
    private var ownsAudioSession = false
    private let audioEngine = AVAudioEngine()
    private let voiceRecordingResampler = PCMResampler()
    private let voiceRecordingBuffer = AudioRecordingBuffer()
    private var lastRecordedAudioData: Data?
    private var audioBeforeApple: Data?
    @Published var recordingTags: [String] = []
    var currentRecordingTags: [String] {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines) == lastRecordedText ? recordingTags : []
    }
    private var lastRecordedText: String?
    /// 识别代际：每次开始/停止递增。回调据此判断自己是否仍是当前会话，主动 cancel 等旧任务的回调会被忽略，避免把「用户停止」误报成「语音识别失败」
    @Published private(set) var awaitingAppleFinal = false
    private var wantsRecording = false
    private var startRequestID = 0
    private var recognitionGeneration = 0
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable: Bool = true
    /// 上一次已震动提醒过的诈骗规则，避免同一句反复翻译时重复震动骚扰用户
    private var announcedScamKey: String?
    /// 驱动波形刷新的定时器，仅录音期间存在
    private var waveformTimer: Timer?

    /// 结果是否正在朗读（驱动按钮图标）
    var isSpeaking: Bool { speech.isSpeaking(resultText) }

    /// 方言名称单独存储；正文中的括号、编号和引用均保留。
    var resultText: String { result }

    override init() {
        super.init()
        speechObserver = speech.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - 翻译（本地词库优先，未命中时直连云服务，支持双向）
    func translate(dialect: String) {
        guard !isRecording, !awaitingAppleFinal, !awaitingIFlytekFinal else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let input = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        invalidateTranslation()
        let generation = translationGeneration
        let sourceDialect = isReverseMode ? "普通话" : dialect
        let targetDialect = isReverseMode ? dialect : "普通话"
        let recording = input == lastRecordedText && recordingDialect == sourceDialect ? lastRecordedAudioData : nil
        let shouldAutoSpeak = showSpeechRetryHint

        // 命中诈骗关键词时立刻震一下，不必等结果回来——预警要抢在用户转账之前
        let detected = ScamDetector.detect(in: input)
        withAnimation(.elderlyState) { scamWarning = detected }
        if let detected, detected.messageKey != announcedScamKey {
            announcedScamKey = detected.messageKey
            Haptic.warning()
        } else if detected == nil {
            announcedScamKey = nil
        }

        let hasOfflineResult = sourceDialect == targetDialect || (sourceDialect == "普通话"
            ? LocalDictionary.lookup(input, dialect: targetDialect) != nil
            : LocalDictionary.reverseLookup(dialectText: input, from: sourceDialect) != nil)
        if !isNetworkAvailable, !hasOfflineResult {
            presentTranslationFailure(lang.tr("translate.noNetwork"))
            return
        }

        isTranslating = true
        translationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.translationGeneration == generation {
                    self.isTranslating = false
                    self.translationTask = nil
                }
            }
            do {
                let text = try await self.translator.translate(input, from: sourceDialect, to: targetDialect)
                try Task.checkCancellation()
                guard self.translationGeneration == generation else { return }
                self.finish(CompletedTranslation(source: input, text: text,
                                                sourceDialect: sourceDialect, targetDialect: targetDialect,
                                                audioData: recording), autoSpeak: shouldAutoSpeak)
            } catch {
                guard !Task.isCancelled, self.translationGeneration == generation else { return }
                let message = self.isNetworkAvailable ? self.localizedErrorMessage(error) : self.lang.tr("translate.noNetwork")
                self.presentTranslationFailure(message)
            }
        }
    }

    private func presentTranslationFailure(_ message: String) {
        if scamWarning != nil {
            // 保留反诈提示的可见性，翻译失败原因在卡片下方显示。
            inlineTranslationError = message
            return
        }
        alertMessage = message
        Haptic.error()
        showAlert = true
    }

    private func invalidateTranslation(clearResult: Bool = true) {
        translationGeneration += 1
        translationTask?.cancel()
        translationTask = nil
        isTranslating = false
        inlineTranslationError = nil
        if speech.isSpeaking(resultText) { speech.stop() }
        if clearResult {
            completedTranslation = nil
            result = ""
            resultDialect = nil
        }
    }

    func languageContextChanged() {
        cancelSpeechInput()
        invalidateTranslation()
    }

    func stopWork() {
        cancelSpeechInput()
        invalidateTranslation(clearResult: false)
    }

    /// 写入结果并存入历史
    private func finish(_ completed: CompletedTranslation, autoSpeak: Bool) {
        completedTranslation = completed
        // 结果卡片带上浮淡入出现，让「译文出来了」这件事有重量感
        withAnimation(.elderlyAppear) {
            result = completed.text
            resultDialect = completed.targetDialect
        }
        Haptic.success()
        appState?.addHistory(HistoryRecord(
            sourceText: completed.source,
            translatedText: completed.text,
            dialect: completed.sourceDialect == "普通话" ? completed.targetDialect : completed.sourceDialect
        ))
        // 语音闭环：翻译成功后自动朗读结果（可在设置里关掉）
        if autoSpeak, speech.autoSpeakTranslation,
           !VoiceCommandService.shared.isListening, !VoiceCommandService.shared.isPreparing, !VoiceCommandService.shared.isFinishing {
            speakResult()
        }
    }

    // MARK: - 朗读（保留方言名，选择系统或云端音色）
    func speakResult() {
        let dialect = resultDialect ?? appState?.preferredDialect ?? "普通话"
        speech.speak(resultText, dialect: dialect)
    }

    // MARK: - 错误消息本地化
    private func localizedErrorMessage(_ error: Error) -> String {
        if error is DemoCloudError || error is GatewayError {
            return error.localizedDescription
        }
        if let translationError = error as? TranslationError {
            switch translationError {
            case .notConfigured:
                return lang.tr("error.notConfigured")
            case .network(let msg):
                return String(format: lang.tr("error.network"), msg)
            case .api(let code, let msg):
                return String(format: lang.tr("error.api"), code, msg)
            case .decoding:
                return lang.tr("error.decoding")
            case .truncated:
                return lang.tr("error.truncated")
            case .untranslated:
                return lang.tr("error.untranslated")
            }
        }
        return lang.tr("error.translateFailed")
    }

    // MARK: - 功能3：声音卡片保存（增强版）
    func saveVoiceCard() {
        guard let completed = completedTranslation,
              completed.source == inputText.trimmingCharacters(in: .whitespacesAndNewlines),
              completed.text == result else { return }
        // 自动分类和标签
        let category = detectCategory(completed.source)
        let tags = MemoryTagger.localTags(completed.source + " " + completed.text)
        let cardID = UUID()
        var audioFileName: String?
        if let data = completed.audioData {
            guard let savedPath = AppFileStore.saveMedia(
                data,
                directory: "Media/VoiceCards",
                fileName: "\(cardID.uuidString).wav"
            ) else {
                showVoiceCardSaveError()
                return
            }
            audioFileName = savedPath
        }

        let card = VoiceCard(
            id: cardID,
            sourceText: completed.source,
            translatedText: completed.text,
            dialect: completed.sourceDialect,
            date: Date(),
            audioData: nil,
            audioFileName: audioFileName,
            category: category,
            tags: tags,
            translatedDialect: completed.targetDialect
        )
        var cards = loadVoiceCards()
        cards.insert(card, at: 0)
        guard AppFileStore.save(cards, fileName: "voice-cards.json", legacyKey: "voiceCards") else {
            AppFileStore.removeMedia(at: audioFileName)
            showVoiceCardSaveError()
            return
        }
        VoiceMemoryService.shared.enrich(card)
        Haptic.success()
        showVoiceCardSaved = true
    }

    private func showVoiceCardSaveError() {
        alertMessage = lang.current == .zh
            ? "声音卡片未能保存，请检查可用存储空间后重试。原文和译文已保留。"
            : "The voice card could not be saved. Check available storage and try again. Your text and translation are still here."
        Haptic.error()
        showAlert = true
    }

    func loadVoiceCards() -> [VoiceCard] {
        AppFileStore.load([VoiceCard].self,
                          fileName: "voice-cards.json",
                          legacyKey: "voiceCards") ?? []
    }

    // 自动分类
    private func detectCategory(_ text: String) -> String {
        if text.contains("爸") || text.contains("妈") || text.contains("孙") ||
           text.contains("儿") || text.contains("女") || text.contains("想你") {
            return "亲情"
        }
        if text.contains("春节") || text.contains("中秋") || text.contains("端午") ||
           text.contains("元宵") || text.contains("重阳") {
            return "节日"
        }
        if text.contains("从前") || text.contains("很久") || text.contains("那时候") ||
           text.contains("小时候") || text.contains("以前") {
            return "故事"
        }
        return "日常"
    }

    // 提取标签
    private func extractTags(_ source: String, translatedText: String) -> [String] {
        var tags: [String] = []

        // 问候类
        if source.contains("你好") || source.contains("早") || source.contains("晚上好") {
            tags.append("问候")
        }
        // 饮食类
        if source.contains("吃") || source.contains("饭") || source.contains("食") {
            tags.append("饮食")
        }
        // 健康类
        if source.contains("身体") || source.contains("健康") || source.contains("看病") {
            tags.append("健康")
        }
        // 童谣类
        if source.count > 20 && (source.contains("月亮") || source.contains("小") ||
                                  source.contains("儿歌")) {
            tags.append("童谣")
        }

        return tags
    }

    func callAntiScamHotline() {
        guard let url = URL(string: "tel://96110") else { return }
        UIApplication.shared.open(url)
    }

    func alertFamily(phone: String) {
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPhone.isEmpty else { return }
        let body = lang.tr("share.smsBody") + inputText
        var components = URLComponents()
        components.scheme = "sms"
        components.path = cleanPhone
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - 语音识别

    /// 该方言是否交给讯飞识别。
    ///
    /// 已映射且配置完整的方言交给讯飞，其余保持系统识别。
    private func shouldUseIFlytek(dialect: String) -> Bool {
        DialectASRPolicy.shouldUseIFlytek(for: dialect)
    }

    func beginHoldToTalk(dialect: String) {
        guard !wantsRecording, !awaitingIFlytekFinal, !awaitingAppleFinal else { return }
        invalidateTranslation()
        let sourceDialect = isReverseMode ? "普通话" : dialect
        recordingDialect = sourceDialect
        VoiceCommandService.shared.stopListening()
        SpeechService.shared.stop()
        VoiceRecordingPlayer.shared.stop()
        recordingTags = []
        audioBeforeApple = nil
        wantsRecording = true
        startRequestID += 1
        if shouldUseIFlytek(dialect: sourceDialect) {
            startIFlytekSpeech(dialect: sourceDialect)
        } else {
            inputText = ""
            result = ""
            resultDialect = nil
            startSpeech(locale: Dialects.locale(for: sourceDialect))
        }
    }

    func endHoldToTalk() {
        guard wantsRecording else { return }
        stopSpeech()
    }

    func cancelSpeechInput() {
        wantsRecording = false
        startRequestID += 1
        awaitingAppleFinal = false
        awaitingIFlytekFinal = false
        usingIFlytek = false
        iFlytekSessionID += 1
        iFlytekObservers = []
        iFlytekASR.cancel()
        stopSpeech(resetStatus: false)
        speechStatusMessage = nil
    }

    func retrySpeech(dialect: String) {
        cancelSpeechInput()
        inputText = ""
        result = ""
        resultDialect = nil
        showSpeechRetryHint = false
        speechStatusMessage = "请重新长按说话"
    }

    // MARK: - 讯飞识别路径

    private func startIFlytekSpeech(dialect: String) {
        lastRecordedAudioData = nil
        lastRecordedText = nil
        usingIFlytek = true
        awaitingIFlytekFinal = false
        iFlytekSessionID += 1
        let sessionID = iFlytekSessionID
        dialectOfLastSession = dialect
        // 每次开始录音都是一次全新的识别：清空上一次的文本与译文。
        // 不清的话新识别结果会接在旧文本后面，越说越长。
        inputText = ""
        result = ""
        resultDialect = nil
        showSpeechRetryHint = false
        speechStatusMessage = lang.tr("translate.recording")
        asrDiagnostic = "引擎：讯飞（\(dialect)）连接中…"

        // 先清空讯飞上一轮错误，再订阅 Published，避免旧错误误触发回退。
        iFlytekASR.start(dialect: dialect, existingText: "")

        // 订阅讯飞状态：文本回填、响度、失败降级
        iFlytekObservers = [
            iFlytekASR.$transcript.sink { [weak self] text in
                guard let self, self.usingIFlytek, self.iFlytekSessionID == sessionID else { return }
                if !text.isEmpty { self.inputText = text }
            },
            iFlytekASR.$isRecording.sink { [weak self] recording in
                guard let self, self.usingIFlytek, self.iFlytekSessionID == sessionID else { return }
                self.isRecording = recording
                if recording {
                    self.asrDiagnostic = "引擎：讯飞（\(dialect)）录音中"
                    Haptic.start()
                    self.startWaveformTimer()
                }
            },
            iFlytekASR.$errorMessage.sink { [weak self] message in
                guard let self, let message,
                      self.usingIFlytek, self.iFlytekSessionID == sessionID else { return }
                self.fallbackToAppleSpeech(dialect: dialect, reason: message)
            },
        ]

        // 兜底：讯飞未授权（错误码 11200）或握手失败时不会有 isRecording，
        // 界面会卡在「录音中」但实际什么都没发生。这里延时检查一次。
        //
        // 给足 4 秒：讯飞要先做签名握手再建连，1.5 秒可能还没连上，
        // 检查过早会把正常会话误判为失败。
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.usingIFlytek,
                  self.iFlytekSessionID == sessionID else { return }
            // 只要已经开始录音就不干预；isSessionFinished 说明正常收了尾
            guard !self.iFlytekASR.isRecording, !self.iFlytekASR.isSessionFinished else { return }
            let reason = self.iFlytekASR.debugDetail ?? "讯飞未能开始录音"
            self.fallbackToAppleSpeech(dialect: dialect, reason: reason)
        }
    }

    /// 开始采音前失败可回退；采音后中断则保留已有内容并提示补录。
    private func fallbackToAppleSpeech(dialect: String, reason: String) {
        guard usingIFlytek, wantsRecording else { return }
        let hasCapturedAudio = iFlytekASR.hasCapturedAudio
        // 优先展示底层细节（NSError domain/code / URLError），否则只看到
        // 「连接中断」这种笼统描述没法定位
        let detail = iFlytekASR.lastFailureDetail ?? iFlytekASR.debugDetail ?? reason
        asrDiagnostic = (hasCapturedAudio ? "⚠️ 讯飞识别中断 — " : "⚠️ 讯飞失败已降级 — ") + detail
            + (iFlytekASR.audioProbe.map { " — \($0)" } ?? "")
        let capturedRecording = iFlytekASR.snapshotRecording()
        usingIFlytek = false
        awaitingIFlytekFinal = false
        // 使编号失效，已经在途的延时检查 / 停止等待都不会再影响新会话
        iFlytekSessionID += 1
        iFlytekObservers = []
        iFlytekASR.cancel()
        cleanupSpeechResources()
        if hasCapturedAudio {
            isRecording = false
            wantsRecording = false
            stopWaveformTimer()
            lastRecordedAudioData = capturedRecording
            lastRecordedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            showSpeechRetryHint = !inputText.isEmpty
            showSpeechError(lang.tr("speech.incompleteParagraph"))
            return
        }
        audioBeforeApple = nil
        startSpeech(locale: Dialects.locale(for: dialect))
    }

    private func stopIFlytekSpeech() {
        // 末帧发出后最终结果会异步回传。必须等 isSessionFinished，
        // 不能等 isRecording——后者在用户点停止的瞬间就已是 false，
        // 那时最终结果还没回来，直接收尾会把最后一句话丢掉。
        awaitingIFlytekFinal = true
        speechStatusMessage = lang.tr("speech.finishingParagraph")
        let sessionID = iFlytekSessionID
        iFlytekASR.stop()

        Task { [weak self] in
            guard let self, self.usingIFlytek,
                  self.iFlytekSessionID == sessionID else { return }
            // 服务统一等待当前段、续段握手和尾音，避免固定 8 秒误判长句失败。
            let completed = await self.iFlytekASR.finish()
            guard self.usingIFlytek, self.iFlytekSessionID == sessionID else { return }
            guard completed else {
                self.lastRecordedAudioData = self.iFlytekASR.snapshotRecording()
                self.lastRecordedText = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                self.usingIFlytek = false
                self.awaitingIFlytekFinal = false
                self.iFlytekSessionID += 1
                self.iFlytekObservers = []
                self.iFlytekASR.cancel()
                self.showSpeechRetryHint = !self.inputText.isEmpty
                self.showSpeechError(self.lang.tr("speech.incompleteParagraph"))
                return
            }
            self.finishIFlytekSpeech()
        }
    }

    /// 讯飞识别收尾：清理资源，走与 Apple 路径相同的「停止后自动翻译」逻辑
    private func finishIFlytekSpeech() {
        // 量测行放在引擎名之后：正常时它证明音频真的流过去了，
        // 异常时它直接指出断在哪一环（没回调 / 没转出 / 没发帧）
        if let probe = iFlytekASR.audioProbe {
            asrDiagnostic = "引擎：讯飞（\(dialectOfLastSession)）识别完成 — \(probe)"
        } else {
            asrDiagnostic = "引擎：讯飞（\(dialectOfLastSession)）识别完成"
        }
        usingIFlytek = false
        awaitingIFlytekFinal = false
        iFlytekSessionID += 1
        iFlytekObservers = []
        stopWaveformTimer()
        isRecording = false
        wantsRecording = false
        Haptic.stop()

        lastRecordedAudioData = iFlytekASR.recordedAudioData
        lastRecordedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        recordingTags = MemoryTagger.localTags(inputText)

        if inputText.isEmpty {
            speechStatusMessage = nil
            showSpeechRetryHint = false
        } else {
            speechStatusMessage = lang.tr("translate.stopped")
            showSpeechRetryHint = true
            if let dialect = appState?.preferredDialect { translate(dialect: dialect) }
        }
    }

    private func startSpeech(locale: String) {
        let requestID = startRequestID
        speechStatusMessage = lang.tr("translate.requestingAuth")
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self, self.wantsRecording, self.startRequestID == requestID else { return }
                switch status {
                case .authorized:
                    self.requestMicrophonePermissionAndBegin(locale: locale, requestID: requestID)
                case .denied:
                    self.showSpeechError(self.lang.tr("speech.denied"))
                case .restricted:
                    self.showSpeechError(self.lang.tr("speech.restricted"))
                case .notDetermined:
                    self.showSpeechError(self.lang.tr("speech.notDetermined"))
                @unknown default:
                    self.showSpeechError(self.lang.tr("speech.unknown"))
                }
            }
        }
    }

    private func requestMicrophonePermissionAndBegin(locale: String, requestID: Int) {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            beginRecording(locale: locale)
        case .denied:
            showSpeechError(lang.tr("speech.micDenied"))
        case .undetermined:
            let micUndeterminedMessage = lang.tr("speech.micUndetermined")
            session.requestRecordPermission { granted in
                Task { @MainActor [weak self] in
                    guard let self, self.wantsRecording, self.startRequestID == requestID else { return }
                    if granted {
                        self.beginRecording(locale: locale)
                    } else {
                        self.showSpeechError(micUndeterminedMessage)
                    }
                }
            }
        @unknown default:
            showSpeechError(lang.tr("speech.micUnknown"))
        }
    }

    private func beginRecording(locale: String) {
        guard wantsRecording else { return }
        stopSpeech(resetStatus: false)
        voiceRecordingBuffer.reset()
        if let audioBeforeApple { voiceRecordingBuffer.appendRecording(audioBeforeApple) }
        audioBeforeApple = nil
        voiceRecordingResampler?.reset()
        lastRecordedAudioData = nil
        lastRecordedText = nil
        recognitionGeneration += 1
        let generation = recognitionGeneration

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            showSpeechError(lang.tr("speech.noRecognizer"))
            return
        }
        guard recognizer.isAvailable else {
            showSpeechError(lang.tr("speech.unavailable"))
            return
        }

        appleParagraph.start(recognizer: recognizer, prefix: inputText,
            onText: { [weak self] text in
                guard let self, self.recognitionGeneration == generation else { return }
                self.inputText = text
            }, onError: { [weak self] error in
                guard let self, self.recognitionGeneration == generation else { return }
                self.showSpeechError(String(format: self.lang.tr("speech.recognizeFailed"), error.localizedDescription))
                self.wantsRecording = false
                self.awaitingAppleFinal = false
                self.stopSpeech(resetStatus: false)
            })

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            ownsAudioSession = true
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let node = audioEngine.inputNode
            let format = node.outputFormat(forBus: 0)
            let voiceRecordingResampler = self.voiceRecordingResampler
            let voiceRecordingBuffer = self.voiceRecordingBuffer
            let relay = appleParagraph.relay
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                guard buffer.frameLength > 0 else { return }
                relay.append(buffer)
                // 顺带算一个响度喂给波形。这里在音频线程上，
                // pushRaw 内部加锁，不触碰任何 UI 状态。
                AudioLevelStore.shared.pushRaw(Double(buffer.normalizedLevel()))
                if let pcm = voiceRecordingResampler?.convert(buffer) {
                    voiceRecordingBuffer.append(pcm)
                }
            }
            hasAudioTap = true

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            speechStatusMessage = lang.tr("translate.recording")
            // 重震一下，明确告知「开始听了」
            Haptic.start()
            startWaveformTimer()
        } catch {
            showSpeechError(lang.tr("speech.recordFailed"))
            cleanupSpeechResources()
            return
        }

    }

    func stopSpeech() {
        wantsRecording = false
        startRequestID += 1
        if usingIFlytek, !iFlytekASR.isRecording, !awaitingIFlytekFinal {
            usingIFlytek = false
            iFlytekSessionID += 1
            iFlytekObservers = []
            iFlytekASR.cancel()
            speechStatusMessage = nil
            return
        }
        if awaitingIFlytekFinal { return }
        if usingIFlytek {
            stopIFlytekSpeech()
        } else if isRecording {
            awaitingAppleFinal = true
            audioEngine.stop()
            if hasAudioTap { audioEngine.inputNode.removeTap(onBus: 0); hasAudioTap = false }
            lastRecordedAudioData = voiceRecordingBuffer.wavData()
            stopWaveformTimer()
            isRecording = false
            speechStatusMessage = lang.tr("speech.finishingParagraph")
            let generation = recognitionGeneration
            Task { [weak self] in
                guard let self, self.recognitionGeneration == generation,
                      self.awaitingAppleFinal else { return }
                let complete = await self.appleParagraph.finish()
                guard self.recognitionGeneration == generation, self.awaitingAppleFinal else { return }
                if complete {
                    self.finishAppleSpeech()
                } else {
                    self.awaitingAppleFinal = false
                    self.lastRecordedText = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.stopSpeech(resetStatus: false)
                    self.showSpeechRetryHint = !self.inputText.isEmpty
                    self.showSpeechError(self.lang.tr("speech.incompleteParagraph"))
                }
            }
        } else if !awaitingAppleFinal {
            stopSpeech(resetStatus: false)
            speechStatusMessage = nil
        }
    }

    private func finishAppleSpeech() {
        guard awaitingAppleFinal else { return }
        awaitingAppleFinal = false
        lastRecordedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        recordingTags = MemoryTagger.localTags(inputText)
        stopSpeech(resetStatus: true)
    }

    private func stopSpeech(resetStatus: Bool) {
        let capturedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isRecording, !capturedText.isEmpty {
            lastRecordedAudioData = voiceRecordingBuffer.wavData()
            lastRecordedText = capturedText
        }
        recognitionGeneration += 1
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        appleParagraph.cancel()
        cleanupSpeechResources()
        if resetStatus {
            // 两下轻震表示「停止收音」，与开始的单下重震盲辨区分
            Haptic.stop()
            if inputText.isEmpty {
                speechStatusMessage = nil
                showSpeechRetryHint = false
            } else {
                speechStatusMessage = lang.tr("translate.stopped")
                showSpeechRetryHint = true
                // 语音闭环：停止录音后自动翻译
                if let dialect = appState?.preferredDialect { translate(dialect: dialect) }
            }
        }
    }

    private func cleanupSpeechResources() {
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
        stopWaveformTimer()
        appleParagraph.cancel()
        isRecording = false
        if ownsAudioSession {
            ownsAudioSession = false
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func showSpeechError(_ message: String) {
        speechStatusMessage = nil
        alertMessage = message
        Haptic.error()
        showAlert = true
    }

    // MARK: - 波形刷新
    //
    // 音频回调跑在非主线程、每 ~20ms 一次，直接把电平推给 SwiftUI 会过度重绘。
    // 这里改成主线程定时器以 25fps 去「取」电平，节奏可控且和屏幕刷新对得上。

    private func startWaveformTimer() {
        stopWaveformTimer()
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceWaveform() }
        }
        // .common 模式保证列表滚动时定时器不被暂停
        RunLoop.main.add(timer, forMode: .common)
        waveformTimer = timer
    }

    private func stopWaveformTimer() {
        waveformTimer?.invalidate()
        waveformTimer = nil
        AudioLevelStore.shared.reset()
    }

    private func advanceWaveform() {
        guard isRecording else { return }
        AudioLevelStore.shared.tick()
    }
}
