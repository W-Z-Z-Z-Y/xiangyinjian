import Foundation
import AVFoundation
import Speech

/// 保留句子与段落边界；拼回分段后的原文不会丢字。
nonisolated enum TranslationParagraph {
    static func chunks(_ text: String, limit: Int = 700) -> [String] {
        let characters = Array(text)
        guard limit > 0, characters.count > limit else { return [text] }
        let boundaries: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n", "；", ";"]
        let softBoundaries: Set<Character> = ["，", ",", "、", "：", ":"]
        func isLetterOrNumber(_ character: Character) -> Bool {
            if character.isNumber { return true }
            guard let value = character.asciiValue else { return false }
            return (65...90).contains(value) || (97...122).contains(value)
        }
        func isInternalPeriod(at index: Int) -> Bool {
            characters[index] == "." && index > 0 && index + 1 < characters.count
                && isLetterOrNumber(characters[index - 1]) && isLetterOrNumber(characters[index + 1])
        }
        func isNumericSeparator(at index: Int) -> Bool {
            (characters[index] == "," || characters[index] == ":" || characters[index] == "：")
                && index > 0 && index + 1 < characters.count
                && characters[index - 1].isNumber && characters[index + 1].isNumber
        }
        func isTokenCharacter(at index: Int) -> Bool {
            isLetterOrNumber(characters[index]) || isInternalPeriod(at: index)
                || isNumericSeparator(at: index) || characters[index] == "-" || characters[index] == "_"
        }
        var result: [String] = []
        var start = 0
        while start < characters.count {
            var end = min(start + limit, characters.count)
            if end < characters.count {
                let preferred = start + limit / 2..<end
                if let boundary = preferred.last(where: {
                    boundaries.contains(characters[$0]) && !isInternalPeriod(at: $0)
                }) {
                    end = boundary + 1
                } else if let boundary = preferred.last(where: {
                    characters[$0].isWhitespace
                        || (softBoundaries.contains(characters[$0]) && !isNumericSeparator(at: $0))
                }) {
                    end = boundary + 1
                } else if isTokenCharacter(at: end - 1), isTokenCharacter(at: end) {
                    // 硬边界落在短编号/小数/域名内部时，将整个词留到下一段。
                    // 超过 limit 的单个长词仍按上限切，避免空段或无限循环。
                    var tokenStart = end - 1
                    while tokenStart > start, isTokenCharacter(at: tokenStart - 1) { tokenStart -= 1 }
                    if tokenStart > start { end = tokenStart }
                }
            }
            result.append(String(characters[start..<end]))
            start = end
        }
        return result
    }
}

/// 讯飞 rg 表示识别结果的 sn 区间，不是汉字下标。
nonisolated struct IATTranscriptAccumulator {
    private var pieces: [Int: String] = [:]
    mutating func apply(sequence: Int, text: String, replacing range: [Int]? = nil) {
        if let range, range.count == 2 {
            for key in Array(pieces.keys) where key >= range[0] && key <= range[1] { pieces[key] = nil }
        }
        pieces[sequence] = text
    }
    var text: String { pieces.keys.sorted().compactMap { pieces[$0] }.joined() }
}

/// 麦克风不随识别分段停下；音频线程切换请求时受同一把锁保护。
nonisolated final class SpeechRequestRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var frames: [ObjectIdentifier: UInt32] = [:]
    func replace(with next: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        request = next
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        if let request {
            frames[ObjectIdentifier(request), default: 0] += buffer.frameLength
            request.append(buffer)
        }
    }
    func hasAudio(for request: SFSpeechAudioBufferRecognitionRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return frames[ObjectIdentifier(request), default: 0] > 0
    }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        request = nil
        frames = [:]
    }
}

nonisolated final class CapturedAudioQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ value: Data) { lock.lock(); data.append(value); lock.unlock() }
    func drain() -> Data {
        lock.lock(); defer { lock.unlock() }
        let result = data
        data = Data()
        return result
    }
}

/// 45 秒切换一个 Apple 识别请求，旧段仍可回传最终结果。
/// 分段只切换识别器；完整原录音由调用方的麦克风缓冲持续保存。
@MainActor
final class AppleParagraphRecognition {
    let relay = SpeechRequestRelay()
    private var recognizer: SFSpeechRecognizer?
    private var requests: [Int: SFSpeechAudioBufferRecognitionRequest] = [:]
    private var tasks: [Int: SFSpeechRecognitionTask] = [:]
    private var pieces: [Int: String] = [:]
    private var finished: Set<Int> = []
    private var current = 0
    private var generation = 0
    private var acceptingAudio = false
    private var failed = false
    private var prefix = ""
    private var rotationTimer: Timer?
    private var onText: ((String) -> Void)?
    private var onError: ((Error) -> Void)?

    func start(recognizer: SFSpeechRecognizer, prefix: String = "",
               onText: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
        cancel()
        self.recognizer = recognizer
        self.prefix = prefix
        self.onText = onText
        self.onError = onError
        acceptingAudio = true
        failed = false
        startSegment()
    }

    private func startSegment() {
        guard acceptingAudio, let recognizer else { return }
        rotationTimer?.invalidate()
        let previous = requests[current]
        current += 1
        let index = current
        let token = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        requests[index] = request
        // 先接上下一段，再结束上一段，不在尾句等待期间停止收音。
        relay.replace(with: request)
        previous?.endAudio()
        tasks[index] = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == token, !self.finished.contains(index) else { return }
                if let text = result?.bestTranscription.formattedString {
                    self.pieces[index] = text
                    self.onText?(self.prefix + self.pieces.keys.sorted().compactMap { self.pieces[$0] }.joined())
                }
                if result?.isFinal == true {
                    self.finished.insert(index)
                    if self.acceptingAudio && index == self.current { self.startSegment() }
                } else if let error {
                    self.finished.insert(index)
                    self.failed = true
                    self.acceptingAudio = false
                    self.relay.replace(with: nil)
                    self.rotationTimer?.invalidate()
                    self.onError?(error)
                }
            }
        }
        let timer = Timer(timeInterval: 45, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token, self.current == index else { return }
                self.startSegment()
            }
        }
        rotationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func finish() async -> Bool {
        let token = generation
        acceptingAudio = false
        rotationTimer?.invalidate()
        rotationTimer = nil
        relay.replace(with: nil)
        for (index, request) in requests where !finished.contains(index) {
            if relay.hasAudio(for: request) { request.endAudio() }
            else { finished.insert(index); tasks[index]?.cancel() }
        }
        for _ in 0..<100 {
            guard generation == token else { return false }
            if requests.keys.allSatisfy({ finished.contains($0) }) { return !failed }
            do { try await Task.sleep(nanoseconds: 50_000_000) }
            catch { return false }
        }
        return false
    }

    func cancel() {
        generation += 1
        acceptingAudio = false
        rotationTimer?.invalidate()
        rotationTimer = nil
        relay.replace(with: nil)
        relay.clear()
        for task in tasks.values { task.cancel() }
        requests = [:]; tasks = [:]; pieces = [:]; finished = []
        current = 0
        recognizer = nil
        onText = nil; onError = nil
    }
}
