import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {

    // MARK: - 导航
    @Published var selectedTab: Tab = .translate
    /// Siri/Intent 请求进入 More 的子页面时设置；ToolsHubView 监听后 push 并置 nil
    @Published var moreNavigationTarget: MoreDestination?
    @Published var memoryNavigationTarget: MemoryDestination?

    // MARK: - 用户偏好
    @Published var preferredDialect: String = "粤语" {
        didSet { UserDefaults.standard.set(preferredDialect, forKey: "preferredDialect") }
    }

    @Published var familyContactPhone: String = "" {
        didSet { UserDefaults.standard.set(familyContactPhone, forKey: "familyContactPhone") }
    }

    // MARK: - 翻译历史
    @Published private(set) var history: [HistoryRecord] = []
    @Published var persistenceError: String?

    // MARK: - 常用语库
    @Published var phrases: [Phrase] = Phrase.defaults
    private var savedPhrases: [Phrase] = Phrase.defaults

    init() {
        preferredDialect = UserDefaults.standard.string(forKey: "preferredDialect") ?? "粤语"
        familyContactPhone = UserDefaults.standard.string(forKey: "familyContactPhone") ?? ""
        history = HistoryStore.load()
        phrases = AppFileStore.load([Phrase].self,
                                    fileName: "phrases.json",
                                    legacyKey: "phrases") ?? Phrase.defaults
        savedPhrases = phrases
    }

    @discardableResult
    func addHistory(_ record: HistoryRecord) -> Bool {
        completeHistoryChange(HistoryStore.add(record))
    }

    @discardableResult
    func clearHistory() -> Bool {
        completeHistoryChange(HistoryStore.clear())
    }

    @discardableResult
    func toggleFavorite(_ record: HistoryRecord) -> Bool {
        completeHistoryChange(HistoryStore.toggleFavorite(id: record.id))
    }

    @discardableResult
    func deleteHistory(ids: Set<UUID>) -> Bool {
        completeHistoryChange(HistoryStore.remove(ids: ids))
    }

    func reloadHistory() {
        history = HistoryStore.load()
    }

    private func completeHistoryChange(_ saved: Bool) -> Bool {
        reloadHistory()
        if !saved { persistenceError = LanguageManager.shared.tr("storage.failed") }
        return saved
    }

    @discardableResult
    func savePhrases() -> Bool {
        guard AppFileStore.save(phrases, fileName: "phrases.json", legacyKey: "phrases") else {
            phrases = savedPhrases
            persistenceError = LanguageManager.shared.tr("storage.failed")
            return false
        }
        savedPhrases = phrases
        return true
    }

    enum Tab: Hashable {
        // 顶层 Tab（TabView 渲染）
        case translate, tools, memory, profile
        case phrases, voiceCards, storybook, more
        // 以下 case 不再作为顶层 Tab，统一收入 More；保留供 App Intents 经 IntentRouter 请求，由 ContentView 映射到 more + moreNavigationTarget
        case history, settings, antiScam
    }
}

/// More 页的子页面目标，配合 AppState.moreNavigationTarget 做 programmatic 导航
enum MoreDestination: Hashable {
    case phrases, history, antiScam, settings, dualDialect, voiceAssistant
}

enum MemoryDestination: Hashable {
    case voiceCards, storybook, history, archive
}

// MARK: - 数据模型

struct HistoryRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date = Date()
    var sourceText: String
    var translatedText: String
    var dialect: String
    var isFavorited: Bool = false

    // 自定义解码：兼容旧数据（没有 isFavorited 字段时默认 false）
    init(id: UUID = UUID(), date: Date = Date(),
         sourceText: String, translatedText: String,
         dialect: String, isFavorited: Bool = false) {
        self.id = id
        self.date = date
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.dialect = dialect
        self.isFavorited = isFavorited
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        sourceText = try c.decode(String.self, forKey: .sourceText)
        translatedText = try c.decode(String.self, forKey: .translatedText)
        dialect = try c.decode(String.self, forKey: .dialect)
        isFavorited = try c.decodeIfPresent(Bool.self, forKey: .isFavorited) ?? false
    }
}

struct Phrase: Identifiable, Codable {
    var id: UUID = UUID()
    var category: String
    var text: String
    var translation: String
    /// 明确记录句子所属方言，避免根据全局默认方言误读。
    var dialect: String

