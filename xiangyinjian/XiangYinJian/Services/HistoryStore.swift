import Foundation

extension Notification.Name {
    static let translationHistoryUpdated = Notification.Name("translationHistoryUpdated")
}

/// App 与 Siri 共用的同步读改写入口；每次操作都基于最新已保存记录。
@MainActor
enum HistoryStore {
    static func load() -> [HistoryRecord] {
        AppFileStore.load([HistoryRecord].self, fileName: "history.json", legacyKey: "history") ?? []
    }

    @discardableResult
    static func add(_ record: HistoryRecord) -> Bool {
        update { records in
            records.removeAll { $0.id == record.id }
            records.insert(record, at: 0)
            // 只限制普通历史数量，收藏不参与自动淘汰。
            var recentCount = 0
            records = records.filter { item in
                if item.isFavorited { return true }
                recentCount += 1
                return recentCount <= 200
            }
        }
    }

    @discardableResult
    static func toggleFavorite(id: UUID) -> Bool {
        update { records in
            guard let index = records.firstIndex(where: { $0.id == id }) else { return }
            records[index].isFavorited.toggle()
        }
    }

    @discardableResult
    static func remove(ids: Set<UUID>) -> Bool {
        update { $0.removeAll { ids.contains($0.id) } }
    }

    @discardableResult
    static func clear() -> Bool {
        update { $0.removeAll() }
    }

    private static func update(_ mutation: (inout [HistoryRecord]) -> Void) -> Bool {
        var records = load()
        mutation(&records)
        guard AppFileStore.save(records, fileName: "history.json", legacyKey: "history") else {
            return false
        }
        NotificationCenter.default.post(name: .translationHistoryUpdated, object: nil)
        return true
    }
}
