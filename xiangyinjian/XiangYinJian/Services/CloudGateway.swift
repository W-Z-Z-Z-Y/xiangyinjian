import Foundation

struct DemoCloudConfiguration: Codable {
    let apiKey: String
    let region: String
    let iflytekAppID: String
    let iflytekAPIKey: String
    let iflytekAPISecret: String

    var hasASR: Bool { !iflytekAppID.isEmpty && !iflytekAPIKey.isEmpty && !iflytekAPISecret.isEmpty }
}

/// 开发演示直连：从本机私有配置读取凭据，公开源码不包含密钥。
@MainActor
final class CloudGateway {
    static let shared = CloudGateway()
    struct TextResult: Decodable { let text: String }
    struct ASRSession: Decodable { let url: String; let appID: String }

    private let configuration: Result<DemoCloudConfiguration, GatewayError>
    private let speechCache = CloudSpeechAudioCache()

    private init() {
        do { configuration = .success(try Self.loadBundledConfiguration()) }
        catch let error as GatewayError { configuration = .failure(error) }
        catch { configuration = .failure(.invalidConfiguration) }
    }

    var isConfigured: Bool { (try? configuration.get().apiKey.isEmpty) == false }
    var asrConfigured: Bool { (try? configuration.get().hasASR) == true }

    func speechConfigured(for dialect: String) -> Bool {
        if dialect == "东北话" { return asrConfigured }
        return ["四川话", "闽南语", "粤语"].contains(dialect) && isConfigured
    }

    private static func loadBundledConfiguration() throws -> DemoCloudConfiguration {
        guard let url = Bundle.main.url(forResource: "DemoSecrets.local", withExtension: "plist") else {
            throw GatewayError.notConfigured
        }
        guard let data = try? Data(contentsOf: url),
              let value = try? PropertyListDecoder().decode(DemoCloudConfiguration.self, from: data) else {
            throw GatewayError.invalidConfiguration
        }
        let parts = [value.iflytekAppID, value.iflytekAPIKey, value.iflytekAPISecret]
        guard ["beijing", "singapore"].contains(value.region),
              value.apiKey.isEmpty || (value.apiKey.hasPrefix("sk-") && value.apiKey.count > 10),
              !parts.contains(where: { !$0.isEmpty }) || value.hasASR,
              ([value.apiKey] + parts).allSatisfy({ !$0.contains(where: { $0.isWhitespace }) && $0.count <= 512 }) else { throw GatewayError.invalidConfiguration }
        guard !value.apiKey.isEmpty || value.hasASR else { throw GatewayError.notConfigured }
        return value
    }

    func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        let data = try await DemoCloudProvider(configuration: configuration.get()).request(path: path, body: body)
        try Task.checkCancellation()
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw GatewayError.invalidResponse }
    }

    func synthesize(text: String, dialect: String, gender: String) async throws -> Data {
        try Task.checkCancellation()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let dialect = dialect == "闽南话" ? "闽南语" : dialect
        // 音色映射或模型更换时提升版本；语速由本机播放器调整，不参与缓存键。
        let cacheKey = ["speech-v1-qwen3-tts-flash-iflytek-ziyang", dialect, gender, text].joined(separator: "\u{0}")
        if let cached = await speechCache.audio(for: cacheKey) {
            try Task.checkCancellation()
            return cached
        }
        let data = try await DemoCloudProvider(configuration: configuration.get()).request(
            path: "v1/speech", body: ["text": text, "dialect": dialect, "gender": gender]
        )
        try Task.checkCancellation()
        let audio = await speechCache.store(data, for: cacheKey)
        try Task.checkCancellation()
        return audio
    }
}

enum GatewayError: LocalizedError {
    case notConfigured, invalidConfiguration, invalidResponse
    nonisolated var errorDescription: String? {
        let en = UserDefaults.standard.string(forKey: "appLanguage") == "en"
        switch self {
        case .notConfigured: return en ? "Cloud services are not configured. Add your own credentials using the project setup guide." : "尚未配置云服务。开发者请按项目配置指南填写自己的密钥。"
        case .invalidConfiguration: return en ? "This version has an invalid online service configuration. Please update the app and retry." : "当前版本的在线服务配置异常，请更新应用后重试。"
        case .invalidResponse: return en ? "The service returned an invalid response. Please retry." : "服务返回内容异常，请重试。"
        }
    }
}
