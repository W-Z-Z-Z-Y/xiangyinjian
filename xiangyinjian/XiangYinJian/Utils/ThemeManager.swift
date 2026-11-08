import SwiftUI
import Combine
import AVFoundation
import Observation

// MARK: - 适老化字体
//
// 字体大小 = 基准值 × 全局 fontScale。读取可观察属性会让每个使用字体的
// SwiftUI 子视图建立更新依赖，不能直接读取 UserDefaults 等待偶然重绘。

extension Font {
    /// 当前字体缩放系数，限制在 1.0 ~ 1.6 之间。
    fileprivate static var elderlyScale: CGFloat {
        CGFloat(ThemeManager.shared.fontScale)
    }

    /// 特殊字号也使用同一缩放状态，避免徽标、全屏正文遗漏。
    static func elderly(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * elderlyScale, weight: weight)
    }

    /// 主标题：32pt 加粗，适合页面大标题
    static var titleElderly: Font { .system(size: 32 * elderlyScale, weight: .bold) }
    /// 次级标题：26pt 加粗
    static var title2Elderly: Font { .system(size: 26 * elderlyScale, weight: .bold) }
    /// 正文：22pt 常规，行间距宽松
    static var bodyElderly: Font { .system(size: 22 * elderlyScale, weight: .regular) }
    /// 三级标题：20pt 中粗，用于卡片中的译文/故事正文等
    static var title3Elderly: Font { .system(size: 20 * elderlyScale, weight: .medium) }
    /// 辅助说明：18pt，用于提示文字
    static var captionElderly: Font { .system(size: 18 * elderlyScale, weight: .regular) }
    /// 按钮标签：22pt 加粗
    static var buttonElderly: Font { .system(size: 22 * elderlyScale, weight: .bold) }
}

// MARK: - 适老化颜色

extension Color {
    // --- 背景 ---
    /// 暖浅米绿：RGB 235、238、225；页面和卡片共用同一底色。
    static let backgroundPrimary   = Color(red: 235.0 / 255.0, green: 238.0 / 255.0, blue: 225.0 / 255.0)
    static let backgroundCard      = backgroundPrimary

    // --- 文字 ---
    /// 暖墨绿：RGB 70、85、70；主文字与主要操作共用。
    static let textPrimary         = Color(red: 70.0 / 255.0, green: 85.0 / 255.0, blue: 70.0 / 255.0)
    /// 暖深灰：RGB 100、105、100；次要字和边框共用。
    static let textSecondary       = Color(red: 100.0 / 255.0, green: 105.0 / 255.0, blue: 100.0 / 255.0)
    static let textTertiary        = textSecondary

    // --- 强调 / 交互 ---
    static let accentElderly       = textPrimary
    static let accentSecondary     = textPrimary
    static let brandAmber          = textPrimary
    static let brandMint           = backgroundPrimary

    // --- 状态 ---
    static let statusSuccess       = textPrimary
    /// 暖防诈提醒红：RGB 220、90、90；仅用于警示和错误。
    static let statusError         = Color(red: 220.0 / 255.0, green: 90.0 / 255.0, blue: 90.0 / 255.0)
    static let statusWarning       = statusError

    // --- 分割线 ---
    static let divider             = textSecondary
}

// MARK: - 适老化间距 & 圆角

enum ElderlyMetrics {
    /// 最小可点击区域（Apple HIG 建议 44pt，适老化放大至 56pt）
    static let minTapTarget: CGFloat = 56
    /// 卡片内边距
    static let cardPadding: CGFloat  = 20
    /// 卡片圆角
    static let cornerRadius: CGFloat = 28
    /// 元素间垂直间距
    static let spacing: CGFloat      = 18
}

// MARK: - 录音音量源
//
// 波形要跟着声音实时起伏，但音频回调在非主线程、约每 20ms 一次，
// 如果每一帧都往 @Published 上写会引发过高的重绘频率。
//
// 这里做两件事：其一，用 NSLock 保证非主线程写、主线程读的数据竞争安全；
// 其二，把重绘压到约 25fps——波形只是给人看「它听见了」，25fps 完全够用，
// 再高既看不出差别也白费电。

/// 音频线程 → 主线程的电平传递槽。
///
/// 独立成一个 `nonisolated` 类型并标 `@unchecked Sendable` 的原因：
/// `AudioLevelStore` 是 `@MainActor` 的，它的存储属性被 main-actor 隔离，
/// `nonisolated` 的 `pushRaw` 无法直接写入（编译器报 "Main actor-isolated
/// property 'rawLevel' can not be mutated from a nonisolated context"）。
/// 把跨线程共享的状态挪出 actor 边界，锁随状态一起走，隔离检查与数据竞争
/// 两个问题一次解决。
///
/// `@unchecked Sendable` 的依据：唯一的可变状态 `value` 全程由 `lock` 保护，
/// 不存在无锁并发访问。
private final class AudioLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Double = 0

    var value: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }
}

@MainActor
final class AudioLevelStore: ObservableObject {
    static let shared = AudioLevelStore()

    /// 供波形使用的电平，0...1，已做过平滑。@Published 会在赋值时
    /// 自动发通知，不要再手动 objectWillChange.send()，否则每帧双倍重绘。
    @Published private(set) var level: Double = 0

    /// 原始电平由音频线程写入，锁保护在 AudioLevelBox 内部
    private let box = AudioLevelBox()

    /// 上次真正更新 UI 的时刻
    private var lastEmit = Date.distantPast
    private let emitInterval: TimeInterval = 0.04

    private init() {}

    /// 由音频线程调用：写入原始电平。
    /// 不直接改 @Published，因此这里不需要、也不能要求主线程。
    nonisolated func pushRaw(_ value: Double) {
        box.value = value
    }

    /// 由主线程定时调用：读取原始电平，平滑后发布给 UI。
    ///
    /// 节流判断放在最前面：没到发布间隔就直接返回，
    /// 平滑计算也一并不做——省下的算力和省下的重绘是同一件事。
    func tick() {
        let now = Date()
        guard now.timeIntervalSince(lastEmit) >= emitInterval else { return }
        lastEmit = now

        let raw = box.value

        // 上升快、下降慢：说话时立刻抬起来，停顿后缓缓落下，
        // 比线性跟随更像真实的声音包络
        let smoothing = raw > level ? 0.55 : 0.15
        level += (raw - level) * smoothing
    }

    /// 停止录音时调用，避免波形停在半空
    func reset() {
        box.value = 0
        level = 0
    }
}

// MARK: - 适老化动画节奏
//
// 老人对瞬时变化感知弱，年轻人觉得「跟手」的 0.12s 切换在他们眼里等于没变化，
// 因此状态切换类动画统一放慢到 0.3s 左右，让变化看得见。
// 按下反馈仍保持 0.12s（要跟手）。
//
// 系统开启「减弱动态效果」时全部退化为淡入淡出——前庭功能敏感的用户
// 对位移和缩放会眩晕，宁可牺牲表现力也不能让人难受。

extension Animation {
    /// 全 App 统一的状态切换动画。减速曲线更柔和，末尾不会「砸」一下。
    static var elderlyState: Animation { .easeInOut(duration: 0.3) }

    /// 结果卡片出现用的弹簧，轻微回弹让内容有「落下来」的重量感。
    static var elderlyAppear: Animation { .spring(response: 0.42, dampingFraction: 0.82) }
}

extension View {
    /// 尊重系统「减弱动态效果」：开启时用淡入淡出替代位移+缩放动画。
    func elderlyTransition(from edge: Edge = .bottom) -> some View {
        modifier(ElderlyAppearTransition(edge: edge))
    }
}

struct ElderlyAppearTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let edge: Edge

    func body(content: Content) -> some View {
        content
            .transition(reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .move(edge: edge)))
    }
}

// MARK: - 适老化触觉反馈
//
// 老人眼花、手抖，细微的视觉反馈常常感知不到，而震动一定感觉得到。
// 因此全 App 的关键操作都要给触觉反馈，并且用不同的震动模式编码含义，
// 让用户不看屏幕也能分辨「成功 / 警告 / 出错」。
//
// 生成器做成 static 复用：UIFeedbackGenerator 在首次触发时会有几十毫秒的
// 唤醒延迟，复用同一实例并配合 prepare() 可以把延迟压到几乎不可感知。

/// 触觉反馈只从主线程的 UI 事件触发，整体标注 @MainActor，
/// 既避免静态可变状态在 Swift 6 并发检查下报错，也保证震动时序与 UI 一致。
@MainActor
enum Haptic {
    private static let light  = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy  = UIImpactFeedbackGenerator(style: .heavy)
    private static let notify = UINotificationFeedbackGenerator()

    /// 预热 Taptic Engine，去掉首次触发的延迟。进入页面时调用。
    static func prepare() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        notify.prepare()
    }

    /// 普通按钮点击：轻震
    static func tap() { light.impactOccurred() }

    /// 选择/切换：中震，比点击更有分量
    static func select() { medium.impactOccurred() }

    /// 开始录音：重震一下，明确告知「开始听了」
    static func start() { heavy.impactOccurred() }

    /// 停止录音：两下轻震
    static func stop() {
        light.impactOccurred()
        // 这里显式跳到主队列，避免直接假设 asyncAfter 所在队列具备主线程隔离
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            MainActor.assumeIsolated { light.impactOccurred() }
        }
    }

    /// 操作成功：成功震动模式
    static func success() { notify.notificationOccurred(.success) }

    /// 风险提示：警告震动模式
    static func warning() { notify.notificationOccurred(.warning) }

    /// 出错：错误震动模式
    static func error() { notify.notificationOccurred(.error) }
}

// MARK: - 适老化按钮样式

struct ElderlyButtonStyle: ButtonStyle {
    var background: Color = .accentElderly
    var foreground: Color = .backgroundPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buttonElderly)
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity, minHeight: ElderlyMetrics.minTapTarget)
            .background(background.opacity(configuration.isPressed ? 0.75 : 1.0))
            .cornerRadius(ElderlyMetrics.cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { Haptic.tap() }
            }
    }
}

// MARK: - ThemeManager（运行时调整字体大小）

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private var storedFontScale: Double

    /// 设置滑块与语音指令共用；Observation 会追踪计算属性背后的存储值。
    var fontScale: Double {
        get { storedFontScale }
        set {
            let value = Self.clampedScale(newValue)
            guard value != storedFontScale else { return }
            storedFontScale = value
            UserDefaults.standard.set(value, forKey: "fontScale")
        }
    }

    private init() {
        storedFontScale = Self.clampedScale(UserDefaults.standard.object(forKey: "fontScale") as? Double ?? 1.0)
    }

    private static func clampedScale(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 1.0), 1.6) : 1.0
    }
}
