import SwiftUI

struct PhrasesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var speech = SpeechService.shared
    @State private var searchText: String = ""
    @State private var selectedCategory: String = ""
    @State private var showAddSheet = false
    @FocusState private var searchFocused: Bool

    private var allCategoryLabel: String { lang.tr("phrases.all") }

    /// 分类名本地化
    private func localizedCategory(_ cat: String) -> String {
        lang.tr("cat.\(cat)")
    }

    private var categories: [String] {
        [allCategoryLabel] + Array(Set(appState.phrases.map(\.category))).sorted()
    }

    private var filtered: [Phrase] {
        appState.phrases.filter { phrase in
            let matchCat = selectedCategory == allCategoryLabel || phrase.category == selectedCategory
            let matchSearch = searchText.isEmpty
                || phrase.text.contains(searchText)
                || phrase.translation.contains(searchText)
            return matchCat && matchSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textSecondary)
                TextField(lang.tr("phrases.search"), text: $searchText)
                    .focused($searchFocused)
                    .submitLabel(.done)
                    .font(.bodyElderly)
            }
            .padding(14)
            .elderlyCard()
            .padding([.horizontal, .top], ElderlyMetrics.cardPadding)

            // 分类选择
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(categories, id: \.self) { cat in
                        Button(cat == allCategoryLabel ? cat : localizedCategory(cat)) { selectedCategory = cat }
                            .font(.buttonElderly)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(minHeight: ElderlyMetrics.minTapTarget)
                            .background(selectedCategory == cat
                                        ? Color.accentElderly : Color.backgroundCard)
                            .foregroundColor(selectedCategory == cat ? .backgroundPrimary : .textPrimary)
                            .cornerRadius(22)
                    }
                }
                .padding(.horizontal, ElderlyMetrics.cardPadding)
                .padding(.vertical, 12)
            }

            // 列表
            List {
                ForEach(filtered) { phrase in
                    PhraseRow(phrase: phrase, speech: speech)
                        .listRowBackground(Color.backgroundCard)
                        .listRowSeparatorTint(Color.divider)
                }
                .onDelete { indices in
                    let toDelete = indices.compactMap { i -> Int? in
                        let phrase = filtered[i]
                        return appState.phrases.firstIndex(where: { $0.id == phrase.id })
                    }
                    appState.phrases.remove(atOffsets: IndexSet(toDelete))
                    appState.savePhrases()
                }
            }
            .listStyle(.plain)
        .contentMargins(.bottom, 84, for: .scrollContent)
            .background(Color.backgroundPrimary)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(lang.tr("phrases.title"))
        .navigationBarTitleDisplayMode(.large)
        .keyboardDismissToolbar(isFocused: searchFocused)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPhraseSheet { newPhrase in
                appState.phrases.insert(newPhrase, at: 0)
                let saved = appState.savePhrases()
                if !saved { appState.persistenceError = nil }
                return saved
            }
        }
        .onAppear {
            if selectedCategory.isEmpty { selectedCategory = allCategoryLabel }
        }
        .onDisappear { speech.stop() }
    }
}

// MARK: - 添加常用语弹窗

private struct AddPhraseSheet: View {
    private enum InputField: Hashable { case text, translation }
    @FocusState private var focusedField: InputField?
    let onAdd: (Phrase) -> Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lang: LanguageManager
    @State private var text = ""
    @State private var translation = ""
    @State private var category = "日常"
    @State private var dialect = "粤语"
    @State private var showSaveError = false

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTranslation: String { translation.trimmingCharacters(in: .whitespacesAndNewlines) }

    private let presetCategories = ["问候", "日常", "感谢", "告别", "就医", "购物", "出行", "反诈", "其他"]

