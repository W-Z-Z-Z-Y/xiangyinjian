import Foundation

/// 方言词表与双向范例，帮助模型结合语境理解和表达，允许保留通用写法。
/// 词表与 `LocalDictionary` 的口径保持一致；如需补充，两处同步修改。
struct DialectGuide {

    let name: String
    /// 该方言最典型的语法特征（一句话）
    let grammarNote: String
    /// 高频术语：代词 / 否定 / 助词 / 常用词
    let glossary: [(String, String)]
    /// few-shot 范例（普通话 → 方言）
    let examples: [(String, String)]
    /// 在适当语境下可优先换成方言表达的普通话用词。
    let avoid: [String]

    /// 普通话 → 方言时使用的提示段。
    var promptSectionToDialect: String {
        var lines: [String] = []
        lines.append("【\(name)】")
        if !grammarNote.isEmpty {
            lines.append("特征：\(grammarNote)")
        }
        if !glossary.isEmpty {
            let pairs = glossary.map { "\($0.0)→\($0.1)" }.joined(separator: "，")
            lines.append("常用词参考（结合语境使用，不机械替换）：\(pairs)")
        }
        if !avoid.isEmpty {
            lines.append("这些普通话用词可按语境使用相应方言表达：\(avoid.joined(separator: "、"))。保留专名、引用和本来就通用的说法。")
        }
        if !examples.isEmpty {
            lines.append("范例：")
            for (mandarin, dialect) in examples {
                lines.append("  普通话：\(mandarin)\n  \(name)：\(dialect)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 方言 → 普通话时使用的反向提示段。
    ///
    /// 不能复用 `promptSectionToDialect`：其中的“优先使用方言词”和
    /// “避开普通话用词”会与目标方向冲突，诱导模型把结果重新写成方言。
    var promptSectionToMandarin: String {
        var lines: [String] = []
        lines.append("【\(name) → 普通话对照】")
        if !grammarNote.isEmpty {
            lines.append("输入特征（仅用于理解原文，不得照搬到译文）：\(grammarNote)")
        }
        if !glossary.isEmpty {
            let pairs = glossary.map { "\($0.1)→\($0.0)" }.joined(separator: "，")
            lines.append("方言词对应普通话（输出右侧普通话说法）：\(pairs)")
        }
        if !examples.isEmpty {
            lines.append("反向翻译范例：")
            for (mandarin, dialect) in examples {
                lines.append("  \(name)：\(dialect)\n  普通话：\(mandarin)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 各方言词表

extension DialectGuide {

    static func guide(for dialect: String) -> DialectGuide? {
        switch dialect {
        case "粤语":   return cantonese
        case "四川话": return sichuan
        case "东北话": return dongbei
        case "闽南语": return minnan
        case "客家话": return hakka
        default:      return nil
        }
    }

    static let cantonese = DialectGuide(
        name: "粤语",
        grammarNote: "否定用「唔」，没有用「冇」，在/正在用「喺」，完成体用「咗」，复数人称加「哋」，领属用「嘅」",
        glossary: [
            ("我", "我"), ("你", "你"), ("他/她", "佢"),
            ("我们", "我哋"), ("你们", "你哋"), ("他们", "佢哋"),
            ("不", "唔"), ("没有", "冇"), ("是", "系"), ("在", "喺"),
            ("的", "嘅"), ("了", "咗"), ("一点/些", "啲"),
            ("吃", "食"), ("喝", "饮"), ("回家", "返屋企"),
            ("什么", "咩"), ("为什么", "点解"), ("哪里", "边度"),
            ("多少", "几多"), ("谢谢", "唔该"), ("对不起", "对唔住"),
        ],
        examples: [
            ("你吃饭了吗", "你食咗饭未"),
            ("我现在要回家", "我而家要返屋企"),
            ("我不知道他去哪里了", "我唔知佢去咗边度"),
        ],
        avoid: ["别", "没", "的", "咱们", "啥"]
    )

    static let sichuan = DialectGuide(
        name: "四川话",
        grammarNote: "疑问用「啥子 / 咋个」，否定用「莫得」，程度副词用「好」；句末常加「哈 / 哦 / 嘛」软化语气",
        glossary: [
            ("我", "我"), ("你", "你"), ("他/她", "他"),
            ("你们", "你们"), ("什么", "啥子"), ("怎么", "咋个"),
            ("没有", "莫得"), ("不要", "莫"), ("很/非常", "好"),
            ("舒服/好", "巴适"), ("可怜/差", "造孽"), ("聊天", "摆龙门阵"),
            ("知道", "晓得"), ("便宜", "相因"), ("聊天", "摆谈"),
            ("一会儿", "哈儿"), ("一起", "一路"), ("吃饭了吗", "吃饭没得"),
        ],
        examples: [
            ("你吃饭了吗", "你吃饭没得"),
            ("这个多少钱", "这个好多钱"),
            ("我不知道怎么办", "我不晓得咋个办"),
        ],
        avoid: ["什么", "没有", "怎么", "的"]
    )

    static let dongbei = DialectGuide(
        name: "东北话",
        grammarNote: "语音接近普通话，方言味主要体现在词汇和语气上；常用「咋 / 整 / 老 / 贼」",
        glossary: [
            ("我", "俺"), ("你", "你"), ("什么", "啥"), ("怎么", "咋"),
            ("非常", "贼 / 老"), ("做/弄", "整"), ("聊天", "唠嗑"),
            ("知道", "知道"), ("喜欢", "稀罕"), ("脏", "埋汰"),
            ("啰嗦/慢", "磨叽"), ("地方", "旮旯"), ("聊天", "唠嗑儿"),
            ("是的", "嗯哪"), ("那当然", "那可不"),
        ],
        examples: [
            ("你去哪儿", "你上哪儿去"),
            ("这个真的很好吃", "这玩意儿贼拉好吃"),
            ("我不知道怎么办", "我咋整啊，不知道咋办"),
        ],
        avoid: ["非常", "特别"]
    )

    /// 闽南语写法用「通行俗字」（汝、厝、伫 这类），不用罗马拼音——
    /// 目标用户是看惯汉字的老人，拼音写法他们读不出来。
    static let minnan = DialectGuide(
        name: "闽南语",
        grammarNote: "人称用「汝 / 伊」，否定用「无 / 毋 / 袂」，表存在用「伫」，所属用「的」但常省略",
        glossary: [
            ("你", "汝"), ("他/她", "伊"), ("我们", "阮"), ("你们", "恁"),
            ("他们", "亻因"), ("不", "毋"), ("没有", "无"), ("不会", "袂"),
            ("在", "伫"), ("家", "厝"), ("吃", "食"), ("喝", "啉"),
            ("走/跑", "走"), ("什么", "啥物"), ("怎么", "按怎"),
            ("哪里", "佗位"), ("多少", "偌济"), ("谢谢", "多谢"),
            ("对不起", "歹势"), ("大家", "逐家"),
        ],
        examples: [
            ("你吃饭了吗", "汝食饭未"),
            ("我不知道", "我毋知"),
            ("他回家了", "伊转去厝矣"),
        ],
        avoid: ["不", "没有", "我们", "你们", "的"]
    )

    static let hakka = DialectGuide(
        name: "客家话",
        grammarNote: "第一人称用「涯」，复数加「兜」（涯兜 / 汝兜），否定用「毋」，家说「屋下」",
        glossary: [
            ("我", "涯"), ("你", "汝"), ("他/她", "佢"),
            ("我们", "涯兜"), ("你们", "汝兜"), ("他们", "佢兜"),
            ("不", "毋"), ("没有", "无"), ("是", "系"),
            ("吃", "食"), ("喝", "饮"), ("家", "屋下"), ("回家", "转屋下"),
            ("什么", "么介"), ("怎么", "仰般"), ("为什么", "做么介"),
            ("哪里", "奈位"), ("多少", "几多"), ("谢谢", "多谢"),
            ("孩子", "细人仔"), ("做饭", "煮食"),
        ],
        examples: [
            ("你吃饭了吗", "汝食饭无"),
            ("我要回家", "涯爱转屋下"),
            ("我不知道", "涯毋知"),
        ],
        avoid: ["不", "没有", "的", "我们", "你们"]
    )
}
