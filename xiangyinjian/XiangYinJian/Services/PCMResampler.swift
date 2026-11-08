import Foundation
import AVFoundation

/// 把 `AVAudioEngine` 采集到的设备原生音频，转换成讯飞要求的
/// **16kHz / 16bit / 单声道 PCM**。
///
/// 为什么需要这个：`AVAudioEngine.inputNode` 采集的是设备原生格式，iPhone 上
/// 通常是 44.1kHz 或 48kHz、且可能是多声道。讯飞只接受 16k 单声道 16bit，
/// 直接把原始 buffer 发过去会得到乱码识别结果（而且不报错，极难排查）。
///
/// 为什么不能用 tap 直接指定 16k：`installTap` 的格式必须与节点输出格式一致，
/// 传 16k 会让引擎抛 NSException（"Failed to create tap due to format
/// mismatch"）并终止进程。转换只能自己做。
final class PCMResampler {

    /// 目标格式：16kHz / 16bit / 单声道 / 交错
    static let targetSampleRate: Double = 16000

    static var targetFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )
    }

    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    /// 输入格式只在首次见到时记录，用于判断是否需要重建 converter
    private var inputFormat: AVAudioFormat?
    /// 最近一次转换失败的原因（诊断用）。
    ///
    /// 重采样失败是完全静默的——调用方只看到 nil，拿不到任何线索。
    /// 把它记下来，界面就能直接显示「为什么没转出音频」。
    private(set) var lastFailure: String?

    init?() {
        guard let fmt = Self.targetFormat else { return nil }
        self.outputFormat = fmt
    }

    /// 转换一次音频 buffer，返回 16k 单声道 Int16 PCM 数据。
    ///
    /// - Returns: 转换后的 PCM 字节；若该 buffer 无法转换则返回 nil。
    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.frameLength > 0 else {
            lastFailure = "空 buffer"
            return nil
        }

        // 输入格式变了（如切换了音频路由：拔耳机、连蓝牙），重建 converter
        if inputFormat == nil || inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            converter?.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        }
        guard let converter else {
            lastFailure = "converter 构造失败 \(buffer.format) → \(outputFormat)"
            return nil
        }

        // 输出容量按采样率比值放大，并留 10% 余量吸收重采样抖动
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio * 1.1) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            lastFailure = "输出 buffer 分配失败 capacity=\(capacity)"
            return nil
        }
        // 必须显式设置 frameLength：AVAudioPCMBuffer 初始化后它为 0，
        // 而 converter 是往「frameLength 指定的可写区间」里写的。
        out.frameLength = capacity

        var provided = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if provided {
                // ⚠️ 这里必须是 .noDataNow 而不是 .endOfStream。
                //
                // .endOfStream 的含义是「输入流已结束」，converter 收到后进入
                // 终结状态，**此后每次调用都返回 .error**。症状极具误导性：
                // 第一次转换成功，之后全部失败，于是永远只录到 0.1 秒音频，
                // 服务端一个字都收不到，而且不抛任何异常。
                // .noDataNow 才是「本次暂时没有更多输入，但流还在继续」。
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error else {
            lastFailure = "convert 返回 .error — "
                + (error.map { "\($0.domain)#\($0.code) \($0.localizedDescription)" } ?? "无 error 对象")
            return nil
        }
        guard out.frameLength > 0 else {
            lastFailure = "convert status=\(status.rawValue) 但产出 0 帧"
            return nil
        }
        lastFailure = nil
        return data(from: out)
    }

    /// 从 Int16 交错 buffer 取出字节
    private func data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let channel = buffer.int16ChannelData else { return nil }
        let frames = Int(buffer.frameLength)
        // 单声道交错即一段连续 Int16
        return Data(bytes: channel[0], count: frames * MemoryLayout<Int16>.size)
    }

    /// 重置内部状态（每次开始新会话时调用）
    func reset() {
        converter = nil
        inputFormat = nil
        lastFailure = nil
    }
}
