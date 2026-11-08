import SwiftUI
import Combine

// MARK: - 声音卡片列表页
struct VoiceCardsView: View {
    @EnvironmentObject private var lang: LanguageManager
    @StateObject private var vm = VoiceCardsViewModel()
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var selectedCategory = "全部"
    @State private var showClearConfirmation = false

    private let categories = ["全部", "日常", "亲情", "节日", "故事"]

    var body: some View {
        ZStack {
            if vm.cards.isEmpty {
                emptyView
            } else {
                VStack(spacing: 0) {
                    // 分类筛选
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(categories, id: \.self) { category in
                                Button {
                                    selectedCategory = category
                                } label: {
                                    Text(category == "全部" ? (lang.current == .zh ? "全部" : "All") : lang.tr("voiceCategory.\(category)"))
                                        .font(.bodyElderly)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(selectedCategory == category ? Color.accentElderly : Color.backgroundCard)
                                        .foregroundColor(selectedCategory == category ? .backgroundPrimary : .textPrimary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color.backgroundPrimary)

                    List {
                        ForEach(filteredCards) { card in
                            VoiceCardRow(card: card) {
                                vm.playCard(card)
                            } onShare: {
                                vm.shareCard(card)
                            } onAddToArchive: {
                                vm.addToArchive(card)
                            }
                            .listRowBackground(Color.backgroundCard)
                        }
                        .onDelete { indexSet in
                            vm.deleteCards(at: indexSet, from: filteredCards)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, 84, for: .scrollContent)
                    .searchable(text: $searchText, prompt: "搜索声音卡片")
                    .searchFocused($searchFocused)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("声音卡片")
        .navigationBarTitleDisplayMode(.large)
        .keyboardDismissToolbar(isFocused: searchFocused)
        .alert(lang.tr("common.alert"), isPresented: Binding(
            get: { vm.archiveFeedbackKey != nil || vm.errorMessage != nil },
            set: { if !$0 { vm.archiveFeedbackKey = nil; vm.errorMessage = nil } }
        )) {
            Button(lang.tr("translate.ok"), role: .cancel) { vm.archiveFeedbackKey = nil; vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? lang.tr(vm.archiveFeedbackKey ?? "archive.saved"))
        }
        .voicePlaybackFeedback()
        .confirmationDialog(lang.current == .zh ? "清空全部声音卡片？" : "Clear all voice cards?",
                            isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button(lang.current == .zh ? "清空" : "Clear", role: .destructive) { vm.clearAll() }
            Button(lang.current == .zh ? "取消" : "Cancel", role: .cancel) {}
        } message: {
            Text(lang.current == .zh
                 ? "将删除 \(vm.cards.count) 张卡片及未存入档案馆的录音，无法撤销。档案馆中的声音仍保留。"
                 : "This removes \(vm.cards.count) cards and recordings that are not archived. This cannot be undone. Archived memories are kept.")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: VoiceArchiveView()) {
                    Label("档案馆", systemImage: "archivebox.fill")
                }
            }
            if !vm.cards.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Text("清空")
                    }
                }
            }
        }
        .onAppear { vm.loadCards() }
        .onReceive(NotificationCenter.default.publisher(for: .voiceMemoriesUpdated)) { _ in vm.loadCards() }
        .onDisappear { VoiceRecordingPlayer.shared.stop(); SpeechService.shared.stop() }
    }

    private var filteredCards: [VoiceCard] {
        var cards = vm.cards

        // 分类筛选
        if selectedCategory != "全部" {
            cards = cards.filter { $0.category == selectedCategory }
        }

        // 搜索筛选
        if !searchText.isEmpty {
            cards = cards.filter {
                $0.sourceText.contains(searchText) ||
                $0.translatedText.contains(searchText)
            }
        }

        return cards
    }

    private var emptyView: some View {
        EmptyStatePanel(
            icon: "waveform.circle",
            title: "还没有声音卡片",
            message: "翻译后点击「保存声音」即可创建。"
        )
    }
}

struct EmptyStatePanel<Action: View>: View {
    let icon: String
    let title: String
    let message: String
    let action: () -> Action

    init(icon: String, title: String, message: String, @ViewBuilder action: @escaping () -> Action) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 64, weight: .regular))
                .foregroundColor(.accentElderly)
                .frame(width: 88, height: 88)
                .background(Color.backgroundCard)
                .clipShape(Circle())

            Text(title)
                .font(.title2Elderly)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(message)
                .font(.bodyElderly)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            action()
        }
        .padding(24)
        .frame(maxWidth: 340)
        .elderlyCard()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 88)
    }
}

extension EmptyStatePanel where Action == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) {
            EmptyView()
        }
    }
}

