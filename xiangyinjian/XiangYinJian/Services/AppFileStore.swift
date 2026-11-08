import Foundation

/// 用 Application Support 中的独立 JSON 文件保存用户数据。
///
/// 与 UserDefaults 相比，文件存储更适合不断增长的历史、绘本和声音卡片。
/// 首次读取时会自动从旧 UserDefaults 数据迁移，保持旧版用户数据兼容。
enum AppFileStore {
    private static let appFolderName = "XiangYinJian"

    private static var rootURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = base.appendingPathComponent(appFolderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            return folder
        } catch {
            return nil
        }
    }

    static func load<T: Codable>(_ type: T.Type, fileName: String, legacyKey: String) -> T? {
        let decoder = JSONDecoder()
        if let url = rootURL?.appendingPathComponent(fileName),
           let data = try? Data(contentsOf: url),
           let value = try? decoder.decode(type, from: data) {
            return value
        }

        guard let legacy = UserDefaults.standard.data(forKey: legacyKey),
              let value = try? decoder.decode(type, from: legacy) else {
            return nil
        }
        _ = save(value, fileName: fileName, legacyKey: legacyKey)
        return value
    }

    @discardableResult
    static func save<T: Codable>(_ value: T, fileName: String, legacyKey: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }

        // 失败时保留已提交的数据，由调用方保留输入并提示重试。
        guard let url = rootURL?.appendingPathComponent(fileName) else { return false }
        // load 的 nil 也可能表示原文件损坏，不能把随后构造的空列表当作最新数据覆盖它。
        guard canRead(T.self, fileName: fileName, legacyKey: legacyKey) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            // 迁移完成后不保留过期副本，避免文件缺失时复活已删除的内容。
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return true
        } catch {
            return false
        }
    }

    /// 不存在是正常的首次保存；读取失败则不能覆盖记录，也不能据此清理共享媒体。
    static func canRead<T: Codable>(_ type: T.Type, fileName: String, legacyKey: String) -> Bool {
        guard let url = rootURL?.appendingPathComponent(fileName) else { return false }
        let decoder = JSONDecoder()
        if FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url) else { return false }
            return (try? decoder.decode(type, from: data)) != nil
        }
        if let legacy = UserDefaults.standard.data(forKey: legacyKey) {
            return (try? decoder.decode(type, from: legacy)) != nil
        }
        return UserDefaults.standard.object(forKey: legacyKey) == nil
    }

    static func saveMedia(_ data: Data, directory: String, fileName: String) -> String? {
        guard let rootURL else { return nil }
        let folder = rootURL.appendingPathComponent(directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            let url = folder.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            return "\(directory)/\(fileName)"
        } catch {
            return nil
        }
    }

    static func mediaURL(for relativePath: String?) -> URL? {
        guard let relativePath, !relativePath.isEmpty, let rootURL else { return nil }
        return rootURL.appendingPathComponent(relativePath)
    }

    static func removeMedia(at relativePath: String?) {
        guard let url = mediaURL(for: relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
