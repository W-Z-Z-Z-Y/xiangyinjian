import Foundation
import AVFoundation
import Combine

/// 讯飞方言语音识别（流式）。
///
/// 按用户选中的方言，把音频经 WebSocket 推给已开通的讯飞语音听写引擎。
/// 方言参数统一由 IFlytekDialectConfiguration 提供；未知参数不猜用其他引擎。
///
/// 协议要点（详见 IFlytekAuth 注释）：
/// - 首帧带 `common.app_id` + `business`，之后每帧只发 `data`
/// - `data.status`：0=首帧，1=中间帧，2=末帧
/// - 音频 16k / 16bit / 单声道，base64 后单帧不超过 13000 字节，
///   官方建议 1280 字节（40ms）一帧
/// - 单次会话最长 60 秒，静默超 10 秒服务端会断连
@MainActor
final class IFlytekASRService: NSObject, ObservableObject {

    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    /// 本次会话已结束（收到末帧结果，或出错收尾）。
    ///
    /// 与 `isRecording` 的区别：`isRecording` 在用户点「停止」的瞬间就置 false，
    /// 但最终识别结果要几百毫秒后才回传。调用方需等 `isSessionFinished` 才能
    /// 取走完整文本，否则会丢掉最后一次结果。
    @Published private(set) var isSessionFinished = false
    @Published var errorMessage: String?
    /// 原始错误详情（错误码 + 讯飞原文）。排查时比 errorMessage 有用得多，
    /// 界面可折叠显示或仅在 DEBUG 下打印。
    @Published var debugDetail: String?
    /// 最近一次连接失败的原始描述，供上层在界面展示。
    @Published private(set) var lastFailureDetail: String?

    /// 音频链路量测（临时诊断）：把「采样率 / 回调次数 / 送出的字节数」
    /// 摊开给界面看。
    ///
    /// 为什么需要：`isRecording == true` 只证明 `audioEngine.start()` 没抛错，
    /// 采集到静音时它照样为真、界面照样打 ✓，但一个字节都不会送到服务端。
    /// 这组数字能把「麦克风没采到」「重采样失败」「发送被丢」三件事分开。
    @Published private(set) var audioProbe: String?
    /// 本次识别同步采集的真实原声（WAV），供声音卡片保存。
    @Published private(set) var recordedAudioData: Data?

    private var connectionTask: Task<Void, Never>?
    private var sessionAppID = ""
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private let audioEngine = AVAudioEngine()
    private let resampler = PCMResampler()
    private let recordingBuffer = AudioRecordingBuffer()
    private let capturedAudio = CapturedAudioQueue()
    private var captureGeneration = 0
    private var captureWanted = false
    private var endingSegment = false
    private var nextSegmentAudio = Data()
    private var sentBytes = 0
    private var quietBytes = 0
    private var segmentResults = IATTranscriptAccumulator()
    private var nextResultSequence = 0
    private var hasAudioTap = false
    private var ownsAudioSession = false

    /// 握手是否完成。发送前必须为 true——在握手完成前调用 send 会失败，
    /// 而失败信息（"音频发送失败"）会掩盖真正的握手错误。
    private var handshakeCompleted = false
    /// 握手完成前攒下的待发帧，握手成功后按序补发
    private var queuedFrames: [String] = []
    private var handshakeTimer: Timer?
    private var finalResultTimer: Timer?
    /// 分段不会改变此编号；取消或重新录音会使旧 finish 等待失效。
    private var paragraphGeneration = 0

    /// 讯飞要求 40ms 一帧；16kHz × 16bit × 单声道 ⇒ 16000 × 0.04 × 2 = 1280 字节
    private static let bytesPerFrame = 1280

    /// 攒够一帧再发，避免高频小包
    private var pendingAudio = Data()
    private var isFirstFrame = true
    /// 音频链路量测（由音频线程写、主线程读，加锁）
    private let probe = AudioProbe.shared
    /// 会话代际：停止后旧回调据此自我忽略，避免把「用户主动停止」报成识别失败
    private var generation = 0
    /// 本次会话已识别的文字（动态修正模式下会被整体替换）
    private var accumulated = ""
    /// 进入会话前已存在的文字
    private var sessionPrefix = ""
    private var businessParameters: [String: Any] = [:]

