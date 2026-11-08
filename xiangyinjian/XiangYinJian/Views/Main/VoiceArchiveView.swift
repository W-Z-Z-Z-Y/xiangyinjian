import SwiftUI
import Combine

// MARK: - 个人多音档案馆
struct VoiceArchiveView: View {
    @EnvironmentObject private var lang: LanguageManager
    @StateObject private var vm = VoiceArchiveViewModel()
    @State private var selectedCategory = "全部"
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private let categories = ["全部", "日常", "亲情", "节日", "故事"]

    var body: some View {
        VStack(spacing: 0) {
            // 统计卡片
            HStack(spacing: 16) {
                StatCard(icon: "waveform.circle.fill", title: "收录数", value: "\(vm.archives.count)")
                StatCard(icon: "person.2.fill", title: "方言数", value: "\(vm.dialectCount)")
                StatCard(icon: "calendar", title: "收录天数", value: "\(vm.dayCount)")
            }
            .padding()
            .background(Color.backgroundPrimary)

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
                .padding(.horizontal)
            }
            .background(Color.backgroundPrimary)
            .padding(.vertical, 8)

            if vm.archives.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(filteredArchives) { card in
                        ArchiveCardRow(card: card) {
                            vm.playCard(card)
                        } onExport: {
                            vm.exportCard(card)
                        } onPlayRepair: {
                            vm.playRepairedCard(card)
                        }
                        .listRowBackground(Color.backgroundCard)
                    }
                    .onDelete { indexSet in
                        vm.deleteArchives(at: indexSet, from: filteredArchives)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, 84, for: .scrollContent)
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("个人多音档案馆")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "搜索春节、红烧肉、童年等标签")
        .searchFocused($searchFocused)
        .keyboardDismissToolbar(isFocused: searchFocused)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { vm.loadArchives() }
        .onReceive(NotificationCenter.default.publisher(for: .voiceMemoriesUpdated)) { _ in vm.loadArchives() }
        .onDisappear { VoiceRecordingPlayer.shared.stop(); SpeechService.shared.stop() }
        .voicePlaybackFeedback()
        .alert(lang.tr("common.alert"), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button(lang.tr("translate.ok"), role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var filteredArchives: [VoiceCard] {
        vm.archives.filter { card in
            (selectedCategory == "全部" || card.category == selectedCategory) &&
            (searchText.isEmpty || card.sourceText.localizedCaseInsensitiveContains(searchText) ||
             card.translatedText.localizedCaseInsensitiveContains(searchText) ||
             card.tags.contains { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    private var emptyView: some View {
        EmptyStatePanel(
            icon: "archivebox",
            title: "档案馆还是空的",
            message: "在声音卡片中点击「存入档案馆」，就能保存家乡声音。"
        )
    }
}

// MARK: - 统计卡片
struct StatCard: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.accentElderly)
            Text(value)
                .font(.title2Elderly)
                .foregroundColor(.textPrimary)
            Text(title)
                .font(.captionElderly)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.backgroundCard)
        .cornerRadius(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value)")
    }
}

// MARK: - 档案卡片行
struct ArchiveCardRow: View {
    @EnvironmentObject private var lang: LanguageManager
    let card: VoiceCard
    let onPlay: () -> Void
    let onExport: () -> Void
    let onPlayRepair: () -> Void
    @ObservedObject private var memory = VoiceMemoryService.shared
    @ObservedObject private var player = VoiceRecordingPlayer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 信息区：合并为一条 VoiceOver 朗读
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(lang.tr("voiceCategory.\(card.category)"))
                        .font(.captionElderly)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.backgroundCard)
                        .foregroundColor(.accentElderly)
                        .cornerRadius(12)

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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(card.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.captionElderly)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.backgroundCard)
                                    .foregroundColor(.accentSecondary)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(infoAccessibilityLabel)

            if memory.repairing.contains(card.id) {
                HStack { ProgressView(); Text("AI 正在降噪，原声可照常播放") }
                    .font(.captionElderly).foregroundStyle(Color.textSecondary)
            }
            if memory.tagging.contains(card.id) {
                Label("正在提取智能标签", systemImage: "tag").font(.captionElderly)
            } else if card.tagMethod != nil {
                Text(card.tagMethod == "ai" ? "AI 智能标签" : "本地智能标签")
                    .font(.captionElderly).foregroundStyle(Color.textSecondary)
            }
            if let message = memory.messages[card.id] {
                Text(message).font(.captionElderly).foregroundStyle(Color.textSecondary)
            }
            if memory.pendingSaveIDs.contains(card.id) {
                Button { memory.retrySaving(card.id) } label: {
                    Label(lang.current == .zh ? "重试保存处理结果" : "Retry saving changes", systemImage: "arrow.clockwise")
                        .font(.bodyElderly).frame(minHeight: ElderlyMetrics.minTapTarget)
                }
                .buttonStyle(.plain)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { playbackButtons }
                VStack(alignment: .leading, spacing: 8) { playbackButtons }
            }
            if !card.hasRepairedAudio && card.hasOriginalAudio {
                Button { memory.repair(card) } label: {
                    Label("AI 修复", systemImage: "waveform.badge.plus")
                        .font(.bodyElderly).frame(minHeight: ElderlyMetrics.minTapTarget)
                }
                .disabled(memory.repairing.contains(card.id))
                .buttonStyle(.plain)
            }
            if card.tagMethod != "ai" {
                Button { memory.generateTags(card) } label: {
                    Label("提取智能标签", systemImage: "tag")
                        .font(.bodyElderly).frame(minHeight: ElderlyMetrics.minTapTarget)
                }
                .disabled(memory.tagging.contains(card.id))
                .buttonStyle(.plain)
            }

        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private var playbackButtons: some View {
        Button(action: onPlay) {
            Label(card.audioFileName != nil && player.playingPath == card.audioFileName ? "停止原声" : (card.hasOriginalAudio ? "原声" : "朗读"), systemImage: "speaker.wave.2")
                .font(.bodyElderly).frame(minHeight: ElderlyMetrics.minTapTarget)
        }.buttonStyle(.plain)
        if card.hasRepairedAudio, let path = card.repairedAudioFileName {
            Button(action: onPlayRepair) {
                Label(player.playingPath == path ? "停止修复版" : "AI 修复版", systemImage: "waveform")
                    .font(.bodyElderly).frame(minHeight: ElderlyMetrics.minTapTarget)
            }.buttonStyle(.plain)
        }
        Button(action: onExport) {
            Label("导出", systemImage: "square.and.arrow.up")
                .font(.bodyElderly).frame(minHeight: ElderlyMetrics.minTapTarget)
        }.buttonStyle(.plain)
    }

