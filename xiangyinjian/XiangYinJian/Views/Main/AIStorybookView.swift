import SwiftUI
import Combine

// MARK: - AI方言绘本主页
struct AIStorybookView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = AIStorybookViewModel()
    @State private var showCreateSheet = false

    var body: some View {
        ZStack {
            if vm.storybooks.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(vm.storybooks) { book in
                            NavigationLink(destination: StorybookDetailView(vm: vm, book: book)) {
                                StorybookCard(book: book)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 84)
                }
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("方言绘本")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateStorybookView(vm: vm)
        }
        .onAppear { vm.loadStorybooks() }
        .onDisappear { vm.cancelImageCaching() }
    }

    private var emptyView: some View {
        EmptyStatePanel(
            icon: "book.circle",
            title: "还没有方言绘本",
            message: "讲一段家乡故事，生成一本可以保存的方言绘本。"
        ) {
            Button {
                showCreateSheet = true
            } label: {
                Label("讲个故事", systemImage: "mic.fill")
                    .font(.title3Elderly)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .buttonStyle(ElderlyButtonStyle())
            .frame(maxWidth: 240)
        }
    }
}

// MARK: - 绘本卡片
struct StorybookCard: View {
    let book: Storybook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StorybookArtwork(book: book, contentMode: .fill)
                .frame(height: 120)
                .clipped()
                .cornerRadius(12)

            Text(book.title)
                .font(.bodyElderly)
                .foregroundColor(.textPrimary)
                .lineLimit(2)

            HStack {
                Text(book.dialect)
                    .font(.captionElderly)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text(book.date, style: .date)
                    .font(.captionElderly)
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(12)
        .background(Color.backgroundCard)
        .cornerRadius(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("方言绘本，\(book.title)，\(book.dialect)")
        .accessibilityHint("点击打开绘本")
    }
}

private struct StorybookArtwork: View {
    let book: Storybook
    let contentMode: ContentMode

    var body: some View {
        Group {
            if let url = AppFileStore.mediaURL(for: book.imageFileName),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let imageUrl = book.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder
                    default:
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                placeholder
            }
        }
        .accessibilityLabel("绘本插图，\(book.title)")
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.backgroundCard)
            .overlay {
                Image(systemName: "book.fill")
                    .font(.largeTitle)
                    .foregroundColor(.accentElderly)
            }
    }
}

// MARK: - 创建绘本页
struct CreateStorybookView: View {
    private enum InputField: Hashable { case topic, story }
    @FocusState private var focusedField: InputField?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject var vm: AIStorybookViewModel
    @StateObject private var dictation = DictationService()
    @State private var storyText = ""
    @State private var topicText = ""
    @State private var isGenerating = false
    @State private var isGeneratingStory = false
    @State private var creationTask: Task<Void, Never>?
    @State private var storyTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // MARK: AI 生成故事区域
                    VStack(alignment: .leading, spacing: 12) {
                        Label("AI 帮我写故事", systemImage: "sparkles")
                            .font(.title3Elderly)
                            .foregroundColor(.accentElderly)

                        Text("输入一个主题（如「过年」「奶奶的菜园」），AI 用\(appState.preferredDialect)自动写一段故事")
                            .font(.captionElderly)
                            .foregroundColor(.textSecondary)

                        HStack(spacing: 12) {
                            TextField("故事主题…", text: $topicText)
                                .focused($focusedField, equals: .topic)
                                .submitLabel(.done)
                                .font(.bodyElderly)
                                .padding(12)
                                .background(Color.backgroundCard)
                                .cornerRadius(10)
                                .disabled(isGeneratingStory || isGenerating)

                            Button {
                                dictation.cancel()
                                isGeneratingStory = true
                                storyTask = Task {
                                    let generated = await vm.generateStoryText(topic: topicText, dialect: appState.preferredDialect)
                                    guard !Task.isCancelled else { return }
                                    if let generated {
                                        storyText = generated
                                    }
                                    isGeneratingStory = false
                                    storyTask = nil
                                }
                            } label: {
                                if isGeneratingStory {
                                    ProgressView().tint(.backgroundPrimary).frame(width: 56, height: 56)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                        .font(.title2)
                                        .frame(width: 56, height: 56)
                                }
                            }
                            .buttonStyle(ElderlyButtonStyle())
                            .frame(width: 56)
                            .disabled(topicText.trimmingCharacters(in: .whitespaces).isEmpty || isGeneratingStory || isGenerating)
                            .accessibilityLabel("AI 生成故事")
                        }

                        if let genError = vm.storyGenError {
                            Text(genError)
                                .font(.captionElderly)
                                .foregroundColor(.statusError)
                        }
                    }
                    .padding(16)
                    .background(Color.backgroundCard)
                    .cornerRadius(16)