    private let lang = LanguageManager.shared

    // MARK: - 对外接口

    var isConfigured: Bool { AppKeys.iFlytekConfigured }
    var hasCapturedAudio: Bool { (recordingBuffer.wavData()?.count ?? 0) > 44 }

    /// 切换录音状态：未录音则开始，正在录音则停止并等待末帧结果。
    func toggle(dialect: String, existingText: String) {
        if isRecording {
            stop()
        } else {
            start(dialect: dialect, existingText: existingText)
        }
    }

    /// 会话开始 / 结束都要清空量测，否则下一次会话会读到上一次的累计值
    func start(dialect: String, existingText: String) {
        lastFailureDetail = nil
        debugDetail = nil
        guard isConfigured else {
            errorMessage = lang.current == .en ? "This version is missing its dialect recognition configuration. Update the app and retry." : "当前版本的方言识别配置缺失，请更新应用后重试。"
            return
        }
        guard let parameters = IFlytekDialectConfiguration.businessParameters(for: dialect) else {
            errorMessage = lang.current == .en ? "This dialect has no configured iFlytek recognition parameters." : "此方言尚未配置对应的讯飞识别参数。"
            return
        }
        cancel()
        businessParameters = parameters
        captureWanted = true
        captureGeneration += 1
        endingSegment = false
        nextSegmentAudio = Data()
        sentBytes = 0
        quietBytes = 0
        segmentResults = IATTranscriptAccumulator()
        nextResultSequence = 0
        _ = capturedAudio.drain()
        errorMessage = nil
        audioProbe = nil
        isSessionFinished = false
        generation += 1
        accumulated = ""
        sessionPrefix = existingText.isEmpty ? "" : existingText + " "
        transcript = sessionPrefix
        pendingAudio = Data()
        recordingBuffer.reset()
        recordedAudioData = nil
        isFirstFrame = true
        resampler?.reset()

        requestMicThenConnect()
    }

    /// 停止录音并发送末帧。识别结果会稍后异步返回。
    func stop() {
        guard !isSessionFinished else { return }
        captureWanted = false
        stopAudioCapture()
        let tail = capturedAudio.drain()
        if connectionTask != nil && socket == nil {
            // 续段取票时麦克风已经采到声音，保留连接以发完尾句。
            // 首次取票尚未采音时则可立即取消。
            nextSegmentAudio.append(tail)
            if nextSegmentAudio.isEmpty && pendingAudio.isEmpty { endSession() }
            return
        }
        guard socket != nil else {
            // 同时使仍在等待麦克风授权的旧回调失效。
            endSession()
            return
        }
        appendAudio(tail)
        if !endingSegment {
            endingSegment = true
            sendEndFrame()
        }
    }

