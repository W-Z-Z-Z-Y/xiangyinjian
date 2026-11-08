# API 与密钥配置指南

本指南对应仓库现有接口，官方入口核对日期：2026-11-08。无需把自己的 Key 交给项目作者；将其填写在本机私有配置文件即可。

## 一、需要哪些密钥

| 功能 | 服务 | 本地配置字段 |
|---|---|---|
| 自由句翻译、故事文本/标签提取 | 阿里云百炼，代码使用 `qwen-plus` | `apiKey`、`region` |
| 四川话、闽南语、粤语专用朗读 | 百炼，代码使用 `qwen3-tts-flash` | 同一百炼 `apiKey`、`region` |
| 故事插画 | 百炼，代码使用 `wan2.2-t2i-flash` | 同一百炼 `apiKey`、`region`，需要图像模型权限 |
| 讯飞方言听写 | 讯飞语音听写流式 WebAPI | `iflytekAppID`、`iflytekAPIKey`、`iflytekAPISecret`，三项配套填写 |
| 东北话“子阳”专用朗读 | 讯飞超拟人语音合成 | 使用上述讯飞应用凭据，另需合成服务及 `x4_ziyang_oral` 发音人权限 |
| 离线词库、本地记录、录音 | 本机代码 | 不需要第三方密钥 |
| Apple 系统识别/朗读 | iOS 系统能力 | 不需要此处的云平台 Key，仍需系统权限及相应语音资源 |

只需要某一类云服务时，另一类凭据留空。讯飞三项必须同时填写或全部留空。仅拥有一个有效 Key，不代表所有模型、方言、语音和图像服务都已开通。

## 二、阿里云百炼 Key 在哪获取

1. 登录 [阿里云百炼控制台](https://bailian.console.aliyun.com/)，进入 API Key 管理，选择自己的服务地域并创建 API Key。
2. 复制自己的模型服务 Key；不要使用阿里云账户的 AccessKey ID/Secret 替代它，也不要把专用 Coding Plan Key 当作本项目所有多模态接口都能通用的 Key。
3. 在 `region` 填 `beijing` 或 `singapore`，必须与创建 Key 的地域一致。本项目目前只映射这两个地域。
4. 核对模型可用性、授权和额度。文本、合成及图像服务可能有不同限制；未开通的功能会报授权或额度错误。

官方说明：[获取与配置 API Key](https://help.aliyun.com/zh/model-studio/get-api-key)、[语音音色列表](https://help.aliyun.com/en/model-studio/qwen-tts-voice-list)、[万相文生图 API](https://help.aliyun.com/zh/model-studio/text-to-image-v2-api-reference)。各地域 Key 和接口不能混用。

## 三、讯飞三项凭据在哪获取

1. 登录 [讯飞开放平台控制台](https://console.xfyun.cn/)，创建自己的应用，使用与当前 WebAPI 相匹配的服务。
2. 在应用的“语音听写（流式版）”服务页获取 `APPID`、`APIKey`、`APISecret`，并开通所需方言权限。
3. 将三项分别填入 `iflytekAppID`、`iflytekAPIKey`、`iflytekAPISecret`。它们必须属于同一应用和适用服务，不能与星火等其他产品的不同凭据格式混填。
4. 需要东北话朗读时，另外开通超拟人语音合成及“子阳”发音人权限。代码使用 `x4_ziyang_oral`，听写权限本身不会自动包含此合成权限。

官方说明：[流式语音听写 WebAPI](https://www.xfyun.cn/doc/asr/voicedictation/API.html)、[超拟人语音合成 API](https://www.xfyun.cn/doc/spark/super%20smart-tts.html)。以自己控制台列出的可用能力为准。

## 四、具体填在哪个文件

仓库只提供空模板 `AppConfig/DemoSecrets.example.plist`。先在项目根目录执行：

```sh
cp AppConfig/DemoSecrets.example.plist xiangyinjian/DemoSecrets.local.plist
```

使用 Xcode 或文本编辑器打开 **`xiangyinjian/DemoSecrets.local.plist`**，填写等号右侧对应的 plist 字符串值。结构如下，示例中凭据故意留空：

```xml
<dict>
    <key>apiKey</key>
    <string></string>
    <key>region</key>
    <string>beijing</string>
    <key>iflytekAppID</key>
    <string></string>
    <key>iflytekAPIKey</key>
    <string></string>
    <key>iflytekAPISecret</key>
    <string></string>
</dict>
```

保留原模板的 XML/plist 外层结构和所有字段名称。Key 不带额外空格或换行。不要修改空模板来存储真实值，也不要把配置放到 Swift 文件、Info.plist 或公开构建脚本。

配置文件必须位于应用的 `xiangyinjian` 资源文件夹内。工程使用 Xcode 同步文件夹，创建文件后确认它出现在应用目标的资源中；如果提示缺少配置，检查文件名、路径、目标成员关系以及 Copy Bundle Resources 中是否包含该本地 plist。不要将 example 模板当作实际配置。

## 五、怎么启用和排查

1. 在 Xcode 选择自己的签名团队与 Bundle Identifier。
2. 填好本机配置后重新构建；当前配置在 App 初始化时读取，编辑文件后需重建并重新启动。
3. 云端翻译测试使用不在本地词库内的一整句，否则可能只命中本地词库。
4. 方言专用朗读需要在应用设置中启用对应音色；不配置云服务时可关闭该选项，改用系统音色。

| 报错情况 | 检查内容 |
|---|---|
| 未配置云服务 | 本地文件路径、目标资源、字段是否为空 |
| 配置格式无效 | plist 格式、`region`、讯飞三项是否填全、是否夹带空白 |
| 授权失败 | Key 是否有效、地域是否匹配、服务/方言/音色是否开通 |
| 额度不足 | 自己账号的服务额度和余额 |
| 无法编译 | Xcode 的 SDK 是否满足工程 iOS 26.5 目标，本地 VoiceNoiseRepair 是否仍在相对位置 |

本版本保留开发直连，真实 plist 会进入自己构建的 App 包。不要公开带 Key 的安装包；要正式分发应用，应改为服务端托管或适用的短期凭据方式。[百炼官方客户端密钥提示](https://help.aliyun.com/zh/model-studio/get-api-key)
