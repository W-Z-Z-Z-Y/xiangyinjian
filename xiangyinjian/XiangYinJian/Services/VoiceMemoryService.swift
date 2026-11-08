import Foundation
import NaturalLanguage
import Combine

nonisolated enum MemoryTagger {
    static func localTags(_ text: String) -> [String] {
        let topics = ["春节", "红烧肉", "童年", "中秋", "端午", "元宵", "重阳", "年夜饭", "饺子", "汤圆", "家乡", "童谣", "儿歌", "奶奶", "爷爷", "孙子", "母亲", "父亲", "小时候", "老照片", "故乡", "生日", "学校", "健康", "看病", "做饭"]
        var tags = topics.filter { text.contains($0) }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            let word = String(text[range])
            if tag == .noun, (2...8).contains(word.count), !tags.contains(word) { tags.append(word) }
            return tags.count < 5
        }
        return Array(tags.prefix(5))
    }
}

@MainActor
final class VoiceMemoryService: ObservableObject {
    static let shared = VoiceMemoryService()
    @Published private(set) var repairing: Set<UUID> = []
    @Published private(set) var tagging: Set<UUID> = []
    @Published private(set) var messages: [UUID: String] = [:]
    @Published private(set) var pendingSaveIDs: Set<UUID> = []
    private let stores = [("voice-cards.json", "voiceCards"), ("voice-archives.json", "voiceArchives")]
    private struct PendingUpdate {
        let file: String
        let key: String
        let transform: (inout VoiceCard) -> Void
    }
    private var pendingUpdates: [UUID: [PendingUpdate]] = [:]

    func enrich(_ card: VoiceCard) {
        generateTags(card)
        if card.hasOriginalAudio, !card.hasRepairedAudio { repair(card) }
    }

    func generateTags(_ card: VoiceCard) {
        if pendingSaveIDs.contains(card.id) { retrySaving(card.id); return }
        guard !tagging.contains(card.id), card.tagMethod != "ai" else { return }
        messages[card.id] = nil
        tagging.insert(card.id)
        Task { [weak self] in
            guard let self else { return }
            defer { tagging.remove(card.id) }
            let text = card.sourceText + " " + card.translatedText
            var tags = MemoryTagger.localTags(text)
            var method = "local"
            if let generated = try? await AIStorybookService().extractMemoryTags(from: text), !generated.isEmpty {
                tags = generated
                method = "ai"
            }
            update(card.id) { $0.tags = tags; $0.tagMethod = method }
        }
    }

    func repair(_ card: VoiceCard) {
        if pendingSaveIDs.contains(card.id) { retrySaving(card.id); return }
        guard !repairing.contains(card.id), !card.hasRepairedAudio else { return }
        guard let url = AppFileStore.mediaURL(for: card.audioFileName), FileManager.default.fileExists(atPath: url.path) else {
            messages[card.id] = "没有原录音，无法修复合成朗读"
            return
        }
        repairing.insert(card.id)
        messages[card.id] = nil
        Task { [weak self] in
            guard let self else { return }
            defer { repairing.remove(card.id) }
            do {
                let data = try await Task.detached(priority: .utility) { try VoiceRepairWorker.repair(url: url) }.value
                // 用户可能在后台处理时删掉录音；不复活已删除的记录。
                guard contains(card.id) else { return }
                guard let path = AppFileStore.saveMedia(data, directory: "Media/VoiceRepairs", fileName: card.id.uuidString + ".wav") else {
                    messages[card.id] = "修复版保存失败，原录音仍保留，请重试"
                    return
                }
                if !update(card.id, transform: { $0.repairedAudioFileName = path }),
                   !pendingSaveIDs.contains(card.id), !isReferenced(path) {
                    AppFileStore.removeMedia(at: path)
                }
            } catch {
                messages[card.id] = "AI 修复未完成，原录音仍保留。请重试（录音最长支持5分钟）。"
            }
        }
    }

    func retrySaving(_ id: UUID) {
        let pending = pendingUpdates.removeValue(forKey: id) ?? []
        var remaining: [PendingUpdate] = []
        var savedAny = false
        for item in pending {
            guard AppFileStore.canRead([VoiceCard].self, fileName: item.file, legacyKey: item.key) else {
                remaining.append(item)
                continue
            }
            var cards = AppFileStore.load([VoiceCard].self, fileName: item.file, legacyKey: item.key) ?? []
            guard let index = cards.firstIndex(where: { $0.id == id }) else { continue }
            item.transform(&cards[index])
            if AppFileStore.save(cards, fileName: item.file, legacyKey: item.key) {
                savedAny = true
            } else {
                remaining.append(item)
            }
        }
        if remaining.isEmpty {
            pendingSaveIDs.remove(id)
            messages[id] = nil
        } else {
            pendingUpdates[id] = remaining
        }
        if savedAny { NotificationCenter.default.post(name: .voiceMemoriesUpdated, object: nil) }
    }

    private func contains(_ id: UUID) -> Bool {
        stores.contains { file, key in
            (AppFileStore.load([VoiceCard].self, fileName: file, legacyKey: key) ?? []).contains { $0.id == id }
        }
    }

    private func isReferenced(_ path: String) -> Bool {
        stores.contains { file, key in
            guard AppFileStore.canRead([VoiceCard].self, fileName: file, legacyKey: key) else { return true }
            return (AppFileStore.load([VoiceCard].self, fileName: file, legacyKey: key) ?? [])
                .contains { $0.audioPaths.contains(path) }
        }
    }
    @discardableResult
    private func update(_ id: UUID, transform: @escaping (inout VoiceCard) -> Void) -> Bool {
        var found = false
        var savedAny = false
        var savedAll = true
        for (file, key) in stores {
            guard AppFileStore.canRead([VoiceCard].self, fileName: file, legacyKey: key) else {
                pendingUpdates[id, default: []].append(PendingUpdate(file: file, key: key, transform: transform))
                pendingSaveIDs.insert(id)
                found = true
                savedAll = false
                continue
            }
            var cards = AppFileStore.load([VoiceCard].self, fileName: file, legacyKey: key) ?? []
            guard let index = cards.firstIndex(where: { $0.id == id }) else { continue }
            transform(&cards[index])
            let saved = AppFileStore.save(cards, fileName: file, legacyKey: key)
            savedAny = savedAny || saved
            savedAll = savedAll && saved
            if !saved {
                pendingUpdates[id, default: []].append(PendingUpdate(file: file, key: key, transform: transform))
                pendingSaveIDs.insert(id)
            }
            found = true
        }
        if found && !savedAll {
            messages[id] = LanguageManager.shared.current == .zh
                ? "部分处理结果未能保存，原录音仍保留，请重试。"
                : "Some changes could not be saved. The original recording is retained. Please retry."
        }
        if savedAny { NotificationCenter.default.post(name: .voiceMemoriesUpdated, object: nil) }
        return found && savedAll
    }
}

extension Notification.Name {
    static let voiceMemoriesUpdated = Notification.Name("voiceMemoriesUpdated")
}