    init(id: UUID = UUID(), category: String, text: String, translation: String, dialect: String) {
        self.id = id
        self.category = category
        self.text = text
        self.translation = translation
        self.dialect = dialect
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        category = try c.decode(String.self, forKey: .category)
        text = try c.decode(String.self, forKey: .text)
        translation = try c.decode(String.self, forKey: .translation)
        dialect = try c.decodeIfPresent(String.self, forKey: .dialect)
            ?? Self.inferLegacyDialect(text: text, translation: translation)
    }

    private static func inferLegacyDialect(text: String, translation: String) -> String {
        for dialect in Dialects.names where translation.contains("（\(dialect)）") {
            return dialect
        }
        let cantoneseMarkers = ["唔", "咗", "冇", "乜", "佢", "啱", "啲"]
        if cantoneseMarkers.contains(where: text.contains) { return "粤语" }
        return "普通话"
    }

    static let defaults: [Phrase] = [
        Phrase(category: "问候", text: "你好", translation: "你好（普通话）", dialect: "普通话"),
        Phrase(category: "问候", text: "早晨", translation: "早上好（粤语）", dialect: "粤语"),
        Phrase(category: "问候", text: "你好呀", translation: "你好（东北话）", dialect: "东北话"),
        Phrase(category: "问候", text: "你好哇", translation: "你好（四川话）", dialect: "四川话"),
        Phrase(category: "日常", text: "食咗未", translation: "吃了吗（粤语）", dialect: "粤语"),
        Phrase(category: "日常", text: "吃了没", translation: "吃了吗（东北话）", dialect: "东北话"),
        Phrase(category: "日常", text: "食饭无", translation: "吃饭了吗（客家话）", dialect: "客家话"),
        Phrase(category: "日常", text: "吃了冇", translation: "吃了吗（闽南语）", dialect: "闽南语"),
        Phrase(category: "感谢", text: "唔该", translation: "谢谢（粤语）", dialect: "粤语"),
        Phrase(category: "感谢", text: "谢谢啊", translation: "谢谢你（东北话）", dialect: "东北话"),
        Phrase(category: "感谢", text: "多谢", translation: "谢谢（闽南语）", dialect: "闽南语"),
        Phrase(category: "告别", text: "拜拜", translation: "再见（粤语）", dialect: "粤语"),
        Phrase(category: "告别", text: "回见啊", translation: "再见（东北话）", dialect: "东北话"),
        Phrase(category: "就医", text: "我不舒服", translation: "我身体不舒服", dialect: "普通话"),
        Phrase(category: "就医", text: "哪里疼", translation: "请问哪里疼", dialect: "普通话"),
        Phrase(category: "就医", text: "我要看医生", translation: "我需要看医生", dialect: "普通话"),
        Phrase(category: "购物", text: "多少钱", translation: "这个多少钱", dialect: "普通话"),
        Phrase(category: "购物", text: "便宜点", translation: "能不能便宜一点", dialect: "普通话"),
        Phrase(category: "出行", text: "怎么走", translation: "请问这里怎么走", dialect: "普通话"),
        Phrase(category: "出行", text: "我要去医院", translation: "我想去医院", dialect: "普通话"),
        Phrase(category: "反诈", text: "我先问一下家里人", translation: "遇到转账或陌生电话时先核实", dialect: "普通话"),
        Phrase(category: "反诈", text: "我不转账", translation: "不向陌生人转账汇款", dialect: "普通话"),
    ]
}

// MARK: - 方言数据

struct DialectInfo {
    let name: String
    let region: String
    let appleLocale: String   // 对应 Apple Speech 识别语言代码
}

enum Dialects {
    static let all: [DialectInfo] = [
        DialectInfo(name: "普通话",  region: "全国",       appleLocale: "zh-CN"),
        DialectInfo(name: "粤语",    region: "广东/香港",   appleLocale: "zh-HK"),
        DialectInfo(name: "四川话",  region: "四川/重庆",   appleLocale: "zh-CN"),
        DialectInfo(name: "东北话",  region: "东北三省",     appleLocale: "zh-CN"),
        DialectInfo(name: "闽南语",  region: "福建/台湾",   appleLocale: "zh-TW"),
        DialectInfo(name: "客家话",  region: "粤东/赣南/闽西", appleLocale: "zh-CN"),
    ]

    static var names: [String] { all.map(\.name) }

    static func locale(for name: String) -> String {
        all.first(where: { $0.name == name })?.appleLocale ?? "zh-CN"
    }
}
