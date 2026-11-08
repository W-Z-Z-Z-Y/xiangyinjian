import Foundation

/// 离线高频词库（断网兜底 / API 未接入时使用）
///
/// 结构：标准说法（普通话）-> [方言名: 该方言说法]
/// 按生活场景分组，便于后续维护和扩充。
///
/// 说明：方言写法采用常见、广为接受的表达，正式发布前建议请各方言
/// 母语者校对一遍。粤语资料最完整，闽南语 / 东北话 / 四川话 / 客家话
/// 部分词条为通用近似写法。
enum LocalDictionary {

    /// 词条总表（合并所有场景）
    static let entries: [String: [String: String]] = {
        var all: [String: [String: String]] = [:]
        for group in [greetings, daily, family, medical, shoppingTravel] {
            all.merge(group) { current, _ in current }
        }
        return all
    }()

    // MARK: - 文本归一化

    /// 整句首尾可忽略的标点与空白；句子内部标点保留，防止改变含义。
    ///
    /// 用 Unicode 标量显式构造，而不是写成一个字符串字面量——因为要忽略的
    /// 字符里包含引号本身，字面量写法会让引号提前闭合字符串（这是个真实踩过的
    /// 编译错误）。用码点写则完全避免歧义。
    ///
    /// 说明：全角标点在 `normalize` 里已先被 `fullwidthToHalfwidth` 转成半角，
    /// 所以下半段只需列半角形式；上半段保留几个不会转换的补充标点。
    private static let punctuation: CharacterSet = {
        var set = CharacterSet(charactersIn: ",.!?;:\\\"'()<>[]{}~ ")
        // 全角/中文标点（部分不会被 fullwidthToHalfwidth 转换）
        let extra: [UInt32] = [
            0x3002, // 。
            0x3001, // 、
            0xFF0C, // ，
            0xFF01, // ！
            0xFF1F, // ？
            0xFF1B, // ；
            0xFF1A, // ：
            0x201C, 0x201D, // “ ”
            0x2018, 0x2019, // ‘ ’
            0x300C, 0x300D, // 「 」
            0xFF08, 0xFF09, // （ ）
            0x300A, 0x300B, // 《 》
            0x3010, 0x3011, // 【 】
            0x2026, // …
            0x2014, // —
            0xFF5E, // ～
            0x3000, // 全角空格
        ]
        set.insert(charactersIn: String(String.UnicodeScalarView(extra.compactMap(Unicode.Scalar.init))))
        return set
    }()