                    Rectangle().fill(Color.divider).frame(height: 0.75).accessibilityHidden(true)

                    // MARK: 语音/手动输入区域
                    Text("或者自己讲 / 打字")
                        .font(.title3Elderly)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("点下面的按钮，用\(appState.preferredDialect)直接讲，App 会自动转成文字")
                        .font(.captionElderly)
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ZStack(alignment: .topTrailing) {
                        TextEditor(text: $storyText)
                            .disabled(isGenerating || isGeneratingStory)
                            .focused($focusedField, equals: .story)
                            .font(.bodyElderly)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                            .padding()
                            .background(Color.backgroundCard)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(dictation.isRecording ? Color.accentElderly : Color.divider, lineWidth: 2)
                            )

                        if dictation.isRecording {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                Text("正在聆听…")
                            }
                            .font(.captionElderly)
                            .foregroundColor(.backgroundPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentElderly)
                            .cornerRadius(12)
                            .padding(12)
                        }
                    }

                    Button {
                        dictation.toggle(dialect: appState.preferredDialect, existingText: storyText)
                    } label: {
                        Label(dictation.isRecording ? "停止录音" : "开始讲述",
                              systemImage: dictation.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    }
                    .buttonStyle(ElderlyButtonStyle(background: .accentElderly))
                    .disabled(isGenerating || isGeneratingStory)
                    .accessibilityLabel(dictation.isRecording ? "停止录音" : "开始用方言讲述故事")

                    if let dictationError = dictation.errorMessage {
                        Text(dictationError)
                            .font(.captionElderly)
                            .foregroundColor(.statusError)
                    }

                    // MARK: 生成绘本按钮
                    Button {
                        isGenerating = true
                        creationTask = Task {
                            if dictation.isRecording || dictation.isFinishing {
                                guard let finishedText = await dictation.finish() else {
                                    isGenerating = false
                                    return
                                }
                                storyText = finishedText
                            }
                            let saved = await vm.createStorybook(text: storyText, dialect: appState.preferredDialect)
                            guard !Task.isCancelled else { return }
                            isGenerating = false
                            creationTask = nil
                            if saved {
                                dismiss()
                            }
                        }
                    } label: {
                        if isGenerating {
                            HStack {
                                ProgressView().tint(.backgroundPrimary)
                                Text(vm.creationProgress ?? "正在准备…")
                            }
                        } else {
                            Label("生成绘本", systemImage: "book.fill")
                        }
                    }
                    .buttonStyle(ElderlyButtonStyle())
                    .disabled(storyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating || isGeneratingStory)

                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.captionElderly)
                            .foregroundColor(.statusError)
                    }
                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("创建绘本")
            .keyboardDismissToolbar(isFocused: focusedField != nil)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        cancelWork()
                        dismiss()
                    }
                }
            }
            // 听写结果写回输入框（不加 isRecording 守卫：isFinal 触发时录音已停，需要保留文字）
            .onChange(of: dictation.transcript) { _, newValue in
                storyText = newValue
            }
            // 离开页面务必关闭麦克风，避免占用音频会话
            .onAppear { vm.errorMessage = nil; vm.storyGenError = nil }
            .onDisappear { cancelWork() }
        }
    }

    private func cancelWork() {
        creationTask?.cancel()
        storyTask?.cancel()
        creationTask = nil
        storyTask = nil
        vm.cancelGeneration()
        dictation.cancel()
        isGenerating = false
        isGeneratingStory = false
    }
}

