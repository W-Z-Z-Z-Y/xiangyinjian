import Foundation
import CryptoKit

/// 讯飞 WebSocket 鉴权：把 APPID/APIKey/APISecret 组装成带签名的 wss URL。
///
/// 算法（官方文档 https://www.xfyun.cn/doc/asr/voicedictation/API.html）：
/// ```
/// signature_origin = "host: \(host)\ndate: \(date)\nGET \(path) HTTP/1.1"
/// signature_sha    = HMAC-SHA256(signature_origin, apiSecret)
/// signature        = base64(signature_sha)
/// authorization_origin = api_key="...",algorithm="hmac-sha256",headers="host date request-line",signature="..."
/// authorization        = base64(authorization_origin)
/// ```
/// 最后拼成 `wss://host/path?authorization=...&date=...&host=...`
///
/// 单独成类型的原因：这是纯函数、无副作用，失败原因集中在签名和时钟上，
/// 与网络逻辑分开后排查范围小很多。
enum IFlytekAuth {

    /// 讯飞要求 date 为 RFC1123 格式且必须是 **GMT**。
    /// 服务器允许最多 300 秒时钟偏差，所以设备时间不准会导致握手 401。
    static func rfc1123Date(_ now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: now)
    }

    /// 构造带签名的 WebSocket URL。
    ///
    /// - Parameter endpoint: 形如 `wss://iat.cn-huabei-1.xf-yun.com/v1`。
    ///   host 与 path 都从中解析，避免两处各写一遍导致不一致。
    /// - Returns: 可直接交给 `URLSessionWebSocketTask` 的 URL；解析失败返回 nil。
    static func signedURL(
        endpoint: String,
        apiKey: String,
        apiSecret: String,
        date: Date = Date()
    ) -> URL? {
        guard let comps = URLComponents(string: endpoint),
              let host = comps.host else { return nil }

        // path 为空时补 "/"，否则签名的 request-line 与服务端不匹配
        let path = comps.path.isEmpty ? "/" : comps.path
        let dateString = rfc1123Date(date)

        let signatureOrigin = "host: \(host)\ndate: \(dateString)\nGET \(path) HTTP/1.1"

        guard let secretData = apiSecret.data(using: .utf8),
              let originData = signatureOrigin.data(using: .utf8) else { return nil }

        let mac = HMAC<SHA256>.authenticationCode(for: originData, using: SymmetricKey(data: secretData))
        let signature = Data(mac).base64EncodedString()

        let authOrigin = "api_key=\"\(apiKey)\",algorithm=\"hmac-sha256\","
            + "headers=\"host date request-line\",signature=\"\(signature)\""
        guard let authData = authOrigin.data(using: .utf8) else { return nil }
        let authorization = authData.base64EncodedString()

        var signed = comps
        signed.queryItems = [
            URLQueryItem(name: "authorization", value: authorization),
            URLQueryItem(name: "date",          value: dateString),
            URLQueryItem(name: "host",          value: host),
        ]
        return signed.url
    }
}
