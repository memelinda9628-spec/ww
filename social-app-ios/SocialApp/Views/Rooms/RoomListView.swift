import SwiftUI

// MARK: - RoomListView
/// 房间列表管理界面，对应 RoomListService。
/// 支持过滤、搜索、多选批量操作。

struct RoomListView: View {
    @StateObject private var viewModel = RoomListViewModel()
    @State private var showFilterSheet: Bool = false
    @State private var selectedSort: SortOption = .recent

    enum SortOption: String, CaseIterable {
        case recent = "最近"
        case unread = "未读优先"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索栏 + 过滤标签
                filterBar

                // 列表
                if viewModel.rooms.isEmpty && !viewModel.isSearching {
                    emptyState
                } else {
                    roomList
                }
            }
            .navigationTitle("房间")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if !viewModel.selectedRoomIds.isEmpty {
                            Button("标记已读") {
                                viewModel.bulkMarkAsRead()
                            }
                        }
                        Menu {
                            Button { selectedSort = .recent } label: {
                                Label("按最近排序", systemImage: selectedSort == .recent ? "checkmark" : "")
                            }
                            Button { selectedSort = .unread } label: {
                                Label("未读优先", systemImage: selectedSort == .unread ? "checkmark" : "")
                            }
                            Divider()
                            Button { viewModel.toggleBulkEdit() } label: {
                                Label(viewModel.bulkEditMode ? "取消多选" : "多选模式", systemImage: viewModel.bulkEditMode ? "checkmark.circle" : "checklist")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheet(
                    isPresented: $showFilterSheet,
                    filter: SearchFilter(keyword: "", authorId: nil, timeRange: nil, minLikes: 0, minComments: 0, hasImages: false),
                    onApply: { _ in }
                )
            }
            .task { await viewModel.loadRooms() }
            .onChange(of: selectedSort) { newSort in
                switch newSort {
                case .recent: viewModel.sortByRecent()
                case .unread: viewModel.sortByUnread()
                }
            }
        }
    }

    // MARK: - 过滤栏

    private var filterBar: some View {
        VStack(spacing: 0) {
            // 搜索
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索房间...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: viewModel.searchQuery) { q in
                        viewModel.search(query: q)
                    }
                if viewModel.isSearching {
                    Button { viewModel.clearSearch() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 过滤标签
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.filterTabs, id: \.self) { filter in
                        filterChip(filter)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .background(.regularMaterial)
    }

    private func filterChip(_ filter: RoomFilterType) -> some View {
        Button {
            viewModel.setFilter(filter)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.filterTabIcon(filter))
                Text(viewModel.filterTabTitle(filter))
                if filter == .unread && viewModel.unreadCount > 0 {
                    Text("\(viewModel.unreadCount)")
                        .font(.caption2)
                        .padding(2)
                        .background(.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(viewModel.activeFilter == filter ? Color.accentColor : Color(.systemGray6))
            .foregroundColor(viewModel.activeFilter == filter ? .white : .primary)
            .cornerRadius(16)
        }
    }

    // MARK: - 房间列表

    private var roomList: some View {
        List {
            ForEach(viewModel.rooms) { room in
                roomRow(room)
                    .swipeActions(edge: .leading) {
                        Button {
                            viewModel.toggleFavourite(room.roomId)
                        } label: {
                            Label("收藏", systemImage: room.isFavourite ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            viewModel.toggleMute(room.roomId)
                        } label: {
                            Label("静音", systemImage: room.isMuted ? "bell" : "bell.slash")
                        }
                        .tint(.orange)

                        Button(role: .destructive) {
                            Task { await viewModel.leaveRoom(room.roomId) }
                        } label: {
                            Label("离开", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    .contextMenu {
                        Button { viewModel.markAsRead(room.roomId) } label: {
                            Label("标为已读", systemImage: "envelope.open")
                        }
                        Button { viewModel.setLowPriority(room.roomId) } label: {
                            Label("低优先级", systemImage: "arrow.down.to.line")
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task { await viewModel.leaveRoom(room.roomId) }
                        } label: {
                            Label("离开房间", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.refresh() }
    }

    private func roomRow(_ room: RoomListItem) -> some View {
        HStack(spacing: 12) {
            // 多选
            if viewModel.bulkEditMode {
                Image(systemName: viewModel.selectedRoomIds.contains(room.roomId) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(viewModel.selectedRoomIds.contains(room.roomId) ? .accentColor : .secondary)
                    .onTapGesture { viewModel.toggleRoomSelection(room.roomId) }
            }

            // 头像
            AvatarView(url: nil, size: 48)
                .overlay(alignment: .bottomTrailing) {
                    if !viewModel.bulkEditMode {
                        Circle()
                            .fill(room.isOnline ? Color.green : Color.gray)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.background, lineWidth: 2))
                    }
                }

            // 房间信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(room.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if room.isFavourite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    if room.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text(room.lastMessagePreview ?? "暂无消息")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 右侧信息
            VStack(alignment: .trailing, spacing: 4) {
                Text(room.formattedLastMessageTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if room.unreadCount > 0 {
                    Text("\(room.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red)
                        .clipShape(Capsule())
                } else if room.isMarkedUnread {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text(viewModel.isSearching ? "没有匹配的房间" : "暂无房间")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}