// MARK: - 声音卡片行
struct VoiceCardRow: View {
    @EnvironmentObject private var lang: LanguageManager
    let card: VoiceCard
    let onPlay: () -> Void
    let onShare: () -> Void
    let onAddToArchive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 信息区：合并为一条 VoiceOver 朗读
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.accentElderly)
                    Text(card.dialect)
                        .font(.captionElderly)
                        .foregroundColor(.textSecondary)

                    Spacer()
                    Text(lang.memoryDate(card.date))
                        .font(.captionElderly)
                        .foregroundColor(.textTertiary)
                }

                Text(card.sourceText)
                    .font(.bodyElderly)
                    .foregroundColor(.textPrimary)

                Text(card.translatedText)
                    .font(.title3Elderly)
                    .foregroundColor(.accentElderly)

                if !card.tags.isEmpty {
                    Label("记忆标签：" + card.tags.joined(separator: "、"), systemImage: "tag")
                        .font(.captionElderly)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(infoAccessibilityLabel)

            HStack(spacing: 12) {
                Button(action: onPlay) {
                    Label(card.hasOriginalAudio ? "原声" : "朗读",
                          systemImage: card.hasOriginalAudio ? "waveform.circle.fill" : "speaker.wave.2.fill")
                        .font(.bodyElderly)
                        .foregroundColor(.accentElderly)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.hasOriginalAudio
                                    ? "播放\(card.dialect)真实原声"
                                    : "播放\(card.translatedDialect ?? card.dialect)合成读音")

                Button(action: onShare) {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .font(.bodyElderly)
                        .foregroundColor(.accentSecondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("分享这张声音卡片")

                Button(action: onAddToArchive) {
                    Label("存入档案馆", systemImage: "archivebox")
                        .font(.bodyElderly)
                        .foregroundColor(.statusSuccess)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("把这张卡片存入档案馆")
            }
        }
        .padding(.vertical, 8)
    }

    /// 把方言、原文、译文、标签合并成一条自然语句供 VoiceOver 朗读。
    private var infoAccessibilityLabel: String {
        var parts = ["\(card.dialect)声音卡片", "原文，\(card.sourceText)", "译文，\(card.translatedText)"]
        if !card.tags.isEmpty {
            parts.append("标签，" + card.tags.joined(separator: "、"))
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - ViewModel
@MainActor
final class VoiceCardsViewModel: ObservableObject {
    @Published var cards: [VoiceCard] = []
    @Published var archiveFeedbackKey: String?
    @Published var errorMessage: String?
    private let speech = SpeechService.shared

    @discardableResult
    func loadCards() -> Bool {
        guard AppFileStore.canRead([VoiceCard].self, fileName: "voice-cards.json", legacyKey: "voiceCards") else {
            errorMessage = LanguageManager.shared.current == .zh
                ? "声音卡片暂时无法读取，已保留原有数据，请重试。"
                : "Voice cards could not be read. Existing data was kept. Please retry."
            return false
        }
        cards = AppFileStore.load([VoiceCard].self,
                                  fileName: "voice-cards.json",
                                  legacyKey: "voiceCards") ?? []
        migrateInlineAudioIfNeeded()
        return true
    }

    func deleteCards(at indexSet: IndexSet, from filtered: [VoiceCard]) {
        guard loadCards() else { return }
        let selectedIDs = indexSet.map { filtered[$0].id }
        let removed = cards.filter { selectedIDs.contains($0.id) }
        let idsToDelete = removed.map(\.id)
        let updated = cards.filter { !idsToDelete.contains($0.id) }
        guard persistCards(updated) else { return }
        cards = updated
        removeAudioFilesIfUnarchived(removed)
        NotificationCenter.default.post(name: .voiceMemoriesUpdated, object: nil)
    }

    func clearAll() {
        guard loadCards() else { return }
        let removed = cards
        guard persistCards([]) else { return }
        cards = []
        removeAudioFilesIfUnarchived(removed)
        VoiceRecordingPlayer.shared.stop()
        speech.stop()
        NotificationCenter.default.post(name: .voiceMemoriesUpdated, object: nil)
    }

    func playCard(_ card: VoiceCard) {
        if let path = card.audioFileName {
            speech.stop()
            VoiceRecordingPlayer.shared.toggle(relativePath: path)
            return
        }
        if card.hasOriginalAudio {
            speech.stop()
            VoiceRecordingPlayer.shared.reportMissingAudio()
            return
        }
        VoiceRecordingPlayer.shared.stop()
        speech.speak(card.translatedText, dialect: card.translatedDialect ?? card.dialect)
    }

    func shareCard(_ card: VoiceCard) {
        let text = """
        【乡音间·声音卡片】

        \(card.sourceText)
        ↓
        [\(card.translatedDialect ?? card.dialect)] \(card.translatedText)

        """

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        var items: [Any] = [text]
        if let url = AppFileStore.mediaURL(for: card.audioFileName),
           FileManager.default.fileExists(atPath: url.path) {
            items.append(url)
        }
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = ac.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        rootVC.present(ac, animated: true)
    }

    func addToArchive(_ card: VoiceCard) {
        guard loadCards() else { return }
        guard let card = cards.first(where: { $0.id == card.id }),
              AppFileStore.canRead([VoiceCard].self, fileName: "voice-archives.json", legacyKey: "voiceArchives") else {
            archiveFeedbackKey = "archive.saveFailed"
            Haptic.error()
            return
        }
        var archives = loadArchives()

        guard !archives.contains(where: { $0.id == card.id }) else {
            archiveFeedbackKey = "archive.alreadySaved"
            Haptic.tap()
            return
        }

        archives.insert(card, at: 0)
        let saved = AppFileStore.save(archives,
                                      fileName: "voice-archives.json",
                                      legacyKey: "voiceArchives")
        guard saved else {
            archiveFeedbackKey = "archive.saveFailed"
            Haptic.error()
            return
        }
        archiveFeedbackKey = "archive.saved"
        Haptic.success()
        NotificationCenter.default.post(name: .voiceMemoriesUpdated, object: nil)
        VoiceMemoryService.shared.enrich(card)
    }

    func loadArchives() -> [VoiceCard] {
        AppFileStore.load([VoiceCard].self,
                          fileName: "voice-archives.json",
                          legacyKey: "voiceArchives") ?? []
    }

    private func persistCards(_ updated: [VoiceCard]) -> Bool {
        guard AppFileStore.save(updated, fileName: "voice-cards.json", legacyKey: "voiceCards") else {
            errorMessage = LanguageManager.shared.current == .zh
                ? "声音卡片保存失败，原有记录和录音已保留，请重试。"
                : "Voice cards could not be saved. Existing records and recordings were kept. Please retry."
            Haptic.error()
            return false
        }
        errorMessage = nil
        return true
    }

    private func migrateInlineAudioIfNeeded() {
        let original = cards
        var changed = false
        for index in cards.indices {
            guard cards[index].audioFileName == nil, let data = cards[index].audioData else { continue }
            cards[index].audioFileName = AppFileStore.saveMedia(
                data,
                directory: "Media/VoiceCards",
                fileName: "\(cards[index].id.uuidString).wav"
            )
            if cards[index].audioFileName != nil {
                cards[index].audioData = nil
                changed = true
            }
        }
        if changed, !persistCards(cards) { cards = original }
    }

    private func removeAudioFilesIfUnarchived(_ removed: [VoiceCard]) {
        guard AppFileStore.canRead([VoiceCard].self, fileName: "voice-archives.json", legacyKey: "voiceArchives") else { return }
        let archivedPaths = Set(loadArchives().flatMap(\.audioPaths))
        let removable = removed.filter { !VoiceMemoryService.shared.pendingSaveIDs.contains($0.id) }
        for path in removable.flatMap(\.audioPaths) where !archivedPaths.contains(path) {
            AppFileStore.removeMedia(at: path)
        }
    }
}

// MARK: - VoiceCard Model (多音声卡片)
struct VoiceCard: Identifiable, Codable {
    let id: UUID
    let sourceText: String
    let translatedText: String
    let dialect: String
    let date: Date
    var audioData: Data?           // 旧版内联音频，读取后会自动迁移到文件
    var audioFileName: String?     // Application Support 中的相对路径
    var repairedAudioFileName: String? = nil
    var tagMethod: String? = nil
    var audioPaths: [String] { [audioFileName, repairedAudioFileName].compactMap { $0 } }
    var category: String = "日常"  // 分类：日常、亲情、节日、故事
    var tags: [String] = []        // 标签：如"童谣"、"问候"、"家乡话"
    var translatedDialect: String? = nil

    var hasOriginalAudio: Bool {
        audioFileName != nil || audioData != nil
    }

    var hasRepairedAudio: Bool {
        guard let url = AppFileStore.mediaURL(for: repairedAudioFileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

private struct VoicePlaybackFeedback: ViewModifier {
    @ObservedObject private var player = VoiceRecordingPlayer.shared
    @ObservedObject private var lang = LanguageManager.shared

    func body(content: Content) -> some View {
        content.alert(lang.tr("common.alert"), isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )) {
            Button(lang.tr("translate.ok"), role: .cancel) { player.errorMessage = nil }
        } message: {
            Text(player.errorMessage ?? "")
        }
    }
}

extension View {
    func voicePlaybackFeedback() -> some View { modifier(VoicePlaybackFeedback()) }
}
