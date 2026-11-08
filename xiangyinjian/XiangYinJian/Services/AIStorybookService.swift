import Foundation

@MainActor
struct AIStorybookService {
    var isConfigured: Bool { CloudGateway.shared.isConfigured }
    struct StoryMeta: Decodable {
        let title: String
        let keywords: [String]
    }
    private struct Tags: Decodable { let tags: [String] }
    private struct ImageTask: Decodable { let taskId: String }
    private struct ImageStatus: Decodable { let status: String; let url: String?; let message: String? }

    func generateMeta(for story: String) async throws -> StoryMeta {
        guard isConfigured else { throw AIError.notConfigured }
        let result: StoryMeta = try await CloudGateway.shared.request("v1/story/meta", body: ["story": story])
        guard !result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !result.keywords.isEmpty else { throw AIError.decoding }
        return result
    }

    func extractMemoryTags(from text: String) async throws -> [String] {
        guard isConfigured else { throw AIError.notConfigured }
        let result: Tags = try await CloudGateway.shared.request("v1/story/tags", body: ["text": String(text.prefix(3000))])
        var tags: [String] = []
        for value in result.tags {
            let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if (2...8).contains(tag.count), text.contains(tag), !tags.contains(tag) { tags.append(tag) }
        }
        return Array(tags.prefix(5))
    }

    func generateStory(topic: String, dialect: String) async throws -> String {
        guard isConfigured else { throw AIError.notConfigured }
        let result: CloudGateway.TextResult = try await CloudGateway.shared.request("v1/story/generate", body: ["topic": topic, "dialect": dialect])
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.decoding }
        return text
    }

    func generateImage(for keywords: [String]) async throws -> String {
        guard isConfigured else { throw AIError.notConfigured }
        let task: ImageTask = try await CloudGateway.shared.request("v1/story/image", body: ["keywords": keywords])
        guard !task.taskId.isEmpty,
              task.taskId.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else { throw AIError.decoding }
        var transientFailures = 0
        for _ in 0..<30 {
            try Task.checkCancellation()
            let result: ImageStatus
            do {
                result = try await CloudGateway.shared.request("v1/story/image/" + task.taskId)
            } catch let error as DemoCloudError {
                // 仅继续查询原任务，不因一次断网或限流重复提交收费生图。
                switch error {
                case .network, .timeout, .busy:
                    transientFailures += 1
                    guard transientFailures <= 3 else { throw error }
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                default: throw error
                }
            }
            try Task.checkCancellation()
            switch result.status {
            case "SUCCEEDED":
                guard let value = result.url, let url = URL(string: value), url.scheme == "https", url.host != nil else { throw AIError.decoding }
                return value
            case "FAILED", "CANCELED", "UNKNOWN":
                throw AIError.imageGeneration(result.message ?? (UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "Image generation failed. Please retry." : "插画生成失败，请重试。"))
            case "PENDING", "RUNNING":
                try await Task.sleep(nanoseconds: 3_000_000_000)
            default: throw AIError.decoding
            }
        }
        throw AIError.network(UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "Image generation timed out. Try later." : "插画生成超时，请稍后重试。")
    }
}

// MARK: - AI错误类型
enum AIError: LocalizedError {
    case notConfigured
    case network(String)
    case decoding
    case imageGeneration(String)
    case imageCache
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "Configure cloud services using the project setup guide." : "尚未配置云服务，请按项目配置指南填写自己的密钥。"
        case .network(let msg):
            return "网络错误：\(msg)"
        case .decoding:
            return "AI 返回解析失败，请重试"
        case .imageGeneration(let message):
            return message
        case .imageCache:
            return UserDefaults.standard.string(forKey: "appLanguage") != "en"
                ? "插图未能保存到本机，请检查网络或剩余存储后重试。"
                : "The illustration could not be saved on this device. Check your connection or available storage, then retry."
        case .saveFailed:
            return UserDefaults.standard.string(forKey: "appLanguage") != "en"
                ? "绘本保存失败，原有绘本已保留，请重试。"
                : "The storybook could not be saved. Existing books were kept. Please retry."
        }
    }
}
