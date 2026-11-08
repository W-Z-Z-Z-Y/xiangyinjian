import SwiftUI

struct ToolsHubView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var lang: LanguageManager
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AppPageHeader(title: lang.tr("design.toolsTitle"), subtitle: lang.tr("design.toolsSubtitle"), icon: "square.grid.2x2")
                    Text(lang.tr("design.toolsSection")).font(.title3Elderly).foregroundStyle(Color.textPrimary)
                    AppCardGrid {
                        NavigationLink(value: MoreDestination.dualDialect) {
                            FeatureTile(icon: "person.2", title: lang.tr("design.dualTitle"), subtitle: lang.tr("design.dualSubtitle"))
                        }
                        NavigationLink(value: MoreDestination.phrases) {
                            FeatureTile(icon: "text.bubble", title: lang.tr("tab.phrases"), subtitle: lang.tr("design.phrasesSubtitle"))
                        }
                        NavigationLink(value: MoreDestination.voiceAssistant) {
                            FeatureTile(icon: "mic", title: lang.tr("design.assistantTitle"), subtitle: lang.tr("design.assistantSubtitle"))
                        }
                        NavigationLink(value: MoreDestination.antiScam) {
                            FeatureTile(icon: "exclamationmark.shield", title: lang.tr("design.scamTitle"), subtitle: lang.tr("design.scamSubtitle"), color: .statusWarning)
                        }
                    }
                    .buttonStyle(FeatureCardButtonStyle())

                }
                .padding(.horizontal, ElderlyMetrics.cardPadding)
                .padding(.bottom, 84)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MoreDestination.self) { destination in
                toolsDestination(destination).toolbar(.visible, for: .navigationBar)
            }
        }
        .onChange(of: appState.moreNavigationTarget) { _, _ in followVoiceRoute() }
        .onChange(of: appState.selectedTab) { oldTab, newTab in
            if oldTab == .tools, newTab != .tools { path = NavigationPath() }
        }
        .onAppear { followVoiceRoute() }
    }

    private func followVoiceRoute() {
        guard let target = appState.moreNavigationTarget, target != .settings else { return }
        path = NavigationPath([target])
        appState.moreNavigationTarget = nil
    }

    @ViewBuilder private func toolsDestination(_ destination: MoreDestination) -> some View {
        switch destination {
        case .phrases: PhrasesView()
        case .history: HistoryView()
        case .antiScam: AntiScamView()
        case .dualDialect: DualDialectView()
        case .voiceAssistant: VoiceAssistantCenterView()
        case .settings: EmptyView()
        }
    }
}

