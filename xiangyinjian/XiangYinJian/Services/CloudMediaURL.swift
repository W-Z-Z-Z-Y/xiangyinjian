import Foundation

nonisolated enum CloudMediaURL {
    static func validated(_ raw: String) -> URL? {
        guard var components = URLComponents(string: raw), let host = components.host,
              components.scheme == "http" || components.scheme == "https",
              components.user == nil, components.password == nil, components.port == nil,
              // 语音使用 dashscope-result-*，万相插画也会返回 dashscope-数字 的 OSS 地址。
              host.range(of: "^dashscope-(?:result-[a-z0-9-]+|[0-9]+)\\.oss-[a-z0-9-]+\\.aliyuncs\\.com$",
                         options: .regularExpression) != nil else { return nil }
        components.scheme = "https"
        return components.url
    }
}
