import SwiftUI

// MARK: - 语音指令帮助页

struct VoiceCommandHintView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        NavigationView {
            List {
                Text(lang.tr("voice.help.languageNote"))
                    .font(.captionElderly)
                    .listRowBackground(Color.backgroundCard)
                Section(lang.tr("voice.help.calls")) {
                    CommandHintRow(icon: "phone.fill", text: lang.tr("voice.example.0"), color: .accentElderly)
                    CommandHintRow(icon: "phone.fill", text: lang.tr("voice.example.1"), color: .accentElderly)
                }

                Section(lang.tr("voice.help.video")) {
                    CommandHintRow(icon: "video.fill", text: lang.tr("voice.example.2"), color: .accentElderly)
                    CommandHintRow(icon: "video.fill", text: lang.tr("voice.example.3"), color: .accentElderly)
                }

                Section(lang.tr("tab.translate")) {
                    CommandHintRow(icon: "character.bubble.fill", text: lang.tr("voice.example.4"), color: .accentElderly)
                    CommandHintRow(icon: "character.bubble.fill", text: lang.tr("voice.example.5"), color: .accentElderly)
                }

                Section(lang.tr("voice.help.pages")) {
                    ForEach(VoiceDestination.allCases, id: \.self) { destination in
                        CommandHintRow(icon: "square.grid.2x2", text: lang.current == .zh ? "打开" + destination.rawValue : "打开" + destination.rawValue + " — " + lang.tr("voiceDestination.\(destination.rawValue)"), color: .accentElderly)
                    }
                }
                Section(lang.tr("voice.help.variations")) {
                    ForEach(10..<16, id: \.self) { index in
                        CommandHintRow(icon: "bubble.left", text: lang.tr("voice.example.\(index)"), color: .accentElderly)
                    }
                }
                Section(lang.tr("voice.help.settings")) {
                    ForEach(16..<24, id: \.self) { index in
                        CommandHintRow(icon: "slider.horizontal.3", text: lang.tr("voice.example.\(index)"), color: .accentElderly)
                    }
                }
                Section(lang.tr("voice.help.navigation")) {
                    CommandHintRow(icon: "house.fill", text: lang.tr("voice.example.8"), color: .accentElderly)
                    CommandHintRow(icon: "house.fill", text: lang.tr("voice.example.9"), color: .accentElderly)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .foregroundStyle(Color.textPrimary)
            .navigationTitle(lang.tr("voice.help.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(lang.tr("common.close")) { dismiss() }
                }
            }
        }
    }
}

struct CommandHintRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.bodyElderly)
        }
        .listRowBackground(Color.backgroundCard)
    }
}
