import Foundation
import CryptoKit

/// 合成音频按内容和音色保存，磁盘读写在独立 actor 上进行。
actor CloudSpeechAudioCache {
    private let directory: URL?
    private let byteLimit: Int
    private let itemLimit: Int
    private let fileLimit = 20 * 1024 * 1024

    init(directory: URL? = nil, byteLimit: Int = 40 * 1024 * 1024, itemLimit: Int = 128) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("XiangYinJian/Speech", isDirectory: true)
        self.byteLimit = max(1, byteLimit)
        self.itemLimit = max(1, itemLimit)
    }

    func audio(for key: String) -> Data? {
        guard let url = fileURL(for: key),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 44, size <= fileLimit,
              let data = try? Data(contentsOf: url) else { return nil }
        guard let normalized = try? CloudSpeechAudio.normalizedWAV(data), normalized == data else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    /// 同一内容同时完成时保留第一份有效音频，写盘失败仍可播放新音频。
    func store(_ data: Data, for key: String) -> Data {
        if let existing = audio(for: key) { return existing }
        guard data.count <= min(byteLimit, fileLimit),
              let normalized = try? CloudSpeechAudio.normalizedWAV(data), normalized == data,
              let directory, let url = fileURL(for: key) else { return data }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            prune(keeping: url)
        } catch {
            // 缓存不可写不影响本次播放。
        }
        return data
    }

    private func fileURL(for key: String) -> URL? {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(digest + ".wav")
    }

    private func prune(keeping newest: URL) {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
              ) else { return }
        let files = urls.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard url.pathExtension == "wav",
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true, let size = values.fileSize else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }.sorted {
            if $0.url == newest { return false }
            if $1.url == newest { return true }
            return $0.date < $1.date
        }
        var bytes = files.reduce(0) { $0 + $1.size }
        var count = files.count
        for file in files {
            guard bytes > byteLimit || count > itemLimit else { break }
            do {
                try FileManager.default.removeItem(at: file.url)
                bytes -= file.size
                count -= 1
            } catch { continue }
        }
    }
}
