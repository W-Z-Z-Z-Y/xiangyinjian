import SwiftUI

struct AntiScamView: View {
    @EnvironmentObject private var lang: LanguageManager
    @State private var selectedScam: ScamType? = nil
    @State private var callError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: ElderlyMetrics.spacing) {
                Label(lang.tr("design.safetyReminder"), systemImage: "shield.lefthalf.filled")
                    .font(.title3Elderly).fontWeight(.bold).foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18).elderlyCard()
                    .padding(.horizontal, ElderlyMetrics.cardPadding)
                    .padding(.top, ElderlyMetrics.cardPadding)
                warningBanner
                threeStepCard
                Text(lang.tr("antiScam.tapToLearn"))
                    .font(.bodyElderly)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ElderlyMetrics.cardPadding)

                ForEach(ScamType.all) { scam in
                    ScamCard(scam: scam, isExpanded: selectedScam?.id == scam.id) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedScam = selectedScam?.id == scam.id ? nil : scam
                        }
                    }
                }

                emergencyCard
            }
            .padding(.bottom, 84)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(lang.tr("antiScam.pageTitle"))
        .navigationBarTitleDisplayMode(.large)
        .alert(lang.tr("common.alert"), isPresented: Binding(
            get: { callError != nil },
            set: { if !$0 { callError = nil } }
        )) {
            Button(lang.tr("translate.ok"), role: .cancel) { callError = nil }
        } message: {
            Text(callError ?? "")
        }
    }

    // MARK: - 顶部警示横幅
    private var warningBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 40))
                .foregroundColor(.statusWarning)
            VStack(alignment: .leading, spacing: 4) {
                Text(lang.tr("antiScam.bannerTitle"))
                    .font(.title2Elderly)
                    .foregroundColor(.textPrimary)
                Text(lang.tr("antiScam.bannerSubtitle"))
                    .font(.bodyElderly)
                    .foregroundColor(.statusError)
            }
            Spacer()
        }
        .padding(ElderlyMetrics.cardPadding)
        .background(Color.backgroundCard)
        .cornerRadius(ElderlyMetrics.cornerRadius)
        .padding(.horizontal, ElderlyMetrics.cardPadding)
    }

    private var threeStepCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang.tr("antiScam.threeStepTitle"))
                .font(.title2Elderly)
                .foregroundColor(.textPrimary)

            ForEach([lang.tr("antiScam.step1"),
                     lang.tr("antiScam.step2"),
                     lang.tr("antiScam.step3")], id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.statusSuccess)
                        .font(.title3)
                    Text(item)
                        .font(.bodyElderly)
                        .foregroundColor(.textPrimary)
                }
            }
        }
        .padding(ElderlyMetrics.cardPadding)
        .elderlyCard()
        .padding(.horizontal, ElderlyMetrics.cardPadding)
    }

    // MARK: - 紧急联系卡片
    private var emergencyCard: some View {
        VStack(spacing: 14) {
            Text(lang.tr("antiScam.emergency"))
                .font(.title2Elderly)
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(EmergencyContact.all) { contact in
                Button {
                    guard let url = URL(string: "tel://\(contact.number)") else {
                        callError = lang.tr("phone.openFailed")
                        return
                    }
                    UIApplication.shared.open(url) { success in
                        Task { @MainActor in
                            if !success { callError = lang.tr("phone.openFailed") }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: contact.icon)
                            .font(.title2)
                            .foregroundColor(contact.color)
                            .frame(width: ElderlyMetrics.minTapTarget, height: ElderlyMetrics.minTapTarget)
                            .background(Color.backgroundCard)
                            .cornerRadius(12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.localizedName(lang))
                                .font(.bodyElderly)
                                .foregroundColor(.textPrimary)
                            Text(contact.number)
                                .font(.title2Elderly)
                                .foregroundColor(.accentElderly)
                        }
                        Spacer()
                        Image(systemName: "phone.fill")
                            .foregroundColor(.statusSuccess)
                            .font(.title2)
                    }
                    .padding(ElderlyMetrics.cardPadding)
                    .elderlyCard()
                }
                .accessibilityLabel("\(contact.localizedName(lang)) \(contact.number)")
                .accessibilityHint(lang.tr("antiScam.callHint"))
            }
        }
        .padding(.horizontal, ElderlyMetrics.cardPadding)
    }
}