    /// 归一化：全角转半角 → 去首尾标点和空白 → 小写化。
    /// 中间的分句边界不能去掉，例如“不，是”不能命中“不是”。
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let half = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) {
            s = half
        }
        s = s.trimmingCharacters(in: punctuation.union(.whitespacesAndNewlines))
        return s.lowercased()
    }

    /// 归一化后的词条索引（懒加载，只在首次查词时构建一次）
    private static let normalizedEntries: [String: [String: String]] = {
        var index: [String: [String: String]] = [:]
        for (mandarin, translations) in entries {
            index[normalize(mandarin)] = translations
        }
        return index
    }()

    /// 归一化只用于查词；命中后保留原句的引号、问号和首尾空白。
    private static func preservingSurroundings(of original: String, translation: String) -> String {
        let leading = original.prefix(while: { normalize(String($0)).isEmpty })
        let trailing = original.reversed().prefix(while: { normalize(String($0)).isEmpty }).reversed()
        return String(leading) + translation + String(trailing)
    }

    // MARK: - 查词

    /// 查词（普通话 key → 方言 value）。dialect 为「普通话」时直接返回原文。
    ///
    /// **只做整句归一化匹配，不做部分匹配。**
    ///
    /// 曾经这里做过「最长前缀包含」匹配，想让「我要去医院看病」命中词条
    /// 「我要去医院」。这是个设计错误：命中后返回的是整条词条的译文，
    /// 用户多说的部分会被静默丢掉——「我要去医院看病」会翻成不含「看病」
    /// 的结果。部分匹配必然丢信息，所以宁可判定未命中、交给大模型整句翻译。
    static func lookup(_ text: String, dialect: String) -> String? {
        if dialect == "普通话" { return text }
        let key = normalize(text)
        guard !key.isEmpty, let translation = normalizedEntries[key]?[dialect] else { return nil }
        return preservingSurroundings(of: text, translation: translation)
    }

    /// 反向查词（方言文本 → 普通话）。
    ///
    /// **只做整句归一化匹配，不做部分匹配**——理由同 `lookup`。
    ///
    /// 典型回归案例：词条「吃饭了吗 / 吃饭没得」曾把「你吃饭没得」部分匹配命中，
    /// 返回「吃饭了吗」，凭空丢掉主语「你」。
    static func reverseLookup(dialectText: String, from dialect: String) -> String? {
        if dialect == "普通话" { return dialectText }
        let key = normalize(dialectText)
        guard !key.isEmpty else { return nil }

        for (mandarin, translations) in entries {
            guard let value = translations[dialect] else { continue }
            // 多写法词条「唔该 / 多谢」：任一种写法整句命中即可
            for form in value.components(separatedBy: " / ") where normalize(form) == key {
                return preservingSurroundings(of: dialectText, translation: mandarin)
            }
        }
        // 系统识别可能已经把方言转写为普通话（如“好多钱”→“多少钱”）。
        // 只接受词库中已知的完整普通话句子，未知长句仍交给在线翻译。
        if normalizedEntries[key]?[dialect] != nil {
            return dialectText
        }
        return nil
    }

    /// 在保留所有未知文本的前提下，把已知方言片段替换成普通话。
    ///
    /// 与旧版“部分命中后直接返回整条词典译文”不同，这里只原位替换实际命中的
    /// 片段，未命中的主语、宾语和上下文全部保留，因此不会再出现信息被截断。
    /// 长词优先，避免短词先替换后破坏完整短语。
    static func reverseCorrectingKnownSpans(
        dialectText: String, from dialect: String
    ) -> String? {
        if let exact = reverseLookup(dialectText: dialectText, from: dialect) {
            return exact
        }
        guard dialect != "普通话" else { return dialectText }

        var replacements: [(source: String, target: String)] = []
        for (mandarin, translations) in entries {
            guard let value = translations[dialect] else { continue }
            for form in value.components(separatedBy: " / ") {
                let source = form.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty,
                      source != mandarin,
                      canReplaceAsPartialSpan(source, dialect: dialect) else { continue }
                replacements.append((source, mandarin))
            }
        }
        replacements.sort {
            if $0.source.count == $1.source.count { return $0.source < $1.source }
            return $0.source.count > $1.source.count
        }

        var output = dialectText
        var changed = false
        for replacement in replacements where output.contains(replacement.source) {
            let updated = output.replacingOccurrences(
                of: replacement.source, with: replacement.target
            )
            if updated != output {
                output = updated
                changed = true
            }
        }
        return changed ? output : nil
    }

    /// 部分替换中的普通单字极易误命中已被 ASR 规范化的普通话句子。
    /// 例如闽南语词条“是 → 是的”曾把“就是白痴”改成“就是的白痴”。
    /// 多字短语可以安全参与匹配；单字只允许辨识度较高的方言字。
    private static func canReplaceAsPartialSpan(_ source: String, dialect: String) -> Bool {
        guard source.count == 1 else { return true }

        let distinctiveCharacters: [String: Set<String>] = [
            "粤语": ["唔", "冇", "佢", "喺", "咗", "嘅", "啲", "咩", "睇", "搵", "返"],
            "闽南语": ["汝", "伊", "阮", "恁", "毋", "袂", "伫", "厝"],
            "东北话": ["啥", "咋"],
            "四川话": [],
            "客家话": ["涯", "汝", "佢", "毋"],
        ]
        return distinctiveCharacters[dialect, default: []].contains(source)
    }

    /// 当前收录的词条数量（设置页 / 调试可用）
    static var count: Int { entries.count }

    // MARK: - 场景：问候
    private static let greetings: [String: [String: String]] = [
        "你好":     ["粤语": "你好", "闽南语": "汝好", "东北话": "你好呀", "四川话": "你好哇", "客家话": "你好"],
        "谢谢":     ["粤语": "唔该 / 多谢", "闽南语": "多谢", "东北话": "谢谢啊", "四川话": "谢了", "客家话": "多谢"],
        "再见":     ["粤语": "拜拜 / 再见", "闽南语": "再会", "东北话": "回见啊", "四川话": "走了哈", "客家话": "再会"],
        "对不起":   ["粤语": "对唔住", "闽南语": "歹势", "东北话": "对不住啊", "四川话": "对不起", "客家话": "对唔住"],
        "没关系":   ["粤语": "冇关系 / 唔紧要", "闽南语": "无要紧", "东北话": "没事儿", "四川话": "没得啥子", "客家话": "无要紧"],
        "请问":     ["粤语": "请问", "闽南语": "请问", "东北话": "问一下", "四川话": "请问哈", "客家话": "请问"],
        "麻烦你了": ["粤语": "麻烦你", "闽南语": "麻烦汝", "东北话": "麻烦你了哈", "四川话": "麻烦你了哈", "客家话": "麻烦你了"],
    ]

    // MARK: - 场景：日常对话
    private static let daily: [String: [String: String]] = [
        "吃饭了吗":     ["粤语": "食咗饭未", "闽南语": "食饭未", "东北话": "吃了没", "四川话": "吃饭没得", "客家话": "食饭无"],
        "你叫什么名字": ["粤语": "你叫咩名", "闽南语": "汝叫啥物名", "东北话": "你叫啥名", "四川话": "你喊啥子名字", "客家话": "你叫么介名字"],
        "多少钱":       ["粤语": "几多钱", "闽南语": "偌济钱", "东北话": "多少钱啊", "四川话": "好多钱", "客家话": "几多钱"],
        "现在几点":     ["粤语": "而家几点", "闽南语": "这马几点", "东北话": "现在几点了", "四川话": "现在几点", "客家话": "当昼几时"],
        "我听不懂":     ["粤语": "我听唔明", "闽南语": "我听无", "东北话": "我听不明白", "四川话": "我听不懂", "客家话": "我听唔懂"],
        "好的":         ["粤语": "好㗎 / 得", "闽南语": "好啊", "东北话": "行啊", "四川话": "要得", "客家话": "好哦"],
        "是的":         ["粤语": "系", "闽南语": "是", "东北话": "是啊", "四川话": "对头", "客家话": "系哦"],
        "不是":         ["粤语": "唔系", "闽南语": "毋是", "东北话": "不是", "四川话": "不是", "客家话": "毋系"],
        "哪里":         ["粤语": "边度", "闽南语": "佗位", "东北话": "哪儿", "四川话": "哪儿", "客家话": "奈位"],
        "什么":         ["粤语": "咩 / 乜嘢", "闽南语": "啥物", "东北话": "啥", "四川话": "啥子", "客家话": "么介"],
        "为什么":       ["粤语": "点解", "闽南语": "是按怎", "东北话": "为啥", "四川话": "为啥子", "客家话": "做么介"],
        "等一下":       ["粤语": "等阵", "闽南语": "等咧", "东北话": "等会儿", "四川话": "等哈儿", "客家话": "等一下"],
    ]

    // MARK: - 场景：家庭 / 称呼
    private static let family: [String: [String: String]] = [
        "爸爸": ["粤语": "爸爸 / 老豆", "闽南语": "阿爸", "东北话": "爸 / 老爸", "四川话": "老汉儿", "客家话": "阿爸"],
        "妈妈": ["粤语": "妈妈 / 老母", "闽南语": "阿母", "东北话": "妈 / 老妈", "四川话": "妈妈", "客家话": "阿姆"],
        "孩子": ["粤语": "细路 / 仔女", "闽南语": "囡仔", "东北话": "孩子 / 娃儿", "四川话": "娃儿", "客家话": "细人仔"],
        "吃":   ["粤语": "食", "闽南语": "食", "东北话": "吃", "四川话": "吃", "客家话": "食"],
        "喝":   ["粤语": "饮", "闽南语": "啉", "东北话": "喝", "四川话": "喝", "客家话": "饮"],
        "回家": ["粤语": "返屋企", "闽南语": "转去厝", "东北话": "回家", "四川话": "回屋头", "客家话": "转屋下"],
    ]

    // MARK: - 场景：就医
    private static let medical: [String: [String: String]] = [
        "我不舒服": ["粤语": "我唔舒服", "闽南语": "我无爽快", "东北话": "我不舒坦", "四川话": "我不安逸", "客家话": "我无舒服"],
        "哪里疼":   ["粤语": "边度痛", "闽南语": "佗位疼", "东北话": "哪儿疼", "四川话": "哪儿痛", "客家话": "奈位痛"],
        "头疼":     ["粤语": "头痛", "闽南语": "头壳疼", "东北话": "头疼", "四川话": "脑壳痛", "客家话": "头拿痛"],
        "看医生":   ["粤语": "睇医生", "闽南语": "看医生", "东北话": "看大夫", "四川话": "看医生", "客家话": "看医生"],
        "吃药":     ["粤语": "食药", "闽南语": "食药仔", "东北话": "吃药", "四川话": "吃药", "客家话": "食药"],
        "我要看医生": ["粤语": "我要睇医生", "闽南语": "我欲看医生", "东北话": "我要看大夫", "四川话": "我要看医生", "客家话": "涯想看医生"],
        "请帮我叫救护车": ["粤语": "请帮我叫白车", "闽南语": "请帮我叫救护车", "东北话": "帮我叫个救护车呗", "四川话": "请帮我叫救护车", "客家话": "请帮涯叫救护车"],
        "我有高血压": ["粤语": "我有高血压", "闽南语": "我有高血压", "东北话": "我有高血压", "四川话": "我有高血压", "客家话": "涯有高血压"],
        "我对这个药过敏": ["粤语": "我对呢只药敏感", "闽南语": "我对这款药会过敏", "东北话": "我对这个药过敏", "四川话": "我对这个药过敏", "客家话": "涯对这款药会过敏"],
    ]

    // MARK: - 场景：购物 / 出行
    private static let shoppingTravel: [String: [String: String]] = [
        "怎么走":   ["粤语": "点行", "闽南语": "按怎行", "东北话": "咋走", "四川话": "咋个走", "客家话": "行奈条路"],
        "太贵了":   ["粤语": "太贵啦", "闽南语": "傷贵", "东北话": "太贵了", "四川话": "太贵咯", "客家话": "忒贵了"],
        "便宜点":   ["粤语": "平啲啦", "闽南语": "较俗咧", "东北话": "便宜点呗", "四川话": "便宜点", "客家话": "便宜滴"],
        "我要这个": ["粤语": "我要呢个", "闽南语": "我欲这个", "东北话": "我要这个", "四川话": "我要这个", "客家话": "涯爱这个"],
        "我要去医院": ["粤语": "我要去医院", "闽南语": "我欲去医院", "东北话": "我要去医院", "四川话": "我要去医院", "客家话": "涯想去医院"],
        "请问公交站在哪里": ["粤语": "请问巴士站喺边度", "闽南语": "请问公车站伫佗位", "东北话": "问一下公交站在哪儿", "四川话": "请问公交站在哪儿", "客家话": "请问公车站伫奈位"],
        "请慢一点说": ["粤语": "请讲慢啲", "闽南语": "请讲较慢咧", "东北话": "请说慢点", "四川话": "请说慢点", "客家话": "请讲慢滴"],
        "我先问一下家里人": ["粤语": "我先问下屋企人", "闽南语": "我先问厝里人", "东北话": "我先问问家里人", "四川话": "我先问哈屋头人", "客家话": "涯先问下屋下人"],
        "我不转账": ["粤语": "我唔转账", "闽南语": "我毋转账", "东北话": "我不转账", "四川话": "我不得转账", "客家话": "涯毋转账"],
    ]
}
