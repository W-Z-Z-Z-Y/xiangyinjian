import SwiftUI

/// 首次启动引导页（3 步）
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var lang: LanguageManager
    @State private var step = 0

    private let steps: [(icon: String, titleKey: String, descKey: String)] = [
        ("globe",          "onboard.step1.title", "onboard.step1.desc"),
        ("mic.circle.fill","onboard.step2.title", "onboard.step2.desc"),
        ("speaker.wave.2", "onboard.step3.title", "onboard.step3.desc"),
    ]

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // 图标
                Image(systemName: steps[step].icon)
                    .font(.system(size: 72))
                    .foregroundColor(.accentElderly)
                    .padding(.bottom, 24)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                // 标题
                Text(lang.tr(steps[step].titleKey))
                    .font(.titleElderly)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 12)

                // 描述
                Text(lang.tr(steps[step].descKey))
                    .font(.bodyElderly)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 40)

                Spacer()

                // 页码指示器
                HStack(spacing: 10) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.accentElderly : Color.divider)
                            .frame(width: i == step ? 12 : 8,
                                   height: i == step ? 12 : 8)
                    }
                }
                .padding(.bottom, 32)

                // 按钮
                VStack(spacing: 14) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if step < steps.count - 1 {
                                step += 1
                            } else {
                                isPresented = false
                            }
                        }
                    } label: {
                        Text(lang.tr(step < steps.count - 1 ? "onboard.next" : "onboard.start"))
                    }
                    .buttonStyle(ElderlyButtonStyle())

                    if step < steps.count - 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isPresented = false
                            }
                        } label: {
                            Text(lang.tr("onboard.skip"))
                                .font(.bodyElderly)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }
}
