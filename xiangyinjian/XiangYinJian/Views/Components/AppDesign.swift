import SwiftUI
import UIKit

@MainActor
enum AppAppearance {
    static func configure() {
        let background = UIColor(Color.backgroundPrimary)
        let foreground = UIColor(Color.textPrimary)
        let secondary = UIColor(Color.textSecondary)
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = background
        navigation.titleTextAttributes = [.foregroundColor: foreground]
        navigation.largeTitleTextAttributes = [.foregroundColor: foreground]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UISegmentedControl.appearance().selectedSegmentTintColor = foreground
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: background], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: secondary], for: .normal)
    }
}

/// 主页面共用标题和留白，字号仍跟随适老设置。
struct AppPageHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.titleElderly).foregroundStyle(Color.textPrimary)
                Text(subtitle).font(.captionElderly).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.accentElderly)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
    }
}

/// 卡片与页面同色，用细线保留层级。
struct AppCardStyle: ViewModifier {
    var radius: CGFloat = ElderlyMetrics.cornerRadius

    func body(content: Content) -> some View {
        content
            .background(Color.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.divider, lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func elderlyCard(radius: CGFloat = ElderlyMetrics.cornerRadius) -> some View {
        modifier(AppCardStyle(radius: radius))
    }

    func keyboardDismissToolbar(isFocused: Bool) -> some View {
        modifier(KeyboardDismissToolbar(isFocused: isFocused))
    }
}

@MainActor
enum AppKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// 只为当前正在输入的页面显示，避免不同导航层级重复添加键盘按钮。
private struct KeyboardDismissToolbar: ViewModifier {
    @EnvironmentObject private var lang: LanguageManager
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                if isFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            Haptic.tap()
                            AppKeyboard.dismiss()
                        } label: {
                            Label(lang.tr("keyboard.done"), systemImage: "keyboard.chevron.compact.down")
                                .font(.bodyElderly)
                                .frame(minHeight: 44)
                        }
                    }
                }
            }
            .onSubmit { AppKeyboard.dismiss() }
    }
}

struct AppCardGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var columns: [GridItem] {
        let scale = ThemeManager.shared.fontScale
        let count = dynamicTypeSize.isAccessibilitySize || scale > 1.2 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) { content }
    }
}

/// 静态声音图形，仅作装饰；录音时仍使用实际音量波形。
struct VoiceWaveformMark: View {
    private let heights: [CGFloat] = [8, 13, 9, 18, 26, 38, 52, 42, 27, 17, 10, 19, 31, 46, 54, 39, 24, 16, 10]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule().fill(Color.accentElderly)
                    .frame(width: 3, height: heights[index])
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .accessibilityHidden(true)
    }
}

/// 功能卡片按下时着色，并在一次按压开始时给出一次触感。
struct FeatureCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: ElderlyMetrics.cornerRadius, style: .continuous)
                    .fill(Color.accentElderly.opacity(configuration.isPressed ? 0.28 : 0))
                    .overlay {
                        RoundedRectangle(cornerRadius: ElderlyMetrics.cornerRadius, style: .continuous)
                            .stroke(Color.accentElderly.opacity(configuration.isPressed ? 1 : 0), lineWidth: 1.5)
                    }
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptic.select() }
            }
    }
}
