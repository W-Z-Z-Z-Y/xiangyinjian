import SwiftUI
import AppIntents

@main
struct XiangYinJianApp: App {

    @StateObject private var appState = AppState()
    private let lang = LanguageManager.shared
    @State private var showOnboarding = false

    init() {
        AppAppearance.configure()
        // 向系统注册 Siri 快捷指令短语，安装后即可被「嘿 Siri」唤起
        XiangYinJianShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environmentObject(appState)
                .environmentObject(lang)
                // 适老化：全局字体缩放跟随系统无障碍设置
                .dynamicTypeSize(.large ... .accessibility3)
                .id(lang.current) // 语言切换时强制重建视图树
                .onAppear {
                    // 首次启动显示新手引导
                    let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
                    if !hasSeenOnboarding {
                        showOnboarding = true
                    }
                }
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                        .environmentObject(lang)
                        .onDisappear {
                            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                        }
                }
        }
    }
}
