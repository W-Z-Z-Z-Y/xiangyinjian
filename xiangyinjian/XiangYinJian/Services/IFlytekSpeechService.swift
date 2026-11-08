import Foundation

/// 东北话「子阳」在线合成。语音听写权限与此发音人的合成权限分别开通。
@MainActor
enum IFlytekSpeechService {
    private static let endpoint = "wss://cbm01.cn-huabei-1.xf-yun.com/v1/private/mcd9m97e6"
    private static let maximumAudioBytes = 20 * 1024 * 1024
    private static let maximumMessageBytes = 14 * 1024 * 1024

    static func synthesize(text: String, configuration: DemoCloudConfiguration) async throws -> Data {
        try Task.checkCancellation()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: " ")
        guard !text.isEmpty, text.count <= 600, text.utf8.count <= 64 * 1024 else {
            throw IFlytekSpeechError.invalidInput
        }
        guard configuration.hasASR,
              let url = IFlytekAuth.signedURL(endpoint: endpoint,
                                            apiKey: configuration.iflytekAPIKey,
                                            apiSecret: configuration.iflytekAPISecret) else {
            throw IFlytekSpeechError.notConfigured
        }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 45
        sessionConfiguration.timeoutIntervalForResource = 55
        sessionConfiguration.urlCache = nil
        let session = URLSession(configuration: sessionConfiguration,
                                 delegate: IFlytekSpeechRedirectPolicy(), delegateQueue: nil)
        let socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = maximumMessageBytes
        let deadline = ContinuousClock.now.advanced(by: .seconds(55))
        // A separate watchdog closes any pending send/receive; no task-group child can
        // keep the caller waiting after cancellation or the total deadline.
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(55)) }
            catch { return }
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }
        defer {
            watchdog.cancel()
            socket.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        do {
            return try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                socket.resume()
                let request: [String: Any] = [
                    "header": ["app_id": configuration.iflytekAppID, "status": 2],
                    "parameter": [
                        "oral": ["oral_level": "low", "spark_assist": 0, "remain": 1, "stop_split": 0],
                        "tts": [
                            "vcn": "x4_ziyang_oral", "speed": 50, "volume": 50, "pitch": 50,
                            "bgs": 0, "reg": 0, "rdn": 0, "rhy": 0,
                            "audio": ["encoding": "raw", "sample_rate": 24000,
                                      "channels": 1, "bit_depth": 16, "frame_size": 0]
                        ]
                    ],
                    "payload": ["text": [
                        "encoding": "utf8", "compress": "raw", "format": "plain",
                        "status": 2, "seq": 0, "text": Data(text.utf8).base64EncodedString()
                    ]]
                ]
                let body = try JSONSerialization.data(withJSONObject: request)
                guard let json = String(data: body, encoding: .utf8) else { throw IFlytekSpeechError.invalidInput }
                try await socket.send(.string(json))

                var pcm = Data()
                var receivedMessages = 0
                while true {
                    try Task.checkCancellation()
                    if ContinuousClock.now >= deadline { throw IFlytekSpeechError.timeout }
                    let message = try await socket.receive()
                    try Task.checkCancellation()
                    receivedMessages += 1
                    guard receivedMessages <= 4096 else { throw IFlytekSpeechError.invalidResponse }
                    let data: Data
                    switch message {
                    case .string(let value): data = Data(value.utf8)
                    case .data(let value): data = value
                    @unknown default: throw IFlytekSpeechError.invalidResponse
                    }
                    guard data.count <= maximumMessageBytes,
                          let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw IFlytekSpeechError.invalidResponse
                    }
                    // Some platform errors are returned at the top level, before a session exists.
                    let header = response["header"] as? [String: Any] ?? response
                    guard let code = header["code"] as? Int else { throw IFlytekSpeechError.invalidResponse }
                    if code != 0 { throw IFlytekSpeechError.provider(code: code) }
                    guard let status = header["status"] as? Int, (0...2).contains(status) else {
                        throw IFlytekSpeechError.invalidResponse
                    }
                    if let payload = response["payload"] as? [String: Any],
                       let audio = payload["audio"] as? [String: Any] {
                        guard audio["encoding"] as? String == "raw",
                              audio["sample_rate"] as? Int == 24000,
                              audio["channels"] as? Int == 1,
                              audio["bit_depth"] as? Int == 16,
                              let base64 = audio["audio"] as? String,
                              let chunk = Data(base64Encoded: base64),
                              chunk.count <= maximumAudioBytes - pcm.count else {
                            throw IFlytekSpeechError.invalidResponse
                        }
                        pcm.append(chunk)
                    }
                    // header.status marks the whole session; an individual audio segment
                    // ending is not sufficient when the provider splits text internally.
                    if status == 2 {
                        guard !pcm.isEmpty, pcm.count % 2 == 0 else { throw IFlytekSpeechError.invalidResponse }
                        try Task.checkCancellation()
                        return makeWAV(pcm)
                    }
                    await Task.yield()
                }
            }, onCancel: {
                socket.cancel(with: .goingAway, reason: nil)
                session.invalidateAndCancel()
            })
        } catch {
            try Task.checkCancellation()
            if let failure = error as? IFlytekSpeechError { throw failure }
            if ContinuousClock.now >= deadline || (error as? URLError)?.code == .timedOut {
                throw IFlytekSpeechError.timeout
            }
            let status = (socket.response as? HTTPURLResponse)?.statusCode
            if status == 401 { throw IFlytekSpeechError.credentials }
            if status == 403 { throw IFlytekSpeechError.permission }
            if status == 429 { throw IFlytekSpeechError.quota }
            // Do not expose Foundation error descriptions: they may contain the signed URL.
            throw IFlytekSpeechError.network
        }
    }

    private static func makeWAV(_ pcm: Data) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + pcm.count))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(24000))
        append(UInt32(48000))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

