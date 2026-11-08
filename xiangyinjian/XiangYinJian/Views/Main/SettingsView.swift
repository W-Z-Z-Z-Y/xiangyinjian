import SwiftUI

struct SettingsView: View {
    private enum Destination: Hashable { case voiceCommands }
    @FocusState private var phoneFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var previewText: String?
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var lang: LanguageManager
    @Bindable private var theme = ThemeManager.shared
    @ObservedObject private var speechService = SpeechService.shared

    private var scaleLabel: String {
        String(format: "%.1f×", theme.fontScale)
    }

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            AppPageHeader(title: lang.tr("settings.title"), subtitle: lang.tr("design.settingsSubtitle"), icon: "slider.horizontal.3")
            // 字体大小调节（置顶）
            SettingsGroup {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "textformat.size")
                            .foregroundColor(.accentElderly)
                        Text(lang.tr("settings.fontSize"))
                            .font(.bodyElderly)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(scaleLabel)
                            .font(.captionElderly)
                            .foregroundColor(.textSecondary)
                    }
                    HStack(spacing: 12) {
                        Text(lang.tr("settings.fontSmall"))
                            .font(.captionElderly)
                            .foregroundColor(.textSecondary)
                        Slider(value: $theme.fontScale, in: 1.0...1.6, step: 0.1)
                            .tint(.accentElderly)
                            .accessibilityLabel(lang.tr("settings.fontSize"))
                            .accessibilityValue(scaleLabel)
                        Text(lang.tr("settings.fontLarge"))
                            .font(.title3Elderly)
                            .foregroundColor(.textSecondary)
                    }
                    Text(lang.tr("settings.fontSample"))
                        .font(.bodyElderly)
                        .foregroundColor(.textPrimary)
                }
                .padding(.vertical, 4)
                .frame(minHeight: ElderlyMetrics.minTapTarget)

            } header: {
                Text(lang.tr("settings.display"))
                    .font(.title2Elderly)
                    .foregroundColor(.textPrimary)
                    .textCase(nil)
            }

            // 方言偏好
            SettingsGroup {
                ForEach(Dialects.names, id: \.self) { name in
                    Button {
                        appState.preferredDialect = name
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lang.dialectDisplayName(name))
                                    .font(.bodyElderly)
                                    .foregroundColor(.textPrimary)
                                Text(lang.tr("region.\(name)"))
                                    .font(.captionElderly)
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            if appState.preferredDialect == name {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentElderly)
                                    .font(.title2)
                            }
                        }
                        .frame(minHeight: ElderlyMetrics.minTapTarget)
                    }

                }
            } header: {
                Text(lang.tr("settings.defaultDialect"))
                    .font(.title2Elderly)
                    .foregroundColor(.textPrimary)
                    .textCase(nil)
            }

            // 家人协助
            SettingsGroup {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.accentSecondary)
                    TextField(lang.tr("settings.familyPhoneHint"), text: $appState.familyContactPhone)
                        .focused($phoneFocused)
                        .font(.bodyElderly)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .accessibilityLabel(lang.tr("settings.familyHelp"))
                        .foregroundColor(.textPrimary)
                }
                .frame(minHeight: ElderlyMetrics.minTapTarget)


                Text(lang.tr("settings.familyDesc"))
                    .font(.captionElderly)
                    .foregroundColor(.textSecondary)

            } header: {
                Text(lang.tr("settings.familyHelp"))
                    .font(.title2Elderly)
                    .foregroundColor(.textPrimary)
                    .textCase(nil)
            }

            // 语音指令
            SettingsGroup {
                NavigationLink(value: Destination.voiceCommands) {
                    HStack(spacing: 12) {
                        Image(systemName: "mic.circle.fill")
                            .foregroundColor(.accentElderly)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lang.tr("design.assistantHelp"))
                                .font(.bodyElderly)
                                .foregroundColor(.textPrimary)
                            Text(lang.tr("design.assistantHelpSubtitle"))
                                .font(.captionElderly)
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .frame(minHeight: ElderlyMetrics.minTapTarget)
                }

            } header: {
                Text(lang.tr("design.assistantTitle"))
                    .font(.title2Elderly)
                    .foregroundColor(.textPrimary)
                    .textCase(nil)
            }

            // 功能5：语音朗读调节
            SettingsGroup {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.accentSecondary)
                        Text(lang.tr("settings.speechRate"))
                            .font(.bodyElderly)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(String(format: "%.2f", speechService.speechRate))
                            .font(.captionElderly)
                            .foregroundColor(.textSecondary)
                    }
                    HStack(spacing: 12) {
                        Text(lang.tr("settings.speechSlow"))
                            .font(.captionElderly)
                            .foregroundColor(.textSecondary)
                        Slider(value: $speechService.speechRate, in: 0.1...0.6, step: 0.05)
                            .tint(.accentSecondary)
                            .accessibilityLabel(lang.tr("settings.speechRate"))
                        Text(lang.tr("settings.speechFast"))
                            .font(.captionElderly)
                            .foregroundColor(.textSecondary)
                    }

                    Rectangle().fill(Color.divider).frame(height: 0.75).accessibilityHidden(true)

                    Toggle(isOn: $speechService.autoSpeakTranslation) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.tr("settings.autoSpeak"))
                                .font(.bodyElderly)
                                .foregroundColor(.textPrimary)
                            Text(lang.tr("settings.autoSpeakHint"))
                                .font(.captionElderly)
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .tint(.accentSecondary)
                    .frame(minHeight: ElderlyMetrics.minTapTarget)

                    Rectangle().fill(Color.divider).frame(height: 0.75).accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "person.wave.2.fill")
                            .foregroundColor(.accentSecondary)
                        Text(lang.tr("settings.voiceGender"))
                            .font(.bodyElderly)
                            .foregroundColor(.textPrimary)
                        Picker(lang.tr("settings.voiceGender"), selection: $speechService.useMaleVoice) {
                            Text(lang.tr("settings.voiceFemale")).tag(false)
                            Text(lang.tr("settings.voiceMale")).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: .infinity)
                    }

                    if let message = speechService.voiceAvailabilityMessage {
                        Text(message).font(.captionElderly).foregroundStyle(Color.textSecondary)
                    }

                    Toggle(isOn: $speechService.cloudDialectEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lang.current == .zh ? "方言专用音色" : "Dialect voices")
                                .font(.bodyElderly).foregroundStyle(Color.textPrimary)
                            Text(lang.current == .zh ? "需要联网，支持四川话、闽南语、粤语和东北话。闽南语、东北话目前提供男声；关闭后使用系统音色。" : "Requires an internet connection. Supports Sichuan, Hokkien, Cantonese and Northeastern speech. Hokkien and Northeastern voices are male only. Turn off to use system voices.")
                                .font(.captionElderly).foregroundStyle(Color.textSecondary)
                        }
                    }.tint(.accentSecondary).frame(minHeight: ElderlyMetrics.minTapTarget)

                    if appState.preferredDialect == "客家话" {
                        Text(lang.current == .zh ? "此方言暂用系统中文音色；可录音保存真实口音。" : "This dialect uses a system Chinese voice. Record audio to preserve the original accent.")
                            .font(.captionElderly).foregroundStyle(Color.textSecondary)
                    }

                    Button {
                        let text = lang.tr("settings.speechSample")
                        previewText = text
                        speechService.speak(text, dialect: appState.preferredDialect)
                    } label: {
                        Label(lang.tr("settings.speechPreview"), systemImage: "play.circle.fill")
                            .font(.bodyElderly)
                            .frame(maxWidth: .infinity, minHeight: ElderlyMetrics.minTapTarget)
                            .background(Color.backgroundCard)
                            .foregroundColor(.accentSecondary)
                            .elderlyCard(radius: 20)
                    }
                    .accessibilityLabel(lang.tr("settings.speechPreview"))
                    .accessibilityHint(lang.tr("settings.speechPreviewHint"))
                }
                .padding(.vertical, 4)

            } header: {
                Text(lang.tr("settings.speechTitle"))
                    .font(.title2Elderly)
                    .foregroundColor(.textPrimary)
                    .textCase(nil)
            }

            // 关于（语言切换放在这里）
            SettingsGroup {
                LabeledContent(lang.tr("settings.version"),
                               value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .font(.bodyElderly)
                    .foregroundColor(.textPrimary)

                LabeledContent(lang.tr("settings.dialectCount"), value: "\(Dialects.all.count)\(lang.tr("settings.dialectUnit"))")
                    .font(.bodyElderly)
                    .foregroundColor(.textPrimary)

                LabeledContent(lang.tr("settings.offlineDict"), value: "\(LocalDictionary.count)\(lang.tr("settings.dictUnit"))")
                    .font(.bodyElderly)
                    .foregroundColor(.textPrimary)


                // 语言切换（放在关于区块内，避免老人误触）
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang.tr("settings.language"))
                        .font(.bodyElderly)
                        .foregroundColor(.textPrimary)
                    Picker(lang.tr("settings.language"), selection: $lang.current) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(minHeight: ElderlyMetrics.minTapTarget)

            } header: {
                Text(lang.tr("settings.about"))
                    .font(.title2Elderly)
                    .foregroundColor(.textPrimary)
                    .textCase(nil)
            }
          }
          .padding(.horizontal, ElderlyMetrics.cardPadding)
          .padding(.bottom, 84)
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissToolbar(isFocused: phoneFocused)
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Destination.self) { _ in
            VoiceCommandHintView().toolbar(.visible, for: .navigationBar)
        }
        .buttonStyle(.plain)
        .tint(.accentElderly)
        .onDisappear { stopPreview() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { stopPreview() } }
    }

    private func stopPreview() {
        if let previewText, speechService.isSpeaking(previewText) || speechService.isPaused(previewText) {
            speechService.stop()
        }
        previewText = nil
    }
}


private struct SettingsGroup<Content: View, Header: View>: View {
    let content: Content
    let header: Header

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.content = content()
        self.header = header()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(alignment: .leading, spacing: 16) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20).elderlyCard()
        }
    }
}
