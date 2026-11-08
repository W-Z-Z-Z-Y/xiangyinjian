import Foundation

// MARK: - 翻译服务协议

/// 翻译服务统一协议，本地词库与云端翻译共用入口
protocol TranslationServiceProtocol {
    /// 是否已正确配置（API Key 等）
    var isConfigured: Bool { get }
    /// 该引擎是否支持指定方言
    func supports(dialect: String) -> Bool
    /// 执行翻译（普通话 → 方言）
    func translate(_ text: String, to dialect: String) async throws -> String
    /// 执行翻译（方言 → 普通话）
    func translateToMandarin(_ text: String, from dialect: String) async throws -> String
}

// MARK: - 翻译错误类型

/// 翻译错误类型（带中文描述，可直接展示给用户）
enum TranslationError: LocalizedError {
    case notConfigured
    case network(String)
    case api(code: String, msg: String)
    case decoding
    case truncated
    case untranslated

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "这句话未命中离线词库。请先按项目配置指南配置云服务。"
        case .network(let m):
            return "网络请求失败：\(m)"
        case .api(let code, let msg):
            return "翻译接口返回错误（\(code)）：\(msg)"
        case .decoding:
            return "无法解析翻译结果，请稍后重试。"
        case .truncated:
            return "文本较长，翻译结果可能不完整，请分段翻译后重试。"
        case .untranslated:
            return "这次没能翻译出来。请换一种说法，或把句子说得更完整一些再试。"
        }
    }
}

/// 离线词库优先；开发版使用本机私有配置，直连云端翻译自由句子。
@MainActor
struct TranslationManager: TranslationServiceProtocol {
    var isConfigured: Bool { CloudGateway.shared.isConfigured }

    func supports(dialect: String) -> Bool { Dialects.names.contains(dialect) || dialect == "闽南话" }

    func translate(_ text: String, from sourceDialect: String, to targetDialect: String) async throws -> String {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let source = sourceDialect == "闽南话" ? "闽南语" : sourceDialect
        let target = targetDialect == "闽南话" ? "闽南语" : targetDialect
        if source == target { return text }
        if source == "普通话", let local = LocalDictionary.lookup(text, dialect: target) { return local }
        if target == "普通话", let local = LocalDictionary.reverseLookup(dialectText: text, from: source) { return local }
        if source != "普通话", target != "普通话",
           let mandarin = LocalDictionary.reverseLookup(dialectText: text, from: source),
           let local = LocalDictionary.lookup(mandarin, dialect: target) { return local }
        guard isConfigured else { throw TranslationError.notConfigured }
        var translated: [String] = []
        for chunk in TranslationParagraph.chunks(text, limit: 600) {
            try Task.checkCancellation()
            // 长段落中的空行不能作为空请求发送；保留分段边缘的空白和段落布局。
            let content = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { translated.append(chunk); continue }
            let result: CloudGateway.TextResult = try await CloudGateway.shared.request("v1/translate", body: [
                "text": content, "sourceDialect": source, "targetDialect": target
            ])
            let value = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw TranslationError.decoding }
            let leading = String(chunk.prefix(while: { $0.isWhitespace }))
            let trailing = String(chunk.reversed().prefix(while: { $0.isWhitespace }).reversed())
            translated.append(leading + value + trailing)
        }
        try Task.checkCancellation()
        return translated.joined()
    }

    func translate(_ text: String, to dialect: String) async throws -> String {
        try await translate(text, from: "普通话", to: dialect)
    }

    func translateToMandarin(_ text: String, from dialect: String) async throws -> String {
        try await translate(text, from: dialect, to: "普通话")
    }
}
