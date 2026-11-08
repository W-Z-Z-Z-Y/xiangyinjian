import SwiftUI

struct TranslationResultFullScreenView: View {
    @EnvironmentObject private var lang: LanguageManager

    let resultText: String
    let resultDialect: String?
    let isSpeaking: Bool
    let onClose: () -> Void
    let onSpeak: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.textSecondary)
                }
                .padding(20)
                .accessibilityLabel(lang.tr("a11y.close"))
            }

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        if let resultDialect {
                            Text(lang.dialectDisplayName(resultDialect))
                                .font(.elderly(size: 20, weight: .semibold))
                                .foregroundColor(.backgroundPrimary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.accentSecondary)
                                .cornerRadius(20)
                        }

                        Text(resultText)
                            .font(.elderly(size: 36, weight: .medium))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(resultAccessibilityLabel)
                }
            }

            HStack(spacing: 40) {
                Button(action: onSpeak) {
                    VStack(spacing: 8) {
                        Image(systemName: isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 36))
                        Text(isSpeaking ? lang.tr("translate.stopSpeak") : lang.tr("translate.speakResult"))
                            .font(.captionElderly)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.accentSecondary)
                }

                Button {
                    UIPasteboard.general.string = resultText
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 36))
                        Text(lang.tr("translate.copyResult"))
                            .font(.captionElderly)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.accentElderly)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
    }

    /// 把方言徽章 + 结果正文合并成一句，避免 VoiceOver 拆成两段碎读。
    private var resultAccessibilityLabel: String {
        if let resultDialect {
            return String(format: lang.tr("a11y.resultWithDialect"),
                          lang.dialectDisplayName(resultDialect), resultText)
        }
        return String(format: lang.tr("a11y.resultPlain"), resultText)
    }
}

struct QuickSceneCardView: View {
    @EnvironmentObject private var lang: LanguageManager

    let onSelectScene: (QuickTranslationScene) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang.tr("translate.scenes"))
                .font(.title2Elderly)
                .foregroundColor(.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(QuickTranslationScene.all) { scene in
                        Button {
                            onSelectScene(scene)
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: scene.icon).font(.title3)
                                Text(scene.localizedTitle(lang)).font(.captionElderly)
                            }
                                .padding(14)
                                .frame(minWidth: 84, minHeight: ElderlyMetrics.minTapTarget)
                                .elderlyCard(radius: 20)
                                .foregroundColor(.textPrimary)
                        }
                        .accessibilityLabel(String(format: lang.tr("translate.sceneFillHint"), scene.localizedTitle(lang)))
                        .accessibilityHint(scene.text)
                    }
                }
            }
        }
    }
}

struct DialectPickerView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let preferredDialect: String
    let onSelectDialect: (String) -> Void

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize || ThemeManager.shared.fontScale > 1.2 ? 1 : 3
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.tr("translate.selectDialect"))
                .font(.title2Elderly)
                .foregroundColor(.textPrimary)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Dialects.names, id: \.self) { name in
                    Button {
                        onSelectDialect(name)
                    } label: {
                        Text(lang.dialectDisplayName(name))
                            .font(.buttonElderly)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: ElderlyMetrics.minTapTarget)
                            .foregroundColor(preferredDialect == name ? .backgroundPrimary : .textPrimary)
                            .background(preferredDialect == name ? Color.accentElderly : Color.backgroundCard)
                            .cornerRadius(ElderlyMetrics.cornerRadius)
                    }
                    // 选中态用色块滑动过渡，而不是瞬间跳变——老人看得见「我选了哪个」
                    .animation(.elderlyState, value: preferredDialect)
                    .accessibilityLabel("\(lang.dialectDisplayName(name))\(preferredDialect == name ? lang.tr("translate.selectedSuffix") : "")")
                    .accessibilityHint(String(format: lang.tr("translate.selectHint"), lang.dialectDisplayName(name)))
                }
            }
        }
    }
}

struct TranslationDirectionToggleView: View {
    @EnvironmentObject private var lang: LanguageManager
    let preferredDialect: String
    let isReverseMode: Bool
    let onSelectDialect: (String) -> Void
    let onToggle: () -> Void

    private var mandarinLabel: some View {
        Text(lang.dialectDisplayName("普通话"))
            .font(.buttonElderly).foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: ElderlyMetrics.minTapTarget)
    }

    private var dialectMenu: some View {
        Menu {
            ForEach(Dialects.names, id: \.self) { name in
                Button { onSelectDialect(name) } label: {
                    if name == preferredDialect {
                        Label(lang.dialectDisplayName(name), systemImage: "checkmark")
                    } else {
                        Text(lang.dialectDisplayName(name))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(lang.dialectDisplayName(preferredDialect))
                Image(systemName: "chevron.down").font(.caption)
            }
            .font(.buttonElderly)
            .foregroundStyle(Color.accentElderly)
            .frame(maxWidth: .infinity, minHeight: ElderlyMetrics.minTapTarget)
        }
        .accessibilityLabel(lang.tr("translate.selectDialect"))
        .accessibilityValue(lang.dialectDisplayName(preferredDialect))
    }

    var body: some View {
        HStack(spacing: 8) {
            if isReverseMode { mandarinLabel } else { dialectMenu }
            Button(action: onToggle) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentElderly)
                    .frame(width: ElderlyMetrics.minTapTarget, height: ElderlyMetrics.minTapTarget)
                    .background(Color.backgroundPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lang.tr("translate.switchDirection"))
            .accessibilityValue(isReverseMode ? lang.tr("translate.reverseLabel") : lang.tr("translate.forwardLabel"))
            if isReverseMode { dialectMenu } else { mandarinLabel }
        }
        .padding(.horizontal, 8).elderlyCard(radius: 24)
    }
}