    /// 等所有续段及尾句返回；换段期间不以 isRecording 判断是否完成。
    func finish() async -> Bool {
        let paragraph = paragraphGeneration
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        stop()
        while !isSessionFinished {
            guard paragraphGeneration == paragraph else { return false }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                debugDetail = "停止录音后 30 秒内仍未收到完整尾句"
                errorMessage = lang.tr("speech.incompleteParagraph")
                if paragraphGeneration == paragraph { endSession() }
                return false
            }
            do { try await Task.sleep(nanoseconds: 50_000_000) }
            catch {
                if paragraphGeneration == paragraph { cancel() }
                return false
            }
        }
        return paragraphGeneration == paragraph && errorMessage == nil
    }

    /// 立刻中断，不等待结果（用户取消 / 页面退出 / 回退到 Apple Speech）
    func cancel() {
        paragraphGeneration += 1
        connectionTask?.cancel()
        connectionTask = nil
        sessionAppID = ""
        captureWanted = false
        captureGeneration += 1
        endingSegment = false
        nextSegmentAudio = Data()
        _ = capturedAudio.drain()
        generation += 1
        handshakeTimer?.invalidate()
        handshakeTimer = nil
        finalResultTimer?.invalidate()
        finalResultTimer = nil
        handshakeCompleted = false
        queuedFrames = []
        stopAudioCapture()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        pendingAudio = Data()
        recordedAudioData = nil
        audioProbe = probe.summary()
        isRecording = false
        isSessionFinished = true
    }

    // MARK: - 权限与音频采集

    private func requestMicThenConnect() {
        let requestGeneration = generation
        let av = AVAudioSession.sharedInstance()
        switch av.recordPermission {
        case .granted:
            connect()
        case .denied:
            errorMessage = lang.tr("speech.micDenied")
        case .undetermined:
            av.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.generation == requestGeneration, self.captureWanted else { return }
                    if granted { self.connect() }
                    else { self.errorMessage = self.lang.tr("speech.micUndetermined") }
                }
            }
        @unknown default:
            errorMessage = lang.tr("speech.micUnknown")
        }
    }

    /// 建立 WebSocket 连接
    private func connect() {
        connectionTask?.cancel()
        handshakeCompleted = false
        queuedFrames = []
        let version = generation
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let ticket: CloudGateway.ASRSession = try await CloudGateway.shared.request("v1/asr/session", body: [:])
                try Task.checkCancellation()
                guard self.generation == version else { return }
                guard let url = URL(string: ticket.url), url.scheme == "wss",
                      url.host == "iat-api.xfyun.cn", url.path == "/v2/iat", url.user == nil,
                      url.password == nil, url.port == nil, url.fragment == nil, !ticket.appID.isEmpty else {
                    throw GatewayError.invalidResponse
                }
                self.sessionAppID = ticket.appID
                self.connectionTask = nil
                self.openSocket(url: url)
            } catch {
                guard self.generation == version, !Task.isCancelled else { return }
                self.connectionTask = nil
                self.errorMessage = error.localizedDescription
                // Error observers may cancel and start Apple recognition synchronously.
                if self.generation == version { self.endSession() }
            }
        }
    }

    private func openSocket(url: URL) {
        handshakeCompleted = false
        queuedFrames = []

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        // 用 delegate 观测握手结果：只看 send 的失败信息无法区分
        // 「握手就被拒」和「握手成功但发送失败」，这两种的病因完全不同。
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        let task = session.webSocketTask(with: url)
        socket = task
        task.resume()

        receiveLoop(generation: generation)

        // 握手看门狗：8 秒内没建立就报错，避免界面一直停在「连接中」
        handshakeTimer?.invalidate()
        let gen = generation
        handshakeTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == gen, !self.handshakeCompleted else { return }
                self.lastFailureDetail = "握手超时（8 秒内未收到 HTTP 101）"
                self.debugDetail = self.lastFailureDetail
                self.errorMessage = "语音识别连接超时"
                self.endSession()
            }
        }

        // 不预发空首帧：协议规定 status=0 的第一帧就要携带音频，
        // 首帧由 appendAudio 在收到足够音频后带上 common/business 发出。
        if captureWanted && !hasAudioTap { startAudioCapture() }
        guard socket === task else { return }
        let buffered = nextSegmentAudio
        nextSegmentAudio = Data()
        if !buffered.isEmpty { appendAudio(buffered) }
        if !captureWanted && !endingSegment {
            endingSegment = true
            sendEndFrame()
        }
    }

    /// 启动麦克风采集，把音频重采样后分帧推送
    private func startAudioCapture() {
        let av = AVAudioSession.sharedInstance()
        do {
            // 用 .playAndRecord 而不是 .record：
            //
            // .record 是「仅采集」模式，系统不让音量键调节本应用的输出，
            // 出来的声音也不走扬声器（走受话音量）。用户反映的「app 里调不了
            // 声音、输入法很难下去」都源于此——录音结束后音频会话没有切回
            // 正常模式，整个 App 的播放音量一直卡在采集配置上。
            // .defaultToSpeaker 同时保证外放而不是听筒。
            try av.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
            )
            ownsAudioSession = true
            try av.setActive(true, options: .notifyOthersOnDeactivation)

            let node = audioEngine.inputNode
            // ⚠️ tap 的格式必须与节点输出格式一致。传一个不同的格式不会让引擎
            // 帮你转换，而是直接抛 NSException（"Failed to create tap due to
            // format mismatch"）并终止进程——点录音就闪退。
            // 采样率转换只能自己做，见 PCMResampler。
            let format = node.outputFormat(forBus: 0)
            probe.begin(hardware: format)

            // 闭包在音频线程执行，只捕获不可变引用，不碰 @MainActor 的 self
            let probe = self.probe
            let resampler = self.resampler
            let recordingBuffer = self.recordingBuffer
            let capturedAudio = self.capturedAudio
            let captureToken = captureGeneration
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard buffer.frameLength > 0 else { return }
                probe.noteTap()

                // 响度在原始 buffer 上取（此时还是 float，能拿到 floatChannelData）
                AudioLevelStore.shared.pushRaw(Double(buffer.normalizedLevel()))

                guard let pcm = resampler?.convert(buffer) else {
                    probe.noteConvertFailure(resampler?.lastFailure ?? "未知")
                    return
                }
                probe.noteConvert(bytes: pcm.count)
                recordingBuffer.append(pcm)
                capturedAudio.append(pcm)
                Task { @MainActor [weak self] in
                    guard let self, self.captureGeneration == captureToken else { return }
                    self.appendAudio(capturedAudio.drain())
                }
            }
            hasAudioTap = true

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            debugDetail = error.localizedDescription
            errorMessage = lang.tr("speech.recordFailed")
            endSession()
        }
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
        // 恢复成普通播放会话，并把控制权还给系统。
        //
        // 只调 setActive(false) 是不够的：category 会保持 .playAndRecord，
        // 音量键仍然按采集模式处理，用户会感觉「App 音量调不动」。
        // 显式切回 .playback 才是完整的收尾。
        if ownsAudioSession {
            ownsAudioSession = false
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
        isRecording = false
    }

    // MARK: - 发送协议帧

    /// 累积音频，攒满一帧就发一包。
    ///
    /// 首帧必须**携带真实音频**：协议里 `data.status=0` 的定义是「第一帧音频」，
    /// 不是「握手帧」。曾经先发一个 audio 为空的 status=0 帧做握手，服务端会
    /// 判为非法帧并直接断开，表现为「语音识别连接中断」。
    private func appendAudio(_ data: Data) {
        guard !data.isEmpty else { return }
        if socket == nil && connectionTask != nil {
            // 云端取票期间只积累 PCM；新连接建立后再生成 status=0 首帧。
            nextSegmentAudio.append(data)
            return
        }
        guard isRecording || socket != nil else { return }
        if endingSegment {
            nextSegmentAudio.append(data)
            return
        }
        pendingAudio.append(data)
        while pendingAudio.count >= Self.bytesPerFrame {
            let chunk = pendingAudio.prefix(Self.bytesPerFrame)
            pendingAudio.removeFirst(Self.bytesPerFrame)
            sendAudioFrame(Data(chunk), status: isFirstFrame ? 0 : 1)
            probe.noteFrameSent()
            isFirstFrame = false
            sentBytes += chunk.count
            // 40 秒后优先在连续 200ms 低能量处换段，减少句中音节被截断。
            // 未出现停顿时仍在 45 秒切段，给接口的 60 秒限制留余量。
            if sentBytes >= 40 * 32_000 {
                quietBytes = Self.isQuietFrame(Data(chunk)) ? quietBytes + chunk.count : 0
            }
            if quietBytes >= 6_400 || sentBytes >= 45 * 32_000 {
                endingSegment = true
                nextSegmentAudio.append(pendingAudio)
                pendingAudio = Data()
                sendEndFrame()
                break
            }
        }
    }

    private static func isQuietFrame(_ frame: Data) -> Bool {
        frame.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Bool in
            let sampleCount = bytes.count / 2
            guard sampleCount > 0 else { return false }
            var sumSquares = 0.0
            for offset in stride(from: 0, to: sampleCount * 2, by: 2) {
                let bits = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                let sample = Double(Int16(bitPattern: bits)) / 32_768.0
                sumSquares += sample * sample
            }
            return sumSquares / Double(sampleCount) <= 0.01 * 0.01
        }
    }

    /// 识别连接分段换新，麦克风和整段原录音保持连续。
    private func continueParagraph() {
        finalResultTimer?.invalidate()
        finalResultTimer = nil
        generation += 1
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        sessionPrefix += accumulated
        var carry = pendingAudio
        carry.append(nextSegmentAudio)
        nextSegmentAudio = carry
        accumulated = ""
        segmentResults = IATTranscriptAccumulator()
        nextResultSequence = 0
        sentBytes = 0
        quietBytes = 0
        pendingAudio = Data()
        isFirstFrame = true
        endingSegment = false
        connect()
    }

    func snapshotRecording() -> Data? { recordingBuffer.wavData() }

    /// 中间帧 / 末帧（仅 data）。
    ///
    /// 首帧（status=0）时额外带上 common + business —— 官方说明这些参数
    /// 「只需要在握手成功后的第一帧请求时带上」。
    private func sendAudioFrame(_ pcm: Data, status: Int) {
        var frame: [String: Any] = [
            "data": [
                "status": status,
                "format": "audio/L16;rate=16000",
                "encoding": "raw",
                "audio": pcm.base64EncodedString(),
            ]
        ]
        if status == 0 {
            frame["common"] = ["app_id": sessionAppID]
            frame["business"] = businessParameters
        }
        send(json: frame)
    }

    /// 末帧：结束并取最终结果
    private func sendEndFrame() {
        // 把不足一帧的尾巴补发（status=1），否则最后零点几秒会丢
        if !pendingAudio.isEmpty {
            let tail = Data(pendingAudio)
            pendingAudio = Data()
            // 若这一帧同时也是首帧（录音极短），仍按 status=0 带上 common/business
            sendAudioFrame(tail, status: isFirstFrame ? 0 : 1)
            isFirstFrame = false
            probe.noteFrameSent()
        }
        // 点下即松开时可能还没有任何 PCM；不能只发 status=2 冒充一次识别。
        guard !isFirstFrame else { endSession(); return }
        send(json: ["data": ["status": 2]])
        if handshakeCompleted { waitForFinalResult() }
    }

    private func waitForFinalResult() {
        guard endingSegment, finalResultTimer == nil else { return }
        let version = generation
        let timer = Timer(timeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == version, self.endingSegment else { return }
                self.debugDetail = "已发送结束帧，10 秒内未收到本段最终结果"
                self.errorMessage = self.lang.tr("speech.incompleteParagraph")
                // 上层可能在错误通知中取消本会话。
                if self.generation == version { self.endSession() }
            }
        }
        finalResultTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }

        // 握手未完成先排队。在握手前调用 send 会直接失败，而那个失败信息
        // （"音频发送失败"）会把真正的握手错误掩盖掉。
        guard handshakeCompleted else {
            queuedFrames.append(text)
            return
        }

        guard let socket else { return }
        let gen = generation
        socket.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                // 会话已被服务端错误码收尾时不再覆盖诊断。
                // 服务端回 10404/11200 后会立刻断连，在途帧的 send 全部失败，
                // 这些「发送失败」若覆盖掉错误码，就只剩一个与病因无关的
                // 「音频发送失败」，排查时被彻底带偏。
                guard !self.isSessionFinished else { return }
                let ns = error as NSError
                let detail = "发送失败 \(ns.domain)#\(ns.code) \(ns.localizedDescription)"
                self.lastFailureDetail = detail
                self.debugDetail = detail
                self.errorMessage = "音频发送失败"
                if self.generation == gen { self.endSession() }
            }
        }
    }

    /// 握手完成后把排队帧按序补发
    private func flushQueuedFrames() {
        let frames = queuedFrames
        queuedFrames = []
        guard let socket else { return }
        let gen = generation
        for text in frames {
            socket.send(.string(text)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in
                    guard let self, self.generation == gen else { return }
                    // 同 send(json:)：不覆盖服务端已经给出的错误码
                    guard !self.isSessionFinished else { return }
                    let ns = error as NSError
                    let detail = "补发失败 \(ns.domain)#\(ns.code) \(ns.localizedDescription)"
                    self.lastFailureDetail = detail
                    self.debugDetail = detail
                    self.errorMessage = "音频发送失败"
                    if self.generation == gen { self.endSession() }
                }
            }
        }
    }

    // MARK: - 接收

    /// 持续接收讯飞返回的识别结果
    private func receiveLoop(generation gen: Int) {
        socket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                switch result {
                case .failure(let error):
                    self.handleFailure(error)
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleResponse(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleResponse(text)
                        }
                    @unknown default:
                        break
                    }
                    if self.generation == gen, self.socket != nil { self.receiveLoop(generation: gen) }
                }
            }
        }
    }

    /// 解析一帧识别结果
    private func handleResponse(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }

        // 服务端错误。
        //
        // 错误字段的位置随接口而异：`iat-api.xfyun.cn/v2/iat` 放在顶层
        // （{"code":11200}），而集群入口 `iat.<region>.xf-yun.com/v1` 放在
        // header 里（{"header":{"code":10404}}）。只读顶层会漏掉后者的全部
        // 错误——连 10404「路由不存在」都读不到，一路沉默到降级。
        let header = json["header"] as? [String: Any]
        let code = (json["code"] as? Int) ?? (header?["code"] as? Int)
        if let code, code != 0 {
            let message = (json["message"] as? String)
                ?? (header?["message"] as? String)
                ?? "未知错误"
            debugDetail = "code=\(code) message=\(message)"
            errorMessage = Self.describe(code: code)
            endSession()
            return
        }

        guard let payload = json["data"] as? [String: Any] else { return }

        // 拼接本帧文字
        if let result = payload["result"] as? [String: Any],
           let words = result["ws"] as? [[String: Any]] {
            let piece = words.compactMap { word -> String? in
                guard let candidates = word["cw"] as? [[String: Any]],
                      let first = candidates.first else { return nil }
                return first["w"] as? String
            }.joined()

            let sequence = (result["sn"] as? Int) ?? nextResultSequence
            nextResultSequence = max(nextResultSequence, sequence + 1)
            let replacement = (result["pgs"] as? String) == "rpl" ? result["rg"] as? [Int] : nil
            segmentResults.apply(sequence: sequence, text: piece, replacing: replacement)
            accumulated = segmentResults.text
            transcript = sessionPrefix + accumulated
        }

        // status == 2 表示本次识别结束
        if let status = payload["status"] as? Int, status == 2 {
            if captureWanted || !nextSegmentAudio.isEmpty {
                continueParagraph()
            } else {
                endSession()
            }
        }
    }

    private func handleFailure(_ error: Error) {
        // 正常关闭（用户停止）不报错
        guard isRecording || socket != nil else { return }

        // 把底层错误拆开看：NSError 的 domain/code 和 URLError 的具体原因
        // 比 localizedDescription 更能定位问题（TLS？401？超时？）
        let ns = error as NSError
        var detail = "\(ns.domain)#\(ns.code) \(ns.localizedDescription)"
        if let urlError = error as? URLError {
            detail += " | URLError.code=\(urlError.code.rawValue)"
            if let underlying = urlError.errorUserInfo[NSUnderlyingErrorKey] as? NSError {
                detail += " | 底层:\(underlying.domain)#\(underlying.code)"
            }
            if let url = urlError.failingURL {
                detail += " | url=\(url.host ?? "?" )\(url.path)"
            }
        }

        debugDetail = detail
        lastFailureDetail = detail
        errorMessage = "语音识别连接中断"
        endSession()
    }

    /// 把讯飞错误码翻译成能看懂的说明。
    ///
    /// 最常见的是 11200（未授权）——所选方言需在控制台单独开通且未到期，
    /// 试用授权到期后也会返回这个码，是回退 Apple Speech 的主因。
    private static func describe(code: Int) -> String {
        switch code {
        case 11200: return "方言识别服务未授权或已到期（11200）"
        case 10404: return "接口地址与 AppID 不匹配，路由不存在（10404）"
        case 10165: return "音频首帧缺失或帧顺序不正确（10165）"
        case 10161: return "音频数据编码不正确（10161）"
        case 10163: return "识别请求缺少参数或参数不正确（10163）"
        case 10114: return "识别会话超时，单段不超过 60 秒（10114）"
        case 10202: return "鉴权失败，请检查设备时间是否准确（10202）"
        default:    return "讯飞识别失败（\(code)）"
        }
    }

    /// 收尾：关闭连接与音频
    private func endSession() {
        connectionTask?.cancel()
        connectionTask = nil
        captureWanted = false
        captureGeneration += 1
        generation += 1
        _ = capturedAudio.drain()
        handshakeTimer?.invalidate()
        handshakeTimer = nil
        finalResultTimer?.invalidate()
        finalResultTimer = nil
        handshakeCompleted = false
        queuedFrames = []
        stopAudioCapture()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        pendingAudio = Data()
        recordedAudioData = recordingBuffer.wavData()
        audioProbe = probe.summary()
        isSessionFinished = true
    }
}

