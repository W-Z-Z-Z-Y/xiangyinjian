import Foundation

nonisolated enum VoiceCommand: Equatable {
    case call(String)
    case translate(String)
    case videoCall(String)
    case navigate(VoiceDestination)
    case fontSize(Double)
    case voiceGender(Bool)
    case speechSpeed(Float)
    case stopPlayback
    case help
    case goHome
    case unknown(String)
}

nonisolated enum VoiceDestination: String, CaseIterable {
    case settings = "设置", antiScam = "防诈助手", phrases = "常用语", history = "历史记录"
    case voiceCards = "声音卡片", archive = "声音档案馆", storybook = "乡音绘本"
    case tools = "功能", memory = "记忆", dualDialect = "双向对话"
}