struct EmergencyHelpButton: View {
    @EnvironmentObject private var lang: LanguageManager

    let phone: String

    var body: some View {
        Button {
            if let url = URL(string: "tel://\(phone)") {
                UIApplication.shared.open(url)
            }
        } label: {
            Image(systemName: "phone.fill")
                .font(.title2)
                .foregroundColor(.backgroundPrimary)
                .frame(width: 56, height: 56)
                .background(Color.accentElderly)
                .clipShape(Circle())
                
        }
        .accessibilityLabel(lang.tr("help.callFamily"))
        .accessibilityHint(lang.tr("help.callFamilyHint"))
    }
}

struct FamilyGreetingsPanelView: View {
    @EnvironmentObject private var lang: LanguageManager

    let onSelectGreeting: (FamilyGreetingItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang.tr("familyGreeting.title"))
                .font(.title2Elderly)
                .foregroundColor(.textPrimary)

            AppCardGrid {
              ForEach(FamilyGreetingItem.all) { item in
                Button {
                    onSelectGreeting(item)
                } label: {
                    HStack(spacing: 12) {
                        Text(lang.tr(item.textKey))
                            .font(.captionElderly)
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: ElderlyMetrics.minTapTarget)
                    .padding(.vertical, 8)
                    .elderlyCard(radius: 18)
                }
                .accessibilityLabel(lang.tr(item.textKey))
                .accessibilityHint(lang.tr("familyGreeting.fillHint"))
            }
            }
        }
        .padding(16)
        .elderlyCard()
    }
}

struct TranslationInputCardView: View {
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var audioLevel = AudioLevelStore.shared

    @Binding var inputText: String
    let isRecording: Bool
    let showSpeechRetryHint: Bool
    let speechStatusMessage: String?
    let onClear: () -> Void
    let onStartSpeech: () -> Void
    let onStopSpeech: () -> Void
    let onRetrySpeech: () -> Void

    @State private var showTextInput = false
    @State private var isHeld = false
    @State private var holdTask: Task<Void, Never>?
    @FocusState private var textInputFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Label(lang.tr("design.voicePrompt"), systemImage: "mic")
                .font(.title3Elderly).foregroundStyle(Color.textPrimary)
            if isRecording {
                AudioWaveformView(level: audioLevel.level, color: .accentElderly, barCount: 32, maxHeight: 64)
            } else {
                VoiceWaveformMark()
            }
            Label(isRecording ? lang.tr("translate.tapToStop") : lang.tr("translate.tapToSpeak"), systemImage: "mic.fill")
                .font(.buttonElderly)
                .foregroundStyle(Color.backgroundPrimary)
                .frame(maxWidth: .infinity, minHeight: ElderlyMetrics.minTapTarget)
                .padding(.vertical, 6)
                .background(Color.accentElderly)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHeld else { return }
                        isHeld = true
                        holdTask = Task { @MainActor in
                            do { try await Task.sleep(nanoseconds: 200_000_000) }
                            catch { return }
                            guard isHeld else { return }
                            onStartSpeech()
                        }
                    }
                    .onEnded { _ in
                        isHeld = false
                        holdTask?.cancel()
                        holdTask = nil
                        onStopSpeech()
                    })
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(isRecording ? lang.tr("translate.stopRecording") : lang.tr("translate.tapToSpeak"))
                .accessibilityHint(lang.tr("translate.speakHintStart"))
                .accessibilityAction { if isRecording { onStopSpeech() } else { onStartSpeech() } }
                .onDisappear {
                    isHeld = false
                    holdTask?.cancel()
                    onStopSpeech()
                }

            if !inputText.isEmpty || showTextInput {
                HStack {
                    Text(lang.tr("translate.inputLabel")).font(.captionElderly).foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle")
                            .font(.title3).foregroundStyle(Color.textSecondary)
                            .frame(width: ElderlyMetrics.minTapTarget, height: ElderlyMetrics.minTapTarget)
                    }
                    .disabled(inputText.isEmpty)
                    .accessibilityLabel(lang.tr("translate.clearInput"))
                    .accessibilityHint(lang.tr("translate.clearHint"))
                }
                if showTextInput {
                    TextEditor(text: $inputText)
                        .font(.bodyElderly).foregroundStyle(Color.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120).padding(8).elderlyCard(radius: 16)
                        .focused($textInputFocused)
                        .accessibilityLabel(lang.tr("translate.inputLabel"))
                        .onAppear { textInputFocused = true }
                } else {
                    Text(inputText).font(.bodyElderly).foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(inputText)
                }
            }

            Rectangle().fill(Color.divider).frame(height: 0.75).accessibilityHidden(true)
            Button {
                Haptic.tap()
                withAnimation(.elderlyState) { showTextInput.toggle() }
            } label: {
                Label(lang.tr("design.typeInput"), systemImage: "keyboard")
                    .font(.bodyElderly).foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: ElderlyMetrics.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityValue(showTextInput ? lang.tr("antiScam.expanded") : lang.tr("antiScam.collapsed"))

            if showSpeechRetryHint {
                HStack(spacing: 8) {
                    Text(lang.tr("translate.retryHint")).font(.captionElderly).foregroundStyle(Color.textSecondary)
                    Button(action: onRetrySpeech) {
                        Label(lang.tr("translate.retryAction"), systemImage: "arrow.clockwise")
                            .font(.captionElderly).foregroundStyle(Color.accentElderly)
                            .frame(minHeight: ElderlyMetrics.minTapTarget)
                    }
                    .accessibilityHint(lang.tr("translate.retryActionHint"))
                }
            }
            if let speechStatusMessage {
                Label(speechStatusMessage, systemImage: isRecording ? "waveform" : "info.circle")
                    .font(.captionElderly).foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(ElderlyMetrics.cardPadding).elderlyCard()
        .keyboardDismissToolbar(isFocused: textInputFocused)
    }
}