// MARK: - 绘本详情页
struct StorybookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: AIStorybookViewModel
    let book: Storybook

    @State private var showDeleteConfirm = false
    @ObservedObject private var speech = SpeechService.shared

    private var isSpeaking: Bool { speech.isSpeaking(book.story) }
    private var displayedBook: Storybook { vm.storybooks.first { $0.id == book.id } ?? book }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StorybookArtwork(book: displayedBook, contentMode: .fit)
                    .frame(minHeight: 180)
                    .cornerRadius(16)

                if !displayedBook.hasLocalImage || vm.imageErrors[book.id] != nil {
                    if let message = vm.imageErrors[book.id] {
                        Text(message).font(.captionElderly).foregroundColor(.statusError)
                    }
                    Button {
                        Task { await vm.retryImage(for: book) }
                    } label: {
                        Label(LanguageManager.shared.current == .zh ? "重新保存插图" : "Retry saving illustration",
                              systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(ElderlyButtonStyle())
                    .disabled(vm.cachingImages.contains(book.id))
                    if vm.cachingImages.contains(book.id) { ProgressView() }
                }

                Text(book.story)
                    .font(.title3Elderly)
                    .foregroundColor(.textPrimary)
                    .padding()
                    .background(Color.backgroundCard)
                    .cornerRadius(12)

                if !book.keywords.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("关键词")
                            .font(.bodyElderly)
                            .foregroundColor(.textSecondary)
                        FlowLayout(spacing: 8) {
                            ForEach(book.keywords, id: \.self) { keyword in
                                Text(keyword)
                                    .font(.captionElderly)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.backgroundCard)
                                    .foregroundColor(.accentElderly)
                                    .cornerRadius(16)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        toggleSpeak()
                    } label: {
                        Label(isSpeaking ? "停止朗读" : "朗读绘本",
                              systemImage: isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ElderlyButtonStyle())
                    .accessibilityLabel(isSpeaking ? "停止朗读" : "用\(book.dialect)朗读绘本")

                    Button {
                        shareStorybook()
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ElderlyButtonStyle(background: .accentSecondary))
                }
            }
            .padding()
            .padding(.bottom, 84)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.statusError)
                }
                .accessibilityLabel("删除绘本")
            }
        }
        .onDisappear { speech.stop() }
        .onAppear { vm.errorMessage = nil }
        .confirmationDialog("删除这本绘本？删除后无法恢复。",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                speech.stop()
                if vm.deleteStorybook(book) { dismiss() }
            }
            Button("取消", role: .cancel) {}
        }
        .alert(LanguageManager.shared.tr("common.alert"), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button(LanguageManager.shared.tr("translate.ok"), role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private func toggleSpeak() {
        if isSpeaking {
            speech.stop()
        } else {
            speech.speak(book.story, dialect: book.dialect)
        }
    }

    private func shareStorybook() {
        let book = displayedBook
        let text = """
        【乡音间·方言绘本】
        \(book.title)

        \(book.story)

        —— 用\(book.dialect)讲述的家乡故事
        """

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        if let localURL = AppFileStore.mediaURL(for: book.imageFileName),
           let image = UIImage(contentsOfFile: localURL.path) {
            let ac = UIActivityViewController(activityItems: [text, image], applicationActivities: nil)
            if let popover = ac.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootVC.present(ac, animated: true)
        } else if let imageUrlString = book.imageUrl, let imageUrl = URL(string: imageUrlString) {
            Task {
                var items: [Any] = [text]
                if let (data, _) = try? await URLSession.shared.data(from: imageUrl),
                   let image = UIImage(data: data) {
                    items.append(image)
                } else {
                    items.append(imageUrl)
                }
                await MainActor.run {
                    let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
                    if let popover = ac.popoverPresentationController {
                        popover.sourceView = rootVC.view
                        popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    rootVC.present(ac, animated: true)
                }
            }
        } else {
            let ac = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            if let popover = ac.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootVC.present(ac, animated: true)
        }
    }
}

// MARK: - 流式布局
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// MARK: - ViewModel
@MainActor
final class AIStorybookViewModel: ObservableObject {
    @Published var storybooks: [Storybook] = []
    @Published var errorMessage: String?
    @Published var storyGenError: String?
    @Published private(set) var creationProgress: String?
    @Published var imageErrors: [UUID: String] = [:]
    @Published private(set) var cachingImages: Set<UUID> = []

    private let aiService = AIStorybookService()
    private var creationID: UUID?
    private var storyGenerationID: UUID?
    private var pendingBook: Storybook?
    private var imageCachingTask: Task<Void, Never>?

    func loadStorybooks() {
        cancelImageCaching()
        guard let latest = readLatestStorybooks() else {
            errorMessage = AIError.saveFailed.localizedDescription
            return
        }
        storybooks = latest
        imageCachingTask = Task { [weak self] in
            guard let self else { return }
            await self.cacheRemoteImagesIfNeeded()
        }
    }

    func cancelImageCaching() {
        imageCachingTask?.cancel()
        imageCachingTask = nil
    }

    private func readLatestStorybooks() -> [Storybook]? {
        guard AppFileStore.canRead([Storybook].self, fileName: "storybooks.json", legacyKey: "storybooks") else { return nil }
        return AppFileStore.load([Storybook].self, fileName: "storybooks.json", legacyKey: "storybooks") ?? []
    }

    private func removeImageIfUnused(_ path: String?) {
        guard let path, let latest = readLatestStorybooks(),
              !latest.contains(where: { $0.imageFileName == path }) else { return }
        AppFileStore.removeMedia(at: path)
    }

    func createStorybook(text: String, dialect: String) async -> Bool {
        guard creationID == nil, !Task.isCancelled else { return false }
        errorMessage = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请先讲述或输入故事，再生成绘本。"
            return false
        }
        guard text.count <= 3000 else {
            errorMessage = "故事最多支持 3000 字，请缩短后再生成绘本；输入内容已保留。"
            return false
        }
        let requestID = UUID()
        creationID = requestID
        defer {
            if creationID == requestID {
                creationID = nil
                creationProgress = nil
            }
        }

        do {
            if pendingBook?.story != text || pendingBook?.dialect != dialect {
                discardPendingBook()
                creationProgress = "正在整理故事…"
                let meta = try await aiService.generateMeta(for: text)
                try checkCreation(requestID)
                creationProgress = "正在绘制插画…"
                let imageURL = try await aiService.generateImage(for: meta.keywords)
                try checkCreation(requestID)
                pendingBook = Storybook(id: UUID(), title: meta.title, story: text, dialect: dialect,
                                        keywords: meta.keywords, imageUrl: imageURL,
                                        imageFileName: nil, date: Date())
            }
            guard var book = pendingBook else { throw CancellationError() }
            if !book.hasLocalImage {
                creationProgress = "正在保存插画…"
                let path = await cacheImage(urlString: book.imageUrl, bookID: book.id)
                guard creationID == requestID, !Task.isCancelled else {
                    removeImageIfUnused(path)
                    throw CancellationError()
                }
                guard let path else { throw AIError.imageCache }
                book.imageFileName = path
                pendingBook = book
            }
            try checkCreation(requestID)
            creationProgress = "正在保存绘本…"
            guard var updated = readLatestStorybooks() else { throw AIError.saveFailed }
            updated.insert(book, at: 0)
            guard AppFileStore.save(updated, fileName: "storybooks.json", legacyKey: "storybooks") else {
                throw AIError.saveFailed
            }
            storybooks = updated
            pendingBook = nil
            NotificationCenter.default.post(name: .voiceMemoriesUpdated, object: nil)
            return true
        } catch {
            if creationID == requestID, !Task.isCancelled, !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    func generateStoryText(topic: String, dialect: String) async -> String? {
        guard storyGenerationID == nil, !Task.isCancelled else { return nil }
        storyGenError = nil
        let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else {
            storyGenError = "请先输入故事主题。"
            return nil
        }
        guard topic.count <= 200 else {
            storyGenError = "故事主题最多支持 200 字，请缩短后重试；输入内容已保留。"
            return nil
        }
        let requestID = UUID()
        storyGenerationID = requestID
        defer { if storyGenerationID == requestID { storyGenerationID = nil } }
        do {
            let text = try await aiService.generateStory(topic: topic, dialect: dialect)
            guard storyGenerationID == requestID, !Task.isCancelled else { return nil }
            return text
        } catch {
            if storyGenerationID == requestID, !Task.isCancelled {
                storyGenError = error.localizedDescription
            }
            return nil
        }
    }

    func cancelGeneration() {
        creationID = nil
        storyGenerationID = nil
        creationProgress = nil
        discardPendingBook()
    }

    private func checkCreation(_ requestID: UUID) throws {
        try Task.checkCancellation()
        guard creationID == requestID else { throw CancellationError() }
    }

    private func discardPendingBook() {
        removeImageIfUnused(pendingBook?.imageFileName)
        pendingBook = nil
    }

    func deleteStorybook(_ book: Storybook) -> Bool {
        guard let latest = readLatestStorybooks() else {
            errorMessage = AIError.saveFailed.localizedDescription
            return false
        }
        let removed = latest.first { $0.id == book.id }
        let updated = latest.filter { $0.id != book.id }
        guard AppFileStore.save(updated, fileName: "storybooks.json", legacyKey: "storybooks") else {
            errorMessage = AIError.saveFailed.localizedDescription
            return false
        }
        storybooks = updated
        removeImageIfUnused(removed?.imageFileName)
        imageErrors[book.id] = nil
        NotificationCenter.default.post(name: .voiceMemoriesUpdated, object: nil)
        return true
    }

    private func cacheRemoteImagesIfNeeded() async {
        let candidates = storybooks.filter { !$0.hasLocalImage }
        for book in candidates {
            guard !Task.isCancelled else { return }
            await retryImage(for: book)
        }
    }

    func retryImage(for book: Storybook) async {
        guard !Task.isCancelled, !cachingImages.contains(book.id) else { return }
        guard let latest = readLatestStorybooks() else {
            imageErrors[book.id] = AIError.saveFailed.localizedDescription
            return
        }
        guard let currentBook = latest.first(where: { $0.id == book.id }) else {
            storybooks = latest
            return
        }
        if currentBook.hasLocalImage {
            storybooks = latest
            imageErrors[book.id] = nil
            return
        }
        cachingImages.insert(book.id)
        imageErrors[book.id] = nil
        defer { cachingImages.remove(book.id) }
        guard let path = await cacheImage(urlString: currentBook.imageUrl, bookID: book.id) else {
            if !Task.isCancelled { imageErrors[book.id] = AIError.imageCache.localizedDescription }
            return
        }
        guard !Task.isCancelled else {
            removeImageIfUnused(path)
            return
        }
        guard var updated = readLatestStorybooks() else {
            imageErrors[book.id] = AIError.saveFailed.localizedDescription
            return
        }
        guard let index = updated.firstIndex(where: { $0.id == book.id }) else {
            removeImageIfUnused(path)
            storybooks = updated
            return
        }
        updated[index].imageFileName = path
        guard AppFileStore.save(updated, fileName: "storybooks.json", legacyKey: "storybooks") else {
            removeImageIfUnused(path)
            imageErrors[book.id] = AIError.saveFailed.localizedDescription
            return
        }
        storybooks = updated
    }

    private func cacheImage(urlString: String?, bookID: UUID) async -> String? {
        guard !Task.isCancelled, let urlString, let url = URL(string: urlString) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(from: url),
              !Task.isCancelled,
              (response as? HTTPURLResponse)?.statusCode == 200,
              UIImage(data: data) != nil else { return nil }
        return AppFileStore.saveMedia(data,
                                      directory: "Media/Storybooks",
                                      fileName: "\(bookID.uuidString).jpg")
    }
}

// MARK: - Model
struct Storybook: Identifiable, Codable {
    let id: UUID
    let title: String
    let story: String
    let dialect: String
    let keywords: [String]
    let imageUrl: String?
    var imageFileName: String?
    let date: Date

    var hasLocalImage: Bool {
        guard let url = AppFileStore.mediaURL(for: imageFileName) else { return false }
        return UIImage(contentsOfFile: url.path) != nil
    }
}