private final class IFlytekSpeechRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum IFlytekSpeechError: LocalizedError {
    case notConfigured, invalidInput, invalidResponse, credentials, permission, quota, timeout, network
    case provider(code: Int)

    nonisolated var errorDescription: String? {
        let english = UserDefaults.standard.string(forKey: "appLanguage") == "en"
        switch self {
        case .notConfigured:
            return english ? "Configure speech services using the project setup guide." : "尚未配置语音服务，请按项目配置指南填写自己的密钥。"
        case .invalidInput:
            return english ? "Shorten the text and remove unsupported symbols, then retry." : "请缩短文字并去除不支持的符号后重试。"
        case .invalidResponse:
            return english ? "The dialect audio was incomplete. Please retry." : "方言音频返回不完整，请重试。"
        case .credentials:
            return english ? "Check that the iFlytek credentials belong to the same app and your device time is correct." : "请检查讯飞三个字段是否属于同一应用，并确认手机时间正确。"
        case .permission:
            return english ? "Enable iFlytek Super Smart TTS and the Ziyang voice (x4_ziyang_oral); check their expiry and remaining credits." : "请在讯飞控制台开通「超拟人语音合成」及「子阳（x4_ziyang_oral）」音色，并检查授权有效期和合成额度。"
        case .quota:
            return english ? "The iFlytek speech quota or concurrency limit has been reached. Check the console or retry later." : "讯飞合成额度或并发次数已达上限，请检查控制台或稍后重试。"
        case .timeout:
            return english ? "Dialect speech timed out. Please retry later." : "方言朗读响应超时，请稍后重试。"
        case .network:
            return english ? "Could not connect to iFlytek speech. Check your network and retry." : "无法连接讯飞语音服务，请检查网络后重试。"
        case .provider(let code):
            switch code {
            case 10010, 11200: return IFlytekSpeechError.permission.errorDescription
            case 10313: return IFlytekSpeechError.credentials.errorDescription
            case 11201: return IFlytekSpeechError.quota.errorDescription
            case 10019, 10114, 10200, 26005, 26006: return IFlytekSpeechError.timeout.errorDescription
            case 10009, 10139, 10160, 10161, 10163: return IFlytekSpeechError.invalidInput.errorDescription
            default:
                return english ? "iFlytek speech failed (code \(code)). Check service permissions or retry later." : "讯飞合成失败（错误码 \(code)），请检查服务权限或稍后重试。"
            }
        }
    }
}
