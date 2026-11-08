import SwiftUI
import AVFoundation

// MARK: - 录音音量包络
//
// 老人按下录音后最大的焦虑是「它到底听见我没有」。波形跟着说话声起伏，
// 这一下就把「它在听」讲清楚了，比任何文字提示都直接。

extension AVAudioPCMBuffer {
    /// 当前缓冲区的响度，归一化到 0...1。
    ///
    /// RMS 转 dBFS 后线性映射：低于 -55dBFS 视为静音（归零），
    /// 高于 -5dBFS 视为满格。这两个阈值是说话距离手机 20~30cm 的常见区间，
    /// 落在区间外的会被 clamp，不会让波形打满或完全不动。
    func normalizedLevel() -> Float {
        guard let channel = floatChannelData?[0], frameLength > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<Int(frameLength) {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))

        let floorDB: Float = -55
        let ceilDB: Float = -5
        let db = 20 * log10(max(rms, 1e-7))
        return min(max((db - floorDB) / (ceilDB - floorDB), 0), 1)
    }
}

// MARK: - 录音波形

/// 录音中的实时波形。
///
/// 每根柱子对应音量历史里的一个采样点（history[0] 是最旧的、画在最左边，
/// 最新的画在最右边），再叠一个该柱子的固定随机权重，让相邻柱子高低错落，
/// 更像真实波形而不是一条平滑的包络线。
/// 历史数组只保留最近 barCount 帧，新值进来旧值挤出，视觉上就是声音从右往左流过。
///
/// 尺寸通过参数暴露，翻译页的宽卡片和左下角悬浮按钮共用这一个组件。
struct AudioWaveformView: View {
    let level: Double
    let color: Color
    var barCount: Int = 24
    var maxHeight: CGFloat = 36
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3

    /// 最近若干帧的音量，最新的在末尾
    @State private var history: [Double] = []
    /// 固定一组随机权重，避免每帧重算导致的闪烁
    @State private var seeds: [Double] = []

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: barHeight(at: index))
            }
        }
        .frame(maxWidth: .infinity, minHeight: maxHeight)
        .onAppear {
            if seeds.isEmpty { seeds = (0..<barCount).map { _ in Double.random(in: 0.35...1.0) } }
            if history.isEmpty { history = Array(repeating: 0, count: barCount) }
        }
        .onChange(of: level) { _, newLevel in
            // 音量一帧一格地向左滚动，形成流动感
            history.append(newLevel)
            if history.count > barCount { history.removeFirst(history.count - barCount) }
        }
        .accessibilityHidden(true)
    }

    private func barHeight(at index: Int) -> CGFloat {
        let value = index < history.count ? history[index] : 0
        let seed = index < seeds.count ? seeds[index] : 0.6
        // 下限 3pt：静音时也留一条细线，让用户知道波形还在工作而不是卡死了
        let height = maxHeight * CGFloat(value) * CGFloat(seed)
        return max(3, height)
    }
}

// MARK: - 环形录音波形
//
// 语音助手页的麦克风是个大圆，横条波形塞不进去——横条会盖住麦克风图标，
// 也会让按钮看起来像长了毛。改成绕着圆一圈的短刺：每根刺的长度由音量历史
// 的一个采样点决定，从正上方开始顺时针排布，历史推进时像声波一圈圈荡开。
//
// 用 Canvas 而不是 ForEach + 多个 Shape：每帧要重画几十根刺的三角函数，
// Canvas 是单个绘制层、没有视图身份开销，25fps 下明显更轻。

struct RingAudioWaveformView: View {
    let level: Double
    var color: Color
    /// 刺的基准半径，通常就等于所环绕圆形视图的半径
    var baseRadius: CGFloat = 36
    /// 相邻两根刺之间留出的弧长。刺的间距恒定，圈越大刺越多，
    /// 这样大圆小圆看起来疏密一致——固定刺数量会让小圆糊成一圈、大圆稀稀拉拉。
    /// 20pt 是「一根刺看得清、又不至于断开成一圈点」的折中，老人看得更清楚。
    var spikeSpacing: CGFloat = 20
    var minLength: CGFloat = 2
    var maxLength: CGFloat = 16
    var lineWidth: CGFloat = 3

    @State private var history: [Double] = []

    /// 按周长算刺的数量，并夹在一个合理区间内：
    /// 下限 16 保证小圆也看得出「一圈」的形状，上限 48 避免大圆上刺细到看不见。
    private var spikeCount: Int {
        let circumference = 2 * .pi * baseRadius
        let count = Int(circumference / spikeSpacing)
        return min(max(count, 16), 48)
    }

    private var canvasSide: CGFloat { (baseRadius + maxLength) * 2 }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let count = spikeCount

