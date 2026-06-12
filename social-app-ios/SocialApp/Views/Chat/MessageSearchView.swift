import SwiftUI

// MARK: - MessageSearchView
/// 消息搜索界面，对应 MessageSearchService。

struct MessageSearchView: View {
    @StateObject private var viewModel = MessageSearchViewModel()
    @State private var searchText: String = ""
    @State private var showFilterPopover: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 过滤栏
                filterBar

                if viewModel.isSearching {
                    ProgressView("搜索中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchText.isEmpty && viewModel.searchHistory.isEmpty {
                    emptyState
                } else if searchText.isEmpty && !viewModel.searchHistory.isEmpty {
                    searchHistoryView
                } else if let result = viewModel.searchResults, !result.roomResults.isEmpty {
                    searchResultList(result)
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if searchText.isNotEmpty {
                    noResultsView
                } else {
                    emptyState
                }
            }
            .navigationTitle("搜索消息")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索消息内容..."
            )
            .onSubmit(of: .search) { performSearch() }
            .onChange(of: viewModel.searchFilter) { _ in performSearch() }
        }
    }

    // MARK: - 过滤栏

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MessageSearchFilter.allCases) { filter in
                    filterChip(filter)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }

    private func filterChip(_ filter: MessageSearchFilter) -> some View {
        Button {
            viewModel.setFilter(filter)
        } label: {
            Text(filter.localizedDescription)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(viewModel.searchFilter == filter ? Color.accentColor : Color(.systemGray6))
                .foregroundColor(viewModel.searchFilter == filter ? .white : .primary)
                .cornerRadius(16)
        }
    }

    // MARK: - 搜索结果

    private func searchResultList(_ result: MessageSearchResult) -> some View {
        List {
            ForEach(result.roomResults) { roomResult in
                Section {
                    Text(roomResult.roomId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(roomResult.events) { event in
                        searchResultRow(event, roomId: roomResult.roomId)
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private func searchResultRow(_ event: MatchedMessage, roomId: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                AvatarView(url: nil, size: 28)
                Text(event.senderId)
                    .font(.subheadline.bold())
                Spacer()
                Text(event.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(event.body)
                .font(.subheadline)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 搜索历史

    private var searchHistoryView: some View {
        List {
            Section("搜索历史") {
                ForEach(viewModel.searchHistory, id: \.self) { query in
                    Button {
                        searchText = query
                        viewModel.searchFromHistory(query)
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.secondary)
                            Text(query)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            viewModel.removeFromHistory(query)
                        }
                    }
                }
                Button("清除历史", role: .destructive) {
                    viewModel.clearHistory()
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - 空/错误状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("输入关键词搜索消息")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("没有找到\"\(searchText)\"相关消息")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func performSearch() {
        viewModel.searchQuery = searchText
        Task { await viewModel.performGlobalSearch() }
    }
}

// MARK: - String Extension

private extension String {
    var isNotEmpty: Bool { !isEmpty }
}