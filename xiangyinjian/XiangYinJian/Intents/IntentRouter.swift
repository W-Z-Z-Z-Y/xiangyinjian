import Foundation
import Combine

/// Intent 与 AppState 之间的桥接单例。
///
/// 导航类 App Intent（如「打开乡音间绘本」）在 `perform()` 里调用
/// `requestTab(_:)`，由 `ContentView` 订阅并切换 TabView。
///
/// 冷启动场景：App 可能因 Intent 被拉起，此时 `ContentView` 尚未订阅，
/// 因此用 `pendingTab` 暂存最后一次请求，待视图出现后补投递。
@MainActor
final class IntentRouter: ObservableObject {
    static let shared = IntentRouter()

    /// 待切换的目标 Tab（被 ContentView 消费后置回 nil）
    @Published var pendingTab: AppState.Tab?

    private init() {}

    func requestTab(_ tab: AppState.Tab) {
        pendingTab = tab
    }
}