    var body: some View {
        NavigationStack {
            Form {
                Section(lang.tr("phrases.dialectText")) {
                    TextField(lang.tr("phrases.dialectHint"), text: $text)
                        .focused($focusedField, equals: .text)
                        .submitLabel(.done)
                        .font(.bodyElderly)
                }
                Section(lang.tr("phrases.meaning")) {
                    TextField(lang.tr("phrases.meaningHint"), text: $translation)
                        .focused($focusedField, equals: .translation)
                        .submitLabel(.done)
                        .font(.bodyElderly)
                }
                Section(lang.tr("phrases.dialect")) {
                    Picker(lang.tr("phrases.dialect"), selection: $dialect) {
                        ForEach(Dialects.names, id: \.self) { name in
                            Text(lang.dialectDisplayName(name)).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section(lang.tr("phrases.category")) {
                    Picker(lang.tr("phrases.category"), selection: $category) {
                        ForEach(presetCategories, id: \.self) { Text(lang.tr("cat.\($0)")) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(lang.tr("phrases.addTitle"))
            .keyboardDismissToolbar(isFocused: focusedField != nil)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.tr("phrases.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.tr("phrases.add")) {
                        guard !trimmedText.isEmpty, !trimmedTranslation.isEmpty else { return }
                        guard onAdd(Phrase(category: category,
                                           text: trimmedText,
                                           translation: trimmedTranslation,
                                           dialect: dialect)) else {
                            showSaveError = true
                            return
                        }
                        dismiss()
                    }
                    .disabled(trimmedText.isEmpty || trimmedTranslation.isEmpty)
                }
            }
            .alert(lang.tr("common.alert"), isPresented: $showSaveError) {
                Button(lang.tr("translate.ok"), role: .cancel) {}
            } message: {
                Text(lang.tr("phrases.saveFailed"))
            }
        }
    }
}

private struct PhraseRow: View {
    let phrase: Phrase
    @ObservedObject var speech: SpeechService
    @EnvironmentObject private var lang: LanguageManager

    /// 方言统一放在原句旁，移除旧释义中相同的末尾标注。
    private var translationDisplay: String {
        let text = phrase.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["（\(phrase.dialect)）", "(\(phrase.dialect))"] {
            if text.hasSuffix(suffix) {
                return String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    /// 分类图标映射
    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "问候": return "👋"
        case "日常": return "💬"
        case "感谢": return "🙏"
        case "告别": return "👋"
        case "就医": return "🏥"
        case "购物": return "🛒"
        case "出行": return "🚗"
        case "反诈": return "⚠️"
        case "其他": return "📌"
        default: return "📝"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(lang.tr("cat.\(phrase.category)"))
                    .font(.captionElderly)
                    .foregroundColor(.backgroundPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.accentSecondary)
                    .cornerRadius(8)
                Spacer()
                Button {
                    speech.speak(phrase.text, dialect: phrase.dialect)
                } label: {
                    Image(systemName: speech.isSpeaking(phrase.text)
                          ? "stop.circle.fill" : "speaker.wave.2.fill")
                        .foregroundColor(.accentSecondary)
                }
                .frame(width: 44, height: 44)
                .buttonStyle(.borderless)
                .accessibilityLabel(speech.isSpeaking(phrase.text)
                    ? lang.tr("phrases.stopSpeak") : "\(lang.tr("phrases.speakHint")) \(phrase.text)")
                .accessibilityHint(lang.tr("phrases.speakHint"))
                Button {
                    UIPasteboard.general.string = phrase.text
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.accentElderly)
                }
                .frame(width: 44, height: 44)
                .buttonStyle(.borderless)
                .accessibilityLabel("\(lang.tr("phrases.copy")) \(phrase.text)")
                .accessibilityHint(lang.tr("phrases.copyHint"))
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(phrase.text)
                    .font(.title2Elderly)
                    .foregroundColor(.textPrimary)
                Spacer(minLength: 0)
                Text(lang.dialectDisplayName(phrase.dialect))
                    .font(.captionElderly)
                    .foregroundStyle(Color.accentElderly)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentElderly.opacity(0.08), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(translationDisplay)
                .font(.bodyElderly)
                .foregroundColor(.textSecondary)
        }
        .padding(.vertical, 8)
    }
}