// MARK: - 诈骗类型卡片

private struct ScamCard: View {
    let scam: ScamType
    let isExpanded: Bool
    let onTap: () -> Void
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var speech = SpeechService.shared

    private var scriptText: String { scam.localizedScript(lang) }
    private var isSpeaking: Bool { speech.isSpeaking(scriptText) }
    private var tipsText: String { scam.localizedTips(lang).joined(separator: "。") }
    private var isTipsSpeaking: Bool { speech.isSpeaking(tipsText) }
    private var speechLocale: String {
        lang.current == .en ? "en-US" : Dialects.locale(for: appState.preferredDialect)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    Image(systemName: scam.icon)
                        .font(.title2)
                        .foregroundColor(scam.color)
                        .frame(width: 48, height: 48)
                        .background(Color.backgroundCard)
                        .cornerRadius(12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scam.localizedTitle(lang))
                            .font(.title2Elderly)
                            .foregroundColor(.textPrimary)
                        Text(scam.localizedSubtitle(lang))
                            .font(.captionElderly)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.textSecondary)
                        .font(.title3)
                }
                .padding(ElderlyMetrics.cardPadding)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(scam.localizedTitle(lang)), \(scam.localizedSubtitle(lang))")
            .accessibilityHint(isExpanded ? lang.tr("antiScam.expanded") : lang.tr("antiScam.collapsed"))

            if isExpanded {
                Divider().background(Color.divider)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(lang.tr("antiScam.typicalScript"))
                            .font(.title2Elderly)
                            .foregroundColor(.statusError)
                        Spacer()
                        Button {
                            // 朗读语言跟翻译页保持一致：用用户设置的偏好方言对应的 locale
                            speech.toggleRestartingPlayback(scriptText, language: speechLocale)
                        } label: {
                            Image(systemName: isSpeaking ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .foregroundColor(.statusError)
                                .frame(width: ElderlyMetrics.minTapTarget, height: ElderlyMetrics.minTapTarget)
                        }
                        .accessibilityLabel(isSpeaking ? lang.tr("playback.pause") : (speech.isPaused(scriptText) ? lang.tr("playback.restart") : lang.tr("antiScam.readScript")))
                    }
                    Text(scriptText)
                        .font(.bodyElderly)
                        .foregroundColor(.textPrimary)
                        .padding(12)
                        .background(Color.backgroundCard)
                        .cornerRadius(10)

                    HStack {
                        Text(lang.tr("antiScam.howToPrevent"))
                            .font(.title2Elderly)
                            .foregroundColor(.statusSuccess)
                        Spacer()
                        Button {
                            // 朗读语言跟翻译页保持一致：用用户设置的偏好方言对应的 locale
                            speech.toggleRestartingPlayback(tipsText, language: speechLocale)
                        } label: {
                            Image(systemName: isTipsSpeaking ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .foregroundColor(.statusSuccess)
                                .frame(width: ElderlyMetrics.minTapTarget, height: ElderlyMetrics.minTapTarget)
                        }
                        .accessibilityLabel(isTipsSpeaking ? lang.tr("playback.pause") : (speech.isPaused(tipsText) ? lang.tr("playback.restart") : lang.tr("antiScam.readTips")))
                    }
                    ForEach(scam.localizedTips(lang), id: \.self) { tip in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.statusSuccess)
                                .font(.title3)
                            Text(tip)
                                .font(.bodyElderly)
                                .foregroundColor(.textPrimary)
                        }
                    }
                }
                .padding(ElderlyMetrics.cardPadding)
            }
        }
        .elderlyCard()
        .padding(.horizontal, ElderlyMetrics.cardPadding)
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { stopOwnPlayback() }
        }
        .onDisappear { stopOwnPlayback() }
    }

    private func stopOwnPlayback() {
        if speech.isSpeaking(scriptText) || speech.isPaused(scriptText)
            || speech.isSpeaking(tipsText) || speech.isPaused(tipsText) {
            speech.stop()
        }
    }
}

