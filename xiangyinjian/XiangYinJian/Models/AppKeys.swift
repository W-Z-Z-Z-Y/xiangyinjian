import Foundation

/// 云端服务状态。比赛演示凭据随应用内置，无需在设置页填写。
@MainActor
enum AppKeys {
    static var iFlytekConfigured: Bool { CloudGateway.shared.asrConfigured }
}