struct TranslationResultCardView: View {
    @EnvironmentObject private var lang: LanguageManager

    let resultText: String
    let resultDialect: String?
    let isSpeaking: Bool
    let onSpeak: () -> Void
    let onCopy: () -> Void
    let onShowFullScreen: () -> Void
    let onSaveVoiceCard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(lang.tr("translate.result"))
                    .font(.title2Elderly)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: onSpeak) {
                    Image(systemName: isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                        .font(.title2)
                        .foregroundColor(.accentSecondary)
                }
                .frame(width: ElderlyMetrics.minTapTarget, height: ElderlyMetrics.minTapTarget)
                .accessibilityLabel(isSpeaking ? lang.tr("translate.stopSpeak") : lang.tr("translate.speakResult"))
                .accessibilityHint(isSpeaking ? lang.tr("translate.stopSpeakHint") : lang.tr("translate.speakResultHint"))

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.title2)
                        .foregroundColor(.accentElderly)
                }
                .frame(width: ElderlyMetrics.minTapTarget, height: ElderlyMetrics.minTapTarget)
                .accessibilityLabel(lang.tr("translate.copyResult"))
                .accessibilityHint(lang.tr("translate.copyResultHint"))

                ShareLink(item: resultText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(.accentSecondary)
                }
                .frame(width: ElderlyMetrics.minTapTarget, height: ElderlyMetrics.minTapTarget)
                .accessibilityLabel(lang.tr("translate.shareResult"))
                .accessibilityHint(lang.tr("translate.shareResultHint"))
            }

            Button(action: onShowFullScreen) {
                VStack(alignment: .leading, spacing: 10) {
                    if let resultDialect {
                        Text(lang.dialectDisplayName(resultDialect))
                            .font(.elderly(size: 16, weight: .semibold))
                            .foregroundColor(.backgroundPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.accentSecondary)
                            .cornerRadius(12)
                    }
                    Text(resultText)
                        .font(.bodyElderly)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(resultAccessibilityLabel)
            .accessibilityHint(lang.tr("result.tapToEnlarge"))

            HStack(spacing: 10) {
                ShareLink(item: lang.tr("share.familyPrefix") + resultText) {
                    Label(lang.tr("share.family"), systemImage: "person.2.fill")
                        .font(.buttonElderly)
                        .frame(maxWidth: .infinity, minHeight: ElderlyMetrics.minTapTarget)
                        .background(Color.accentSecondary)
                        .foregroundColor(.backgroundPrimary)
                        .cornerRadius(ElderlyMetrics.cornerRadius)
                }
                .accessibilityLabel(lang.tr("share.family"))
                .accessibilityHint(lang.tr("share.familyHint"))

                Button(action: onSaveVoiceCard) {
                    Label(lang.tr("voiceCard.save"), systemImage: "waveform.circle.fill")
                        .font(.buttonElderly)
                        .frame(maxWidth: .infinity, minHeight: ElderlyMetrics.minTapTarget)
                        .background(Color.accentElderly)
                        .foregroundColor(.backgroundPrimary)
                        .cornerRadius(ElderlyMetrics.cornerRadius)
                }
                .accessibilityLabel(lang.tr("voiceCard.save"))
                .accessibilityHint(lang.tr("voiceCard.saveHint"))
            }
        }
        .padding(ElderlyMetrics.cardPadding)
        .elderlyCard()
    }

    /// 方言徽章 + 结果正文合并朗读，避免 VoiceOver 碎读。
    private var resultAccessibilityLabel: String {
        if let resultDialect {
            return String(format: lang.tr("a11y.resultWithDialect"),
                          lang.dialectDisplayName(resultDialect), resultText)
        }
        return String(format: lang.tr("a11y.resultPlain"), resultText)
    }
}
