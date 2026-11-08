import AppIntents
import Foundation

// MARK: - 方言选项

enum DialectIntentOption: String, AppEnum {
    case mandarin = "普通话"
    case cantonese = "粤语"
    case sichuan = "四川话"
    case northeast = "东北话"
    case hokkien = "闽南话"
    case hakka = "客家话"

    // 保留已创建快捷指令的原始枚举值，业务层统一使用 App 的方言名称。
    var canonicalName: String { self == .hokkien ? "闽南语" : rawValue }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "方言"

    static var caseDisplayRepresentations: [DialectIntentOption: DisplayRepresentation] = [
        .mandarin: "普通话",
        .cantonese: "粤语",
        .sichuan: "四川话",
        .northeast: "东北话",
        .hokkien: "闽南话",
        .hakka: "客家话",
    ]
}

// MARK: - 翻译 Intent

struct TranslateToDialectIntent: AppIntent {
    static var title: LocalizedStringResource = "翻译方言"
    static var description = IntentDescription("把一句话翻译成指定方言，并用 Siri 朗读出来")
    static var openAppWhenRun = false

    @Parameter(title: "要翻译的内容", requestValueDialog: "您想翻译哪句话？")
    var text: String

    @Parameter(title: "目标方言")
    var dialect: DialectIntentOption?

    static var parameterSummary: some ParameterSummary {
        Summary("把 \(\.$text) 翻译成 \(\.$dialect)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let english = LanguageManager.shared.current == .en
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if english { return .result(dialog: "Please say what you want to translate.") }
            return .result(dialog: "您还没有说要翻译什么内容。")
        }

        let selectedDialect = dialect?.canonicalName
            ?? UserDefaults.standard.string(forKey: "preferredDialect")
            ?? "粤语"
        let targetDialect = selectedDialect == "闽南话" ? "闽南语" : selectedDialect

        let manager = TranslationManager()
        do {
            let result = try await manager.translate(trimmed, from: "普通话", to: targetDialect)
            try Task.checkCancellation()
            let saved = HistoryStore.add(HistoryRecord(sourceText: trimmed,
                                                       translatedText: result,
                                                       dialect: targetDialect))
            guard saved else {
                if english { return .result(dialog: "Translation: \(result). History could not be saved. Please check device storage.") }
                return .result(dialog: "译文是：\(result)。但历史保存失败，请检查设备储存空间。")
            }
            if english {
                let name = LanguageManager.shared.dialectDisplayName(targetDialect)
                return .result(dialog: "In \(name): \(result)")
            }
            return .result(dialog: "\(targetDialect)的说法是：\(result)")
        } catch is CancellationError {
            throw CancellationError()
        } catch TranslationError.notConfigured {
            if english { return .result(dialog: "This phrase is not available offline. Online translation has not been configured.") }
            return .result(dialog: "离线词库暂时没有这句话，在线翻译尚未配置。")
        } catch {
            if english { return .result(dialog: "Translation failed. Please check your connection and try again.") }
            return .result(dialog: "翻译失败了，请检查网络后再试一次。")
        }
    }
}

// MARK: - 导航 Intent

struct OpenDialectTranslatorIntent: AppIntent {
    static var title: LocalizedStringResource = "打开方言翻译"
    static var description = IntentDescription("打开乡音间并进入方言翻译页面")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.requestTab(.translate)
        return .result()
    }
}

struct OpenStorybookIntent: AppIntent {
    static var title: LocalizedStringResource = "打开方言绘本"
    static var description = IntentDescription("打开乡音间并进入方言绘本页面")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.requestTab(.storybook)
        return .result()
    }
}

struct OpenAntiScamIntent: AppIntent {
    static var title: LocalizedStringResource = "打开防诈骗指南"
    static var description = IntentDescription("打开乡音间的防诈骗指南")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.requestTab(.antiScam)
        return .result()
    }
}

// MARK: - 快捷指令短语

struct XiangYinJianShortcuts: AppShortcutsProvider {
    nonisolated static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateToDialectIntent(),
            phrases: [
                "用\(.applicationName)翻译",
                "让\(.applicationName)翻译方言",
                "\(.applicationName)翻译一句",
            ],
            shortTitle: "翻译方言",
            systemImageName: "character.bubble"
        )
        AppShortcut(
            intent: OpenDialectTranslatorIntent(),
            phrases: [
                "打开\(.applicationName)翻译",
                "用\(.applicationName)说话",
            ],
            shortTitle: "方言翻译",
            systemImageName: "waveform.and.mic"
        )
        AppShortcut(
            intent: OpenStorybookIntent(),
            phrases: [
                "用\(.applicationName)讲故事",
                "打开\(.applicationName)绘本",
            ],
            shortTitle: "方言绘本",
            systemImageName: "book"
        )
        AppShortcut(
            intent: OpenAntiScamIntent(),
            phrases: [
                "打开\(.applicationName)防诈骗",
                "\(.applicationName)防诈骗指南",
            ],
            shortTitle: "防诈骗指南",
            systemImageName: "shield.lefthalf.filled"
        )
    }
}