// MARK: - 数据模型

struct ScamType: Identifiable {
    let id = UUID()
    let titleKey: String
    let subtitleKey: String
    let icon: String
    let color: Color
    let scriptKey: String
    let tipKeys: [String]

    func localizedTitle(_ lang: LanguageManager) -> String { lang.tr(titleKey) }
    func localizedSubtitle(_ lang: LanguageManager) -> String { lang.tr(subtitleKey) }
    func localizedScript(_ lang: LanguageManager) -> String { lang.tr(scriptKey) }
    func localizedTips(_ lang: LanguageManager) -> [String] { tipKeys.map { lang.tr($0) } }

    static let all: [ScamType] = [
        ScamType(
            titleKey: "scamType.gov.title",
            subtitleKey: "scamType.gov.subtitle",
            icon: "building.columns.fill",
            color: .statusError,
            scriptKey: "scamType.gov.script",
            tipKeys: ["scamType.gov.tip1", "scamType.gov.tip2", "scamType.gov.tip3"]
        ),
        ScamType(
            titleKey: "scamType.refund.title",
            subtitleKey: "scamType.refund.subtitle",
            icon: "cart.fill",
            color: .statusWarning,
            scriptKey: "scamType.refund.script",
            tipKeys: ["scamType.refund.tip1", "scamType.refund.tip2", "scamType.refund.tip3"]
        ),
        ScamType(
            titleKey: "scamType.invest.title",
            subtitleKey: "scamType.invest.subtitle",
            icon: "chart.line.uptrend.xyaxis",
            color: .statusWarning,
            scriptKey: "scamType.invest.script",
            tipKeys: ["scamType.invest.tip1", "scamType.invest.tip2", "scamType.invest.tip3"]
        ),
        ScamType(
            titleKey: "scamType.family.title",
            subtitleKey: "scamType.family.subtitle",
            icon: "person.2.fill",
            color: .statusWarning,
            scriptKey: "scamType.family.script",
            tipKeys: ["scamType.family.tip1", "scamType.family.tip2", "scamType.family.tip3"]
        ),
        ScamType(
            titleKey: "scamType.gift.title",
            subtitleKey: "scamType.gift.subtitle",
            icon: "gift.fill",
            color: .accentSecondary,
            scriptKey: "scamType.gift.script",
            tipKeys: ["scamType.gift.tip1", "scamType.gift.tip2", "scamType.gift.tip3"]
        ),
        ScamType(
            titleKey: "scamType.romance.title",
            subtitleKey: "scamType.romance.subtitle",
            icon: "heart.fill",
            color: .statusWarning,
            scriptKey: "scamType.romance.script",
            tipKeys: ["scamType.romance.tip1", "scamType.romance.tip2", "scamType.romance.tip3"]
        ),
    ]
}

struct EmergencyContact: Identifiable {
    let id = UUID()
    let nameKey: String
    let number: String
    let icon: String
    let color: Color

    func localizedName(_ lang: LanguageManager) -> String { lang.tr(nameKey) }

    static let all: [EmergencyContact] = [
        EmergencyContact(nameKey: "emergency.police",   number: "110",   icon: "shield.fill",                       color: .statusError),
        EmergencyContact(nameKey: "emergency.antiScam", number: "96110", icon: "exclamationmark.shield.fill",       color: .statusWarning),
        EmergencyContact(nameKey: "emergency.ambulance", number: "120",  icon: "cross.fill",                        color: .statusSuccess),
    ]
}
