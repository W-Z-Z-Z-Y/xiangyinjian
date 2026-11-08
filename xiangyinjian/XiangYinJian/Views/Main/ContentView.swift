import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var speechService = SpeechService.shared
    @StateObject private var intentRouter = IntentRouter.shared
    @State private var showVoiceAssistant = false
    @State private var translationPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    var body: some View {
        // 导航独立占用布局高度，保证每个 NavigationStack 的滚动视口
        // 都在胶囊导航上方结束，不依赖 TabView 向内部传递安全区插入量。
        VStack(spacing: 0) {
            TabView(selection: $appState.selectedTab) {
                NavigationStack(path: $translationPath) { TranslationView() }
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem { Label(lang.tr("tab.translate"), systemImage: "waveform.and.mic") }
                    .tag(AppState.Tab.translate)

                ToolsHubView()
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem { Label(lang.tr("design.toolsTab"), systemImage: "square.grid.2x2.fill") }
                    .tag(AppState.Tab.tools)

                MemoryHubView()
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem { Label(lang.tr("design.memoryTab"), systemImage: "heart.text.square.fill") }
                    .tag(AppState.Tab.memory)

                NavigationStack(path: $settingsPath) { SettingsView() }
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem { Label(lang.tr("tab.settings"), systemImage: "gearshape.fill") }
                    .tag(AppState.Tab.profile)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                if speechService.isLoading || (speechService.speakingText != nil && speechService.voiceAvailabilityMessage != nil) {
                    HStack(spacing: 12) {
                        if speechService.isLoading { ProgressView() }
                        Text(speechService.isLoading
                             ? (lang.current == .zh ? "正在准备方言朗读…" : "Preparing dialect audio…")
                             : (speechService.voiceAvailabilityMessage ?? ""))
                            .font(.captionElderly).foregroundStyle(Color.textPrimary)
                        Spacer(minLength: 0)
                        Button(lang.current == .zh ? "停止" : "Stop") { speechService.stop() }
                            .font(.bodyElderly).frame(minHeight: ElderlyMetrics.minTapTarget)
                    }.padding(.horizontal, ElderlyMetrics.cardPadding).background(Color.backgroundPrimary)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Button {
                    NotificationCenter.default.post(name: .voiceAssistantWillOpen, object: nil)
                    showVoiceAssistant = true
                } label: {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.backgroundPrimary)
                        .frame(width: 60, height: 60)
                        .background(Color.accentElderly)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.backgroundPrimary, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lang.tr("voice.openAssistant"))
                .padding(.leading, 20).padding(.bottom, 16)
            }

            HStack(spacing: 4) {
                tabButton(.translate, title: lang.tr("tab.translate"), icon: "mic")
                tabButton(.tools, title: lang.tr("design.toolsTab"), icon: "square.grid.2x2")
                tabButton(.memory, title: lang.tr("design.memoryTab"), icon: "book")
                tabButton(.profile, title: lang.tr("tab.settings"), icon: "gearshape")
            }
            .padding(6)
            .elderlyCard(radius: 36)
            .padding(.horizontal, ElderlyMetrics.cardPadding)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color.backgroundPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .tint(.accentElderly)
        .sheet(isPresented: $showVoiceAssistant) {
            NavigationStack {
                VoiceAssistantCenterView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(lang.tr("common.close")) { showVoiceAssistant = false } } }
            }
        }
        .alert(appState.persistenceError != nil ? lang.tr("storage.failedTitle") : (lang.current == .zh ? "朗读提示" : "Speech playback"), isPresented: Binding(
            get: { appState.persistenceError != nil || speechService.errorMessage != nil },
            set: { if !$0 { appState.persistenceError = nil; speechService.errorMessage = nil } }
        )) {
            Button(lang.tr("common.ok"), role: .cancel) { appState.persistenceError = nil; speechService.errorMessage = nil }
        } message: {
            Text(appState.persistenceError ?? speechService.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .translationHistoryUpdated)) { _ in
            appState.reloadHistory()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appState.reloadHistory() }
        }
        .onChange(of: intentRouter.pendingTab) { _, newTab in handleIntentTab(newTab) }
        .onChange(of: appState.selectedTab) { oldTab, newTab in
            guard oldTab != newTab else { return }
            AppKeyboard.dismiss()
            if oldTab == .translate { translationPath = NavigationPath() }
            if oldTab == .profile { settingsPath = NavigationPath() }
        }
        .onAppear {
            appState.reloadHistory()
            // 全 App 的按钮共用 ElderlyButtonStyle，这里预热一次触觉引擎即可全程受益
            Haptic.prepare()
            if let pending = intentRouter.pendingTab { handleIntentTab(pending) }
        }
    }

    private func tabButton(_ tab: AppState.Tab, title: String, icon: String) -> some View {
        let selected = appState.selectedTab == tab
        return Button {
            AppKeyboard.dismiss()
            Haptic.select()
            appState.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 22, weight: selected ? .semibold : .regular))
                Text(title).font(.captionElderly).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.backgroundPrimary : Color.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(selected ? Color.accentElderly : Color.backgroundPrimary)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func handleIntentTab(_ tab: AppState.Tab?) {
        guard let tab else { return }
        switch tab {
        case .phrases:
            appState.selectedTab = .tools
            appState.moreNavigationTarget = .phrases
        case .history:
            appState.selectedTab = .memory
            appState.memoryNavigationTarget = .history
        case .antiScam:
            appState.selectedTab = .tools
            appState.moreNavigationTarget = .antiScam
        case .settings:
            appState.selectedTab = .profile
        case .voiceCards:
            appState.selectedTab = .memory
            appState.memoryNavigationTarget = .voiceCards
        case .storybook:
            appState.selectedTab = .memory
            appState.memoryNavigationTarget = .storybook
        default:
            appState.selectedTab = .translate
        }
        intentRouter.pendingTab = nil
    }
}
