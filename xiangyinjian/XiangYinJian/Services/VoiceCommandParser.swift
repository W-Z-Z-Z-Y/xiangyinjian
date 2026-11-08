import Foundation

/// 只执行完整的单条本地指令；翻译正文和联系人保留用户原文。
nonisolated enum VoiceCommandParser {
    private static let ending = "(?:一下|好吗|可以吗|谢谢|唔该|吧|呀|呢|嘛|哈|啦|喔|哦|啊|了){0,3}[。！？!?，,]*"
    private static let font = "(?:字体|文字|字号|字)"
    private static let amount = "(?:一点儿|一点|一些|点儿|些|点|啲)"
    static let intentPatterns: [(String, String)] = [
        ("font_smaller", "(?:把|将)?\(font)(?:给我)?(?:再|稍微)?(?:(?:弄|整|调|变|改)(?:成)?小(?:\(amount))?|缩小(?:\(amount))?|小\(amount)|太大)|(?:缩小|调小)(?:\(amount))?(?:一下)?\(font)"),
        ("font_larger", "(?:把|将)?\(font)(?:给我)?(?:再|稍微)?(?:(?:弄|整|调|变|改)(?:成)?大(?:\(amount))?|放大(?:\(amount))?|大\(amount)|太小|看不清)(?:了?[，,]?(?:我)?看不清)?|(?:放大|调大)(?:\(amount))?(?:一下)?\(font)|(?:我)?看不清(?:楚)?(?:这里的)?\(font)"),
        ("voice_male", "(?:(?:换|改|切换)(?:成|为|到|个|一个)?|用|使用|想听|听|来(?:个|一个))?(?:男声|男音|男生|男人(?:的)?声音|男的声音|男士(?:的)?声音)(?:朗读|读)?"),
        ("voice_female", "(?:(?:换|改|切换)(?:成|为|到|个|一个)?|用|使用|想听|听|来(?:个|一个))?(?:女声|女音|女生|女人(?:的)?声音|女的声音|女士(?:的)?声音)(?:朗读|读)?"),
        ("speed_slower", "(?:语速|(?:声音)?(?:读|说|讲|念)(?:话|得)?|声音)(?:再|稍微)?(?:放|调|整)?(?:慢\(amount)|太快|快了)|慢\(amount)(?:读|说|讲|念)?|(?:放慢|调慢)(?:语速)?"),
        ("speed_faster", "(?:语速|(?:声音)?(?:读|说|讲|念)(?:话|得)?|声音)(?:再|稍微)?(?:放|调|整)?(?:快\(amount)|太慢|慢了)|快\(amount)(?:读|说|讲|念)?|(?:加快|调快)(?:语速)?"),
        ("stop", "停止(?:朗读|播放|声音)?|暂停(?:朗读|播放)?|安静(?:一点|啲)|停(?:一下|一停|下来)?"),
        ("help", "(?:你)?(?:能|会)(?:说|做|干)?什么|怎么用|怎样用|如何用|怎么操作|指令帮助|语音帮助|(?:都)?有哪些功能"),
        ("home", "(?:回到|返回|回|返|去|带我回)?(?:首页|主页|主页面|主界面)|返回|回去|返去"),
        ("antiScam", "(?:我)?(?:怕|担心|避免|防止|如何|怎样|怎么)(?:被骗|诈骗|受骗|上当)(?:了)?(?:怎么办)?|防骗方法|防骗知识"),
        ("archive", "(?:想听|听听|听一下|听|找找|找一下|查查|查看|打开)(?:以前录(?:的声音|的录音)?|老录音|收藏的声音|家乡录音|录过的声音)")
    ]
    static let destinationPatterns: [(VoiceDestination, String)] = [
        (.archive, "声音档案馆|声音档案|档案馆|录音档案|老录音|以前录的声音|家乡录音"),
        (.antiScam, "防诈助手|反诈助手|防诈骗|防骗|反诈|防诈"),
        (.history, "历史记录|翻译历史|翻译记录|之前的翻译|以前的翻译|以前翻译"),
        (.voiceCards, "声音卡片|语音卡片|声卡片"),
        (.storybook, "乡音绘本|方言绘本|绘本|故事书"),
        (.phrases, "常用语|常用句|日常用语|常用的话"),
        (.dualDialect, "双向对话|面对面互译|面对面翻译|双人对话|两个人对话|面对面会议"),
        (.settings, "设置|设定|偏好"), (.tools, "常用功能|功能|工具"), (.memory, "记忆|回忆")
    ]

    static func parse(_ text: String) -> VoiceCommand? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        var value = raw
        for _ in 0..<8 {
            let normalized = commandText(value)
            guard let prefix = ["你好小助手", "你好", "您好", "小助手", "可以帮我", "麻烦帮我", "请帮我",
                                "我想要", "我想", "我要", "能不能", "可不可以", "请你", "帮我", "帮忙", "麻烦你", "麻烦", "劳驾", "请"]
                .first(where: normalized.hasPrefix) else { break }
            value.removeFirst(prefix.count)
            value = String(value.drop(while: { $0.isWhitespace || "，,：:".contains($0) }))
        }
        // “翻译页面”是页面名；“翻译：页面”仍是要翻译的原文。
        if matchesWhole("翻译页(?:面)?|方言翻译(?:页(?:面)?)?", value) { return .goHome }
        // 先提取明确的翻译正文，正文中的否定、页面名、电话号码不能触发操作。
        if let content = capture("^(?:(?:给我|替我)?翻译(?:一下|下|哈)?|这句话(?:用普通话)?怎么说)[\\s，,：:]*(.*)$", in: value) {
            return .translate(content.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if matchesWhole("别读了|别说了|不要再读(?:了)?|不要再说(?:了)?|不要(?:朗读|播放)(?:了)?|别(?:朗读|播放)(?:了)?|唔好再?(?:读|讲|播)(?:喇|啦)?", value) {
            return .stopPlayback
        }
        // 保留“看不清”，但否定、取消、同时操作或二选一都不得执行第一项。
        if matches("不要|不想|不用|不必|不需要|不准|不(?:打开|开启|进入|播放|放|来|听|看|读|说|讲|念|打|拨|换|改|调|去|切换|翻译|缩小|停)|(?<![特识分区告个离])别|莫|勿|甭|唔好|唔使|咪|取消|然后|接着|同时|并且|顺便|或者|还是", value) {
            return .unknown(raw)
        }
        let intents = intentPatterns.filter { matchesWhole($0.1, value) }
        if intents.count == 1, let command = command(for: intents[0].0) { return command }
        if intents.count > 1 { return .unknown(raw) }

        let opening = "(?:打开|开启|进入|看看|看一下|看下|查看|看|查一下|查查|找找|找一下|去|听听|听一下|用一下|使用|切换到|换到|切到|想看|要看|想用|要用|想打开|想找)"
        let navigationPrefix = "(?:\(opening)(?:一下|下|哈)?(?:这个|那个|我的)?)?"
        if matchesWhole("\(navigationPrefix)(?:翻译|方言翻译)(?:页|页面|界面|功能)?", value) {
            return .goHome
        }
        let destinations = destinationPatterns.filter {
            matchesWhole("\(navigationPrefix)(?:\($0.1))(?:页|页面|界面|功能)?", value)
        }
        if destinations.count == 1 { return .navigate(destinations[0].0) }
        if destinations.count > 1 { return .unknown(raw) }

        let actions: [(String, (String) -> VoiceCommand)] = [
            ("(?:微信视频(?:通话)?|视频通话|打(?:个|一个|通|一通)?(?:微信)?视频(?:电话)?)", { .videoCall($0) }),
            ("(?:打(?:个|一个|通|一通)?电话|拨(?:个|一下)?电话)", { .call($0) })
        ]
        for (verb, action) in actions {
            if matchesWhole(verb, value) { return action("") }
            let patterns = [
                "^(?:给|向|跟|同|和)(.+?)\(verb)\(ending)$",
                "^\(verb)(?:给|找|联系|畀)(.+?)\(ending)$"
            ]
            for pattern in patterns {
                guard let captured = capture(pattern, in: value) else { continue }
                let name = captured.trimmingCharacters(in: .whitespacesAndNewlines)
                guard matches("^[\\p{L}\\p{N}·・ ]{1,40}$", name),
                      !matches("然后|接着|同时|并且|顺便|或者|还是|和|或|再|给|打电话|视频|打开|翻译|取消", name) else {
                    return .unknown(raw)
                }
                return action(name)
            }
        }
        return .unknown(raw)
    }

    static func command(for intent: String) -> VoiceCommand? {
        switch intent {
        case "font_larger": return .fontSize(0.1)
        case "font_smaller": return .fontSize(-0.1)
        case "voice_male": return .voiceGender(true)
        case "voice_female": return .voiceGender(false)
        case "speed_slower": return .speechSpeed(-0.05)
        case "speed_faster": return .speechSpeed(0.05)
        case "stop": return .stopPlayback
        case "help": return .help
        case "home": return .goHome
        case "antiScam": return .navigate(.antiScam)
        case "archive": return .navigate(.archive)
        default: return nil
        }
    }

    private static func matchesWhole(_ pattern: String, _ text: String) -> Bool {
        matches("^(?:\(pattern))\(ending)$", text)
    }
    private static func matches(_ pattern: String, _ text: String) -> Bool {
        commandText(text).range(of: pattern, options: .regularExpression) != nil
    }
    private static func capture(_ pattern: String, in text: String) -> String? {
        let normalized = commandText(text)
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = expression.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    private static func commandText(_ text: String) -> String {
        // 只统一指令用字，逐字等长替换，使捕获位置仍对应原始正文和联系人。
        let traditional = "幫開設講換聲體語頁請聽譯這話嗎謝來讀說點兒個給與電話視頻聯繫錄檔館歷記憶鄉畫雙對詐騙麼樣舊調將為進關閉別時還擔裡讓啟"
        let simplified  = "帮开设讲换声体语页请听译这话吗谢来读说点儿个给与电话视频联系录档馆历记忆乡画双对诈骗么样旧调将为进关闭别时还担里让启"
        let replacements = Dictionary(zip(traditional, simplified), uniquingKeysWith: { first, _ in first })
        return String(text.map { replacements[$0] ?? $0 })
    }
}