            for index in 0..<count {
                // -90° 起画，即正上方
                let angle = (Double(index) / Double(count)) * 2 * .pi - .pi / 2
                let value = index < history.count ? history[index] : 0
                let length = minLength + (maxLength - minLength) * CGFloat(value)

                let inner = CGPoint(
                    x: center.x + cos(angle) * baseRadius,
                    y: center.y + sin(angle) * baseRadius
                )
                let outer = CGPoint(
                    x: center.x + cos(angle) * (baseRadius + length),
                    y: center.y + sin(angle) * (baseRadius + length)
                )

                var path = Path()
                path.move(to: inner)
                path.addLine(to: outer)

                // 越长的刺越醒目，弱音时自然淡出，而不是靠透明度整体呼吸
                let opacity = 0.35 + 0.65 * Double(value)
                context.stroke(
                    path,
                    with: .color(color.opacity(opacity)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
        .frame(width: canvasSide, height: canvasSide)
        .allowsHitTesting(false)
        .onAppear {
            if history.isEmpty { history = Array(repeating: 0, count: spikeCount) }
        }
        .onChange(of: level) { _, newLevel in
            history.append(newLevel)
            // 半径变化导致刺数量变化时，同步调整历史长度，避免数组越界或残留旧值
            if history.count > spikeCount {
                history.removeFirst(history.count - spikeCount)
            } else if history.count < spikeCount {
                history = Array(repeating: 0, count: spikeCount - history.count) + history
            }
        }
        .accessibilityHidden(true)
    }
}

struct PulsingEffect: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            // 开启「减弱动态效果」时不缩放，只保留轻微的透明度呼吸
            .scaleEffect(reduceMotion ? 1.0 : (pulsing ? 1.15 : 1.0))
            .opacity(pulsing ? 0.7 : 1.0)
            .animation(
                isActive
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing
            )
            .onAppear {
                if isActive { pulsing = true }
            }
            .onChange(of: isActive) {
                pulsing = isActive
            }
    }
}

struct ScamWarning {
    let messageKey: String
    let tipKey: String?
    let level: ScamRiskLevel

    var message: String { LanguageManager.shared.tr(messageKey) }
    var tip: String? { tipKey.map { LanguageManager.shared.tr($0) } }
}

enum ScamRiskLevel {
    case normal
    case high
}

struct QuickTranslationScene: Identifiable {
    let id = UUID()
    let titleKey: String
    let icon: String
    let text: String

    func localizedTitle(_ lang: LanguageManager) -> String {
        lang.tr(titleKey)
    }

    static let all: [QuickTranslationScene] = [
        QuickTranslationScene(titleKey: "scene.medical",   icon: "cross.case.fill",        text: "我要看医生"),
        QuickTranslationScene(titleKey: "scene.direction", icon: "map.fill",               text: "请问公交站在哪里"),
        QuickTranslationScene(titleKey: "scene.shopping",  icon: "cart.fill",              text: "多少钱"),
        QuickTranslationScene(titleKey: "scene.cantHear",  icon: "hearingdevice.and.signal.meter", text: "请慢一点说"),
        QuickTranslationScene(titleKey: "scene.askFamily", icon: "person.2.fill",          text: "我先问一下家里人"),
    ]
}

struct FamilyGreetingItem: Identifiable {
    let id = UUID()
    let icon: String
    let textKey: String
    let text: String

    static let all: [FamilyGreetingItem] = [
        FamilyGreetingItem(icon: "heart.fill", textKey: "familyGreeting.safe", text: "我在外面很好，不用担心"),
        FamilyGreetingItem(icon: "heart", textKey: "familyGreeting.miss", text: "我想你了"),
        FamilyGreetingItem(icon: "hands.sparkles", textKey: "familyGreeting.care", text: "天气变了，注意保暖"),
        FamilyGreetingItem(icon: "phone", textKey: "familyGreeting.call", text: "有空给我打个电话"),
        FamilyGreetingItem(icon: "fork.knife", textKey: "familyGreeting.eat", text: "吃饭了吗，注意按时吃饭"),
    ]
}

enum ScamDetector {
    private static let rules: [(keywords: [String], messageKey: String, tipKey: String, level: ScamRiskLevel)] = [
        (
            keywords: ["安全账户", "资金转移", "配合调查", "涉嫌洗钱", "涉嫌诈骗", "公安局", "检察院", "法院", "警察"],
            messageKey: "scam.msg.gov",
            tipKey: "scam.tip.gov",
            level: .high
        ),
        (
            keywords: ["退款", "赔偿", "客服", "屏幕共享", "操作退款", "二维码", "扫码退"],
            messageKey: "scam.msg.refund",
            tipKey: "scam.tip.refund",
            level: .high
        ),
        (
            keywords: ["高回报", "保本", "保息", "内部渠道", "年化", "理财", "投资", "稳赚", "低风险高收益"],
            messageKey: "scam.msg.invest",
            tipKey: "scam.tip.invest",
            level: .high
        ),
        (
            keywords: ["借钱", "急用钱", "出事了", "被抓", "派出所", "保密", "别告诉"],
            messageKey: "scam.msg.family",
            tipKey: "scam.tip.family",
            level: .high
        ),
        (
            keywords: ["领礼品", "免费领", "扫码领", "填身份证", "填手机号", "中奖", "恭喜您获得"],
            messageKey: "scam.msg.gift",
            tipKey: "scam.tip.gift",
            level: .normal
        ),
        (
            keywords: ["转账", "汇款", "打款", "银行卡号", "收款码"],
            messageKey: "scam.msg.transfer",
            tipKey: "scam.tip.transfer",
            level: .high
        ),
    ]

    static func detect(in text: String) -> ScamWarning? {
        for rule in rules {
            if rule.keywords.contains(where: { text.contains($0) }) {
                return ScamWarning(messageKey: rule.messageKey, tipKey: rule.tipKey, level: rule.level)
            }
        }
        return nil
    }
}
