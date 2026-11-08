import Foundation

/// 与讯飞控制台「语音听写 → 方言/语种」已开通项目保持一致。
/// 独立方言使用 iat + accent，不要求另开通多方言免切服务。
enum IFlytekDialectConfiguration {
    private static let accents: [String: String] = [
        "普通话": "mandarin",
        "粤语": "cantonese",
        "广东话": "cantonese",
        "东北话": "dongbeiese",
        "四川话": "lmz",
        "普通话+四川话": "cn_lmz",
        "普通话＋四川话": "cn_lmz",
        "闽南语": "minnanese",
        "闽南话": "minnanese",
        "客家话": "hakkanese"
    ]

    static func supports(_ dialect: String) -> Bool { accents[dialect] != nil }

    static func businessParameters(for dialect: String) -> [String: Any]? {
        guard let accent = accents[dialect] else { return nil }
        var parameters: [String: Any] = [
            "language": "zh_cn",
            "domain": "iat",
            "accent": accent,
            "eos": 10000,
            "rlang": "zh-cn"
        ]
        // 官方动态修正仅支持中文普通话，混合四川话引擎也不附加此参数。
        if dialect == "普通话" { parameters["dwa"] = "wpgs" }
        return parameters
    }
}