    /// 把分类、方言、原文、译文、标签合并成一条自然语句供 VoiceOver 朗读。
    private var infoAccessibilityLabel: String {
        var parts = ["\(card.category)，\(card.dialect)", "原文，\(card.sourceText)", "译文，\(card.translatedText)"]
        if !card.tags.isEmpty {
            parts.append("标签，" + card.tags.joined(separator: "、"))
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - ViewModel
@MainActor
final class VoiceArchiveViewModel: ObservableObject {
    @Published var archives: [VoiceCard] = []
    @Published var errorMessage: String?
    private let speech = SpeechService.shared

    var dialectCount: Int {
        Set(archives.map { $0.dialect }).count
    }

    var dayCount: Int {
        let dates = archives.map { Calendar.current.startOfDay(for: $0.date) }
        return Set(dates).count
    }

    @discardableResult
    func loadArchives() -> Bool {
        guard AppFileStore.canRead([VoiceCard].self, fileName: "voice-archives.json", legacyKey: "voiceArchives") else {
            errorMessage = LanguageManager.shared.current == .zh
                ? "档案暂时无法读取，已保留原有数据，请重试。"
                : "The archive could not be read. Existing data was kept. Please retry."
            return false
        }
        archives = AppFileStore.load([VoiceCard].self,
                                     fileName: "voice-archives.json",
                                     legacyKey: "voiceArchives") ?? []
        let original = archives
        var changed = false
        for index in archives.indices {
            guard archives[index].audioFileName == nil, let data = archives[index].audioData else { continue }
            if let path = AppFileStore.saveMedia(data, directory: "Media/VoiceCards", fileName: archives[index].id.uuidString + ".wav") {
                archives[index].audioFileName = path
                archives[index].audioData = nil
                changed = true
            }
        }
        if changed, !persistArchives(archives) { archives = original }
        return true
    }

    func deleteArchives(at indexSet: IndexSet, from filtered: [VoiceCard]) {
        guard loadArchives() else { return }
        let selectedIDs = indexSet.map { filtered[$0].id }
        let removed = archives.filter { selectedIDs.contains($0.id) }
        let idsToDelete = removed.map(\.id)
        let updated = archives.filter { !idsToDelete.contains($0.id) }
        guard persistArchives(updated) else { return }
        archives = updated
        removeAudioFilesIfUnused(removed)
        NotificationCenter.default.post(name: .voiceMemoriesUpdated, object: nil)
    }

    private func persistArchives(_ updated: [VoiceCard]) -> Bool {
        guard AppFileStore.save(updated,
                          fileName: "voice-archives.json",
                          legacyKey: "voiceArchives") else {
            errorMessage = LanguageManager.shared.current == .zh
                ? "档案保存失败，原有记录和录音已保留，请重试。"
                : "The archive could not be saved. Existing records and recordings were kept. Please retry."
            Haptic.error()
            return false
        }
        errorMessage = nil
        return true
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

    func playRepairedCard(_ card: VoiceCard) {
        guard let path = card.repairedAudioFileName else { return }
        speech.stop()
        VoiceRecordingPlayer.shared.toggle(relativePath: path)
    }

    func exportCard(_ card: VoiceCard) {
        let text = """
        【乡音间·个人多音档案】

        分类：\(card.category)
        方言：\(card.dialect)
        日期：\(card.date.formatted(date: .long, time: .omitted))

        \(card.sourceText)
        ↓
        \(card.translatedText)

        标签：\(card.tags.map { "#\($0)" }.joined(separator: " "))

        —— 珍贵的方言记忆
        """

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        var items: [Any] = [text]
        if let url = AppFileStore.mediaURL(for: card.audioFileName),
           FileManager.default.fileExists(atPath: url.path) {
            items.append(url)
        }
        if let url = AppFileStore.mediaURL(for: card.repairedAudioFileName), FileManager.default.fileExists(atPath: url.path) { items.append(url) }
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = ac.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        rootVC.present(ac, animated: true)
    }

    private func removeAudioFilesIfUnused(_ removed: [VoiceCard]) {
        guard AppFileStore.canRead([VoiceCard].self, fileName: "voice-cards.json", legacyKey: "voiceCards") else { return }
        let cards = AppFileStore.load([VoiceCard].self,
                                      fileName: "voice-cards.json",
                                      legacyKey: "voiceCards") ?? []
        let activePaths = Set((cards + archives).flatMap(\.audioPaths))
        let removable = removed.filter { !VoiceMemoryService.shared.pendingSaveIDs.contains($0.id) }
        for path in removable.flatMap(\.audioPaths) where !activePaths.contains(path) {
            AppFileStore.removeMedia(at: path)
        }
    }
}
