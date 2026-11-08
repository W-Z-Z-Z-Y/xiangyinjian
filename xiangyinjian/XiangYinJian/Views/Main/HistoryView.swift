import SwiftUI
import UIKit

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var lang: LanguageManager
    @State private var showClearConfirm = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var showFavoritesOnly = false

    private var filtered: [HistoryRecord] {
        appState.history.filter { record in
            let matchFav = !showFavoritesOnly || record.isFavorited
            let matchSearch = searchText.isEmpty
                || record.sourceText.contains(searchText)
                || record.translatedText.contains(searchText)
                || record.dialect.contains(searchText)
            return matchFav && matchSearch
        }
    }

    var body: some View {
        Group {
            if appState.history.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    Picker(lang.tr("history.title"), selection: $showFavoritesOnly) {
                        Text(lang.tr("history.all")).tag(false)
                        Text(lang.tr("history.favorites")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding([.horizontal, .top], ElderlyMetrics.cardPadding)

                    if filtered.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: showFavoritesOnly ? "star" : "magnifyingglass")
                                .font(.system(size: 64))
                                .foregroundColor(.textSecondary)
                            Text(showFavoritesOnly ? lang.tr("history.noFavorites") : lang.tr("history.noSearchResult"))
                                .font(.title2Elderly)
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        historyList
                    }
                }
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(lang.tr("history.title"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: lang.tr("history.search"))
        .searchFocused($searchFocused)
        .keyboardDismissToolbar(isFocused: searchFocused)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { appState.reloadHistory() }
        .toolbar {
            if !appState.history.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(lang.tr("history.clear")) { showClearConfirm = true }
                        .foregroundColor(.statusError)
                        .font(.bodyElderly)
                }
            }
        }
        .confirmationDialog(lang.tr("history.clearConfirm"), isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(lang.tr("history.clear"), role: .destructive) { appState.clearHistory() }
            Button(lang.tr("history.cancel"), role: .cancel) {}
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 64))
                .foregroundColor(.textSecondary)
            Text(lang.tr("history.empty"))
                .font(.title2Elderly)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyList: some View {
        List {
            ForEach(filtered) { record in
                HistoryRow(record: record) {
                    appState.toggleFavorite(record)
                }
                .listRowBackground(Color.backgroundCard)
                .listRowSeparatorTint(Color.divider)
            }
            .onDelete { indices in
                let ids = Set(indices.compactMap { index in
                    filtered.indices.contains(index) ? filtered[index].id : nil
                })
                appState.deleteHistory(ids: ids)
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 84, for: .scrollContent)
    }
}

private struct HistoryRow: View {
    let record: HistoryRecord
    let onToggleFavorite: () -> Void
    @EnvironmentObject private var lang: LanguageManager
    @State private var isExpanded = false
    @State private var copied = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    private var dateString: String {
        Self.dateFormatter.string(from: record.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(lang.dialectDisplayName(record.dialect), systemImage: "globe")
                    .font(.captionElderly)
                    .foregroundColor(.accentSecondary)
                Spacer()
                Text(dateString)
                    .font(.captionElderly)
                    .foregroundColor(.textSecondary)
                Button(action: onToggleFavorite) {
                    Image(systemName: record.isFavorited ? "star.fill" : "star")
                        .foregroundColor(record.isFavorited ? .accentElderly : .textSecondary)
                        .font(.title3)
                }
                .frame(width: 44, height: 44)
                .buttonStyle(.borderless)
                .accessibilityLabel(record.isFavorited ? lang.tr("history.removeFav") : lang.tr("history.addFav"))
                .accessibilityHint(lang.tr("history.favHint"))
            }
            Text(record.sourceText)
                .font(.bodyElderly)
                .foregroundColor(.textPrimary)
                .textSelection(.enabled)
            Text(record.translatedText)
                .font(.bodyElderly)
                .foregroundColor(.textSecondary)
                .lineLimit(isExpanded ? nil : 2)
                .textSelection(.enabled)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { historyActions }
                VStack(alignment: .leading, spacing: 8) { historyActions }
            }
            .font(.captionElderly)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var historyActions: some View {
        Button {
            isExpanded.toggle()
            Haptic.tap()
        } label: {
            Label(lang.tr(isExpanded ? "history.collapse" : "history.expand"),
                  systemImage: isExpanded ? "chevron.up" : "chevron.down")
                .frame(minHeight: ElderlyMetrics.minTapTarget)
        }
        .buttonStyle(.borderless)
        Button {
            UIPasteboard.general.string = record.translatedText
            copied = true
            Haptic.success()
        } label: {
            Label(lang.tr(copied ? "history.copied" : "history.copy"),
                  systemImage: copied ? "checkmark" : "doc.on.doc")
                .frame(minHeight: ElderlyMetrics.minTapTarget)
        }
        .buttonStyle(.borderless)
    }
}