struct MemoryHubView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var lang: LanguageManager
    @StateObject private var voices = VoiceCardsViewModel()
    @ObservedObject private var player = VoiceRecordingPlayer.shared
    @ObservedObject private var speech = SpeechService.shared
    @State private var storybookCount = 0
    @State private var path = NavigationPath()

    private var recentCard: VoiceCard? { voices.cards.max { $0.date < $1.date } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AppPageHeader(title: lang.tr("design.memoryTitle"), subtitle: lang.tr("design.memorySubtitle"), icon: "heart")
                    AppCardGrid {
                        NavigationLink(value: MemoryDestination.voiceCards) {
                            MemoryCountTile(icon: "waveform", title: lang.tr("design.voiceCardsTitle"), count: voices.cards.count, unit: lang.tr("design.cardUnit"))
                        }
                        NavigationLink(value: MemoryDestination.storybook) {
                            MemoryCountTile(icon: "book", title: lang.tr("design.storybookTitle"), count: storybookCount, unit: lang.tr("design.bookUnit"))
                        }
                    }
                    .buttonStyle(FeatureCardButtonStyle())
                    HStack {
                        Text(lang.tr("design.recentVoices")).font(.title3Elderly).foregroundStyle(Color.textPrimary)
                        Spacer()
                        NavigationLink(value: MemoryDestination.voiceCards) {
                            Label(lang.tr("design.viewAll"), systemImage: "chevron.right")
                                .font(.captionElderly).foregroundStyle(Color.textSecondary)
                                .frame(minHeight: ElderlyMetrics.minTapTarget)
                        }
                    }
                    if let card = recentCard {
                        recentVoice(card)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "waveform").font(.title).foregroundStyle(Color.accentElderly)
                            Text(lang.tr("design.noVoices")).font(.title3Elderly).foregroundStyle(Color.textPrimary)
                            Text(lang.tr("design.saveVoiceHint")).font(.captionElderly).foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20).elderlyCard()
                    }
                    NavigationLink(value: MemoryDestination.storybook) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(lang.tr("design.storybookTitle")).font(.title2Elderly)
                                Text(lang.tr("design.storybookSubtitle")).font(.captionElderly).foregroundStyle(Color.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "book.pages").font(.system(size: 42, weight: .light)).accessibilityHidden(true)
                            Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                        }
                        .foregroundStyle(Color.textPrimary)
                        .padding(20).elderlyCard()
                    }
                    NavigationLink(value: MemoryDestination.archive) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(lang.tr("design.archiveTitle"), systemImage: "archivebox")
                                    .font(.title3Elderly).fontWeight(.bold)
                                Text(lang.tr("design.archiveSubtitle"))
                                    .font(.captionElderly).foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        .foregroundStyle(Color.textPrimary)
                        .frame(minHeight: ElderlyMetrics.minTapTarget)
                        .padding(20).elderlyCard()
                    }
                    NavigationLink(value: MemoryDestination.history) {
                        HStack {
                            Label(lang.tr("design.historyTitle"), systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        .font(.bodyElderly).foregroundStyle(Color.textPrimary)
                        .frame(minHeight: ElderlyMetrics.minTapTarget)
                        .padding(.horizontal, 20).padding(.vertical, 8).elderlyCard()
                    }
                }
                .buttonStyle(FeatureCardButtonStyle())
                .padding(.horizontal, ElderlyMetrics.cardPadding)
                .padding(.bottom, 84)
                .onAppear(perform: refreshContent)
                .onDisappear {
                    player.stop()
                    speech.stop()
                }
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MemoryDestination.self) { destination in
                Group {
                    switch destination {
                    case .voiceCards: VoiceCardsView()
                    case .storybook: AIStorybookView()
                    case .history: HistoryView()
                    case .archive: VoiceArchiveView()
                    }
                }
                .toolbar(.visible, for: .navigationBar)
            }
        }
        .voicePlaybackFeedback()
        .onReceive(NotificationCenter.default.publisher(for: .voiceMemoriesUpdated)) { _ in refreshContent() }
        .onChange(of: appState.memoryNavigationTarget) { _, _ in followVoiceRoute() }
        .onChange(of: appState.selectedTab) { oldTab, newTab in
            if oldTab == .memory, newTab != .memory { path = NavigationPath() }
        }
        .onAppear { followVoiceRoute() }
        .onDisappear {
            VoiceRecordingPlayer.shared.stop()
            speech.stop()
        }
    }

    private func followVoiceRoute() {
        guard let target = appState.memoryNavigationTarget else { return }
        path = NavigationPath([target])
        appState.memoryNavigationTarget = nil
    }

    private func refreshContent() {
        voices.loadCards()
        storybookCount = (AppFileStore.load([Storybook].self, fileName: "storybooks.json", legacyKey: "storybooks") ?? []).count
    }

    private func isPlaying(_ card: VoiceCard) -> Bool {
        if let audioFileName = card.audioFileName, player.playingPath == audioFileName { return true }
        return speech.isSpeaking(card.translatedText)
    }

    private func recentVoice(_ card: VoiceCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(lang.tr("voiceCategory.\(card.category)")) · \(lang.dialectDisplayName(card.dialect))")
                .font(.captionElderly).foregroundStyle(Color.textSecondary)
            Text(card.sourceText).font(.title2Elderly).foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                VoiceWaveformMark()
                Button { voices.playCard(card) } label: {
                    Image(systemName: isPlaying(card) ? "stop.fill" : "play.fill")
                        .font(.title3).foregroundStyle(Color.backgroundPrimary)
                        .frame(width: ElderlyMetrics.minTapTarget, height: ElderlyMetrics.minTapTarget)
                        .background(Color.accentElderly).clipShape(Circle())
                }
                .accessibilityLabel(lang.tr(isPlaying(card) ? "translate.stopSpeak" : "translate.speakResult"))
                .accessibilityHint(card.translatedText)
            }
            Text(lang.memoryDate(card.date)).font(.captionElderly).foregroundStyle(Color.textSecondary)
        }
        .padding(20).elderlyCard()
    }
}

private struct FeatureTile: View {
    let icon: String
    let title: String
    let subtitle: String
    var color: Color = .accentElderly

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.system(size: 42, weight: .light)).foregroundStyle(color)
                .frame(height: 56).accessibilityHidden(true)
            Text(title).font(.title3Elderly).fontWeight(.bold).foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.captionElderly).foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.textSecondary).accessibilityHidden(true)
            }
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading).elderlyCard()
        .contentShape(RoundedRectangle(cornerRadius: ElderlyMetrics.cornerRadius))
    }
}

private struct MemoryCountTile: View {
    let icon: String
    let title: String
    let count: Int
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon).font(.captionElderly).foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(count, format: .number).font(.titleElderly).foregroundStyle(Color.textPrimary)
                Text(unit).font(.captionElderly).foregroundStyle(Color.textSecondary)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).elderlyCard()
        .accessibilityElement(children: .combine)
    }
}

