import SwiftUI

// MARK: - 双人对话模式
/// 两人面对面，各说各的方言，App 实时互译。
/// 上半屏：A 说话区（倒置显示，方便对面的人看）
/// 下半屏：B 说话区（正常方向）
struct DualDialectView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = DualDialectViewModel()
    @FocusState private var focusedSide: DualDialectViewModel.Side?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // ── A 区（上，倒置——方便对面的人读） ──
                SpeakerPanel(
                    side: .a,
                    vm: vm,
                    focusedSide: $focusedSide,
                    height: geo.size.height / 2 - 1
                )
                .rotationEffect(.degrees(180))

                Divider()
                    .frame(height: 2)
                    .background(Color.backgroundCard)

                // ── B 区（下，正常方向） ──
                SpeakerPanel(
                    side: .b,
                    vm: vm,
                    focusedSide: $focusedSide,
                    height: geo.size.height / 2 - 1
                )
            }
        }
        .padding(.bottom, 80)
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("双人对话")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissToolbar(isFocused: focusedSide != nil)
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: .voiceAssistantWillOpen)) { _ in vm.stopWork() }
        .onDisappear { vm.stopWork() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { vm.stopWork() } }
    }
}

// MARK: - 单侧面板
private struct SpeakerPanel: View {
    let side: DualDialectViewModel.Side
    @ObservedObject var vm: DualDialectViewModel
    var focusedSide: FocusState<DualDialectViewModel.Side?>.Binding
    let height: CGFloat

    private var state: DualDialectViewModel.SideState {
        side == .a ? vm.sideA : vm.sideB
    }

    var body: some View {
        VStack(spacing: 12) {
            // 方言选择
            dialectPicker

            // 输入/识别结果区
            inputArea

            Spacer(minLength: 0)

            // 翻译结果
            if !state.translation.isEmpty {
                translationResult
            }
            if let errorMessage = state.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.captionElderly)
                    .foregroundColor(.statusError)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(errorMessage)
            }

            // 操作按钮行
            buttonRow
        }
        .padding(16)
        .frame(height: height)
    }

    // MARK: 方言选择器
    private var dialectPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill")
                .foregroundColor(.accentElderly)
                .font(.title3)
            Menu {
                ForEach(Dialects.names, id: \.self) { name in
                    Button(name) { vm.setDialect(name, for: side) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(state.dialect)
                        .font(.title3Elderly)
                        .foregroundColor(.accentElderly)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.accentElderly)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.backgroundCard)
                .cornerRadius(20)
            }
            .accessibilityLabel("选择\(side == .a ? "上方" : "下方")说话人的方言，当前：\(state.dialect)")
            Spacer()
        }
    }

    // MARK: 输入区
    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(state.isListening ? Color.accentElderly : Color.divider, lineWidth: 2)
                )

            if state.inputText.isEmpty && !state.isListening {
                Text("说话或打字…")
                    .font(.bodyElderly)
                    .foregroundColor(.textTertiary)
                    .padding(12)
                    .allowsHitTesting(false)
            }

            TextEditor(text: Binding(
                get: { state.inputText },
                set: { vm.setInput($0, for: side) }
            ))
            .focused(focusedSide, equals: side)
            .font(.bodyElderly)
            .foregroundColor(.textPrimary)
            .scrollContentBackground(.hidden)
            .padding(8)

            if state.isListening {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                    Text("正在聆听…")
                }
                .font(.captionElderly)
                .foregroundColor(.backgroundPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentElderly)
                .cornerRadius(10)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(minHeight: 80, maxHeight: 110)
    }

    // MARK: 翻译结果
    private var translationResult: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundColor(.accentElderly)
                .font(.title3)
            Text(state.translation)
                .font(.title3Elderly)
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                vm.speakTranslation(for: side)
            } label: {
                Image(systemName: vm.isSpeaking(side) ? "stop.circle.fill" : "speaker.wave.2.fill")
                    .font(.title2)
                    .foregroundColor(.accentElderly)
            }
            .accessibilityLabel(vm.isSpeaking(side) ? "停止朗读" : "朗读翻译结果")
        }
        .padding(12)
        .background(Color.backgroundCard)
        .cornerRadius(12)
    }

    // MARK: 按钮行
    private var buttonRow: some View {
        HStack(spacing: 12) {
            // 麦克风按钮
            Button {
                vm.toggleListening(for: side)
            } label: {
                Label(
                    state.isFinishing ? "识别尾句" : (state.isListening ? "停止" : "说话"),
                    systemImage: state.isFinishing ? "hourglass" : (state.isListening ? "stop.circle.fill" : "mic.circle.fill")
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ElderlyButtonStyle(background: side == .a
                ? Color(red: 50 / 255, green: 110 / 255, blue: 165 / 255)
                : .accentElderly))
            .disabled(state.isFinishing)
            .accessibilityLabel(state.isListening ? "停止录音" : "用\(state.dialect)说话")

            // 翻译按钮（有文字时显示）
            if !state.inputText.isEmpty && !state.isTranslating && !state.isFinishing && !state.isListening {
                Button {
                    vm.translate(for: side)
                } label: {
                    Label("翻译", systemImage: "arrow.right")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ElderlyButtonStyle(background: .accentSecondary))
                .accessibilityLabel("翻译这段\(state.dialect)")
            }

            if state.isTranslating {
                HStack {
                    ProgressView().tint(.backgroundPrimary)
                    Text("翻译中")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentElderly)
                .cornerRadius(ElderlyMetrics.cornerRadius)
            }
        }
    }
}