/// 音频链路量测。
///
/// 存在的理由：`isRecording == true` 只说明 `audioEngine.start()` 没抛异常。
/// 麦克风采集到**静音**时它同样为真，界面照样打 ✓，但服务端一个字节都收不到，
/// 最终表现为「识别完成但没有文字」——一个把病因完全藏起来的失败。
/// 这组计数把链路断开的位置标出来：
///  - tapCalls == 0        → tap 根本没被回调（引擎/会话配置问题）
///  - tapCalls > 0, convert == 0 → 重采样失败（输入格式不兼容）
///  - convert > 0, frames == 0   → 攒不满一帧（音频过短或全是空 buffer）
final class AudioProbe {
    static let shared = AudioProbe()

    private let lock = NSLock()
    private var tapCalls = 0
    private var convertCalls = 0
    private var audioBytes = 0
    private var frames = 0
    private var format = "?"
    private var convertFailReason: String?

    private init() {}

    func begin(hardware: AVAudioFormat) {
        lock.lock(); defer { lock.unlock() }
        tapCalls = 0; convertCalls = 0; audioBytes = 0; frames = 0
        convertFailReason = nil
        let kind: String
        switch hardware.commonFormat {
        case .pcmFormatFloat32: kind = "f32"
        case .pcmFormatInt16:   kind = "i16"
        case .pcmFormatInt32:   kind = "i32"
        default:                kind = "其他"
        }
        format = "\(Int(hardware.sampleRate))Hz/\(hardware.channelCount)ch/\(kind)"
    }

