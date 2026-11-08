# 乡音间（xiangyinjian）

SwiftUI iOS 项目，保留离线方言词库、常用语、翻译记录、录音与声音档案、系统朗读、语音指令，以及可选的云端翻译、方言语音和 AI 故事能力。

此目录是独立的 GitHub 源码版，不含真实密钥、用户数据或安装包。云服务适配器保留，由使用者填写自己的配置；不提供共享 Key。

## 环境要求

- macOS 与 Xcode；原工程最低系统目标为 **iOS 26.5**，需要安装包含对应或更新 iOS SDK 的 Xcode。工程原有 Swift 并发和界面实现未降级改写。
- 本地 Swift Package `VoiceNoiseRepair` 已包含在仓库中，通过相对路径引用，不依赖原作者机器目录。
- 在 Xcode 的 Signing & Capabilities 中选择自己的开发团队；按需将默认 `com.example.xiangyinjian` 修改为自己的 Bundle Identifier。

## 打开和使用

1. 打开 `xiangyinjian.xcodeproj`，选择 `xiangyinjian` scheme。
2. 不需要第三方 Key 即可使用已收录词句的离线翻译、常用语、翻译历史及本地录音等功能。例如普通话“你好”翻译为四川话，可命中内置词库。
3. 系统语音识别与朗读使用 Apple 系统能力，不需要另申请本项目的 API Key；可用语言、语音包、联网与权限要求取决于设备和系统。系统能力不能一概视为完全离线。
4. 若不配置云服务，在设置中关闭“方言专用音色”，使用系统朗读。自由句翻译、云端专用方言音色及 AI 生成需要下一步配置。
5. 按 [API 与密钥配置指南](docs/API配置指南.md) 复制空模板并填写自己的密钥，重新构建应用。

在项目根目录执行以下命令可创建本机配置：

```sh
cp AppConfig/DemoSecrets.example.plist xiangyinjian/DemoSecrets.local.plist
```

模板位于 AppConfig，真实本地配置位于应用资源组下，命名和路径必须准确。真实配置已被 `.gitignore` 排除，不需要上传给其他使用者。

## 目录

```text
xiangyinjian.xcodeproj/          Xcode 工程
AppConfig/Info.plist             应用权限及元数据
AppConfig/DemoSecrets.example.plist  空配置模板，可上传
xiangyinjian/XiangYinJian/       Swift 源码
xiangyinjian/Assets.xcassets/    应用资源
VoiceNoiseRepair/               本地 RNNoise C 降噪包及原许可证
docs/API配置指南.md              密钥填写位置与官方获取入口
```

当前界面由 ContentView、ToolsHubView、MemoryHubView 等组织；已移除未被引用的旧 MoreView 聚合页，保留在用的功能和模块。第三方声明位于 `xiangyinjian/XiangYinJian/ThirdPartyNotices.txt` 与 `VoiceNoiseRepair/COPYING`。

## 配置与分发边界

这个版本保留原有开发演示直连方式：本地填写的 plist 会随你构建的 App 打包。`.gitignore` 保护 Git 仓库，不保护安装包中的长期服务密钥。公开源码时只上传空模板；不要把带真实密钥的 IPA 作为公开发行附件。正式分发给他人使用，应另做服务端密钥托管或短期凭据方案。

## 验证范围

已检查配置模板的 plist 格式、工程的相对依赖和资源引用，并复核了离线词库优先、缺少云配置时的处理路径。当前整理环境为 Windows，没有 Xcode，未编译此 iOS 工程，也未启动模拟器或真机。云服务未经真实 Key 调用，最终构建和云功能需要使用者在自己的 macOS/Xcode 及服务账户下验证。

在具备对应 SDK 的 Mac 上，可以运行以下命令仅检查编译，不启动模拟器或真机：

```sh
xcodebuild -project xiangyinjian.xcodeproj -scheme xiangyinjian -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```