/// Keeps voice commands discoverable without competing with the translation microphone.
struct VoiceAssistantCenterView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var voiceCmd = VoiceCommandService.shared
    @ObservedObject private var audioLevel = AudioLevelStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let micDiameter: CGFloat = 150

    var body: some View {
        ScrollView {
          VStack(spacing: 24) {
            Spacer()
            ZStack {
                // 监听中：绕麦克风一圈的实时音量波形，让用户看见「它听见了」
                if voiceCmd.isListening {
                    RingAudioWaveformView(
                        level: audioLevel.level,
                        color: .accentElderly,
                        baseRadius: micDiameter / 2,
                        maxLength: 30
                    )
                    .elderlyTransition(from: .top)
                }

                Image(systemName: voiceCmd.isListening ? "waveform" : "mic.circle.fill")
                    .font(.system(size: 68, weight: .medium))
                    .foregroundColor(.backgroundPrimary)
                    .frame(width: micDiameter, height: micDiameter)
                    .background(Color.accentElderly)
                    .clipShape(Circle())
                    .modifier(PulsingEffect(isActive: voiceCmd.isListening))
            }
            // 给环形波形留出空间，避免向外扩的刺被布局裁掉
            .frame(width: micDiameter + 60, height: micDiameter + 60)
            .onChange(of: voiceCmd.isListening) { _, listening in
                if listening { Haptic.start() } else { Haptic.stop() }
            }

            Text(lang.tr(voiceCmd.isListening ? "voice.listening" : "design.assistantTitle"))
                .font(.title2Elderly)
                .foregroundColor(.textPrimary)
            Text(lang.tr(voiceCmd.isListening ? "voice.finishHint" : "voice.startHint"))
                .font(.bodyElderly)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if !voiceCmd.recognizedText.isEmpty {
                Text(voiceCmd.recognizedText)
                    .font(.bodyElderly)
                    .foregroundColor(.textPrimary)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color.backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 24)
            }

            Button {
                if voiceCmd.isPreparing {
                    voiceCmd.stopListening()
                } else if voiceCmd.isListening || voiceCmd.lastCommand != nil {
                    Task { @MainActor in
                        if let command = await voiceCmd.commandForExecution() {
                            let shouldDismiss = voiceCmd.shouldDismissAfterExecution
                            if voiceCmd.executeCommand(command, appState: appState), shouldDismiss { dismiss() }
                        }
                    }
                } else {
                    voiceCmd.startListening(dialect: appState.preferredDialect)
                }
            } label: {
                Label(lang.tr(voiceCmd.isFinishing ? "voice.finishing" : voiceCmd.isPreparing ? "voice.cancelWait" : (voiceCmd.isListening || voiceCmd.lastCommand != nil ? "voice.execute" : "voice.start")), systemImage: voiceCmd.isListening ? "checkmark.circle.fill" : "mic.fill")
            }
            .buttonStyle(ElderlyButtonStyle(background: .accentElderly))
            .disabled(voiceCmd.isFinishing)
            .padding(.horizontal, 24)

            if !voiceCmd.recognizedText.isEmpty {
                Button { voiceCmd.startListening(dialect: appState.preferredDialect) } label: {
                    Label(lang.tr("voice.retry"), systemImage: "arrow.clockwise")
                        .font(.bodyElderly).foregroundStyle(Color.accentElderly)
                        .frame(maxWidth: .infinity, minHeight: ElderlyMetrics.minTapTarget)
                        .padding(.vertical, 6).elderlyCard(radius: 24)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }
            if let feedback = voiceCmd.feedbackMessage {
                Text(feedback).font(.bodyElderly).foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            Spacer()
          }
          .padding(.bottom, 84)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(lang.tr("design.assistantTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptic.tap()
                    voiceCmd.showHelp = true
                } label: {
                    Label(lang.tr("voice.commands"), systemImage: "questionmark.circle")
                        .font(.captionElderly)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel(lang.tr("voice.commandsHint"))
            }
        }
        .sheet(isPresented: $voiceCmd.showHelp) { VoiceCommandHintView() }
        .alert(lang.tr("common.alert"), isPresented: Binding(
            get: { voiceCmd.errorMessage != nil },
            set: { if !$0 { voiceCmd.errorMessage = nil } }
        )) {
            Button(lang.tr("common.ok")) { voiceCmd.errorMessage = nil }
        } message: {
            Text(voiceCmd.errorMessage ?? "")
        }
        .onDisappear { voiceCmd.stopListening() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { voiceCmd.stopListening() } }
    }
}