    func noteTap() {
        lock.lock(); tapCalls += 1; lock.unlock()
    }

    func noteConvert(bytes: Int) {
        lock.lock(); convertCalls += 1; audioBytes += bytes; lock.unlock()
    }

    /// 只保留第一次失败原因：后续失败基本都是同一个，重复覆盖没有价值
    func noteConvertFailure(_ reason: String) {
        lock.lock()
        if convertFailReason == nil { convertFailReason = reason }
        lock.unlock()
    }

    func noteFrameSent() {
        lock.lock(); frames += 1; lock.unlock()
    }

    /// 一行摘要，直接显示在诊断行里
    func summary() -> String {
        lock.lock(); defer { lock.unlock() }
        let seconds = Double(audioBytes) / 32000.0
        var text = String(
            format: "麦克风 %@ · 回调 %d 次 · 转出 %d 次/%.1f 秒 · 已发 %d 帧",
            format, tapCalls, convertCalls, seconds, frames
        )
        if let reason = convertFailReason {
            text += " · 失败原因：\(reason)"
        }
        return text
    }
}

// MARK: - WebSocket 握手观测

/// 用 delegate 拿到握手阶段的真实结果。
///
/// 为什么必须这样：在握手完成前调用 `send` 只会得到一个笼统的
/// 「音频发送失败」，无法区分「握手就被服务端拒绝（401/403）」和
/// 「握手成功但后续发送失败」。这两者病因完全不同——前者要查签名，
/// 后者要查网络。`didOpen` 同时用于放行排队中的音频帧。
extension IFlytekASRService: URLSessionWebSocketDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.socket === webSocketTask else { return }
            self.handshakeCompleted = true
            self.handshakeTimer?.invalidate()
            self.handshakeTimer = nil
            self.flushQueuedFrames()
            if self.endingSegment { self.waitForFinalResult() }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 正常关闭（用户停止 / 服务端收完末帧）不当作错误
            guard self.socket === webSocketTask else { return }
            let wasHandshake = !self.handshakeCompleted
            let detail = "关闭码 \(closeCode.rawValue)"
                + (reasonText.isEmpty ? "" : " 原因:\(reasonText)")
                + (wasHandshake ? " — 握手阶段被拒，请检查签名与接口地址" : "")
            self.lastFailureDetail = detail
            self.debugDetail = detail
            self.errorMessage = wasHandshake ? "语音识别握手失败" : "语音识别连接已关闭"
            self.endSession()
        }
    }
}
