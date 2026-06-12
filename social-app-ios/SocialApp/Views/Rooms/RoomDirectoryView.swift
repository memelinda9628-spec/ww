import SwiftUI

// MARK: - RoomDirectoryView
/// 房间目录浏览界面，对应 RoomDirectoryService。

struct RoomDirectoryView: View {
    @StateObject private var viewModel = RoomDirectoryViewModel()
    @State private var searchTerm: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 过滤条件
                filterOptions

                // 结果列表
                if viewModel.isLoading {
                    ProgressView("搜索中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.rooms.isEmpty {
                    emptyState
                } else {
                    roomList
                }
            }
            .navigationTitle("房间目录")
            .searchable(text: $searchTerm, prompt: "搜索房间...")
            .onSubmit(of: .search) {
                viewModel.searchTerm = searchTerm
                Task { await viewModel.performSearch() }
            }
        }
    }

    // MARK: - 过滤选项

    private var filterOptions: some View {
        HStack(spacing: 12) {
            // 服务器选择
            Picker("服务器", selection: $viewModel.selectedHomeserver) {
                ForEach(viewModel.availableHomeservers, id: \.0) { (key, label) in
                    Text(label).tag(key as String?)
                }
            }
            .pickerStyle(.menu)

            Spacer()

            // 仅公开
            Toggle(isOn: $viewModel.onlyPublic) {
                Text("仅公开")
                    .font(.subheadline)
            }
            .toggleStyle(.button)
            .onChange(of: viewModel.onlyPublic) { _ in
                performSearchIfNeeded()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: - 房间列表

    private var roomList: some View {
        List {
            ForEach(viewModel.rooms) { room in
                roomRow(room)
                    .onAppear {
                        Task { await viewModel.onAppearLastItem(room) }
                    }
            }

            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView("加载更多...")
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            viewModel.searchTerm = searchTerm
            Task { await viewModel.performSearch() }
        }
    }

    private func roomRow(_ room: RoomDescription) -> some View {
        HStack(spacing: 12) {
            // 头像
            AvatarView(url: nil, size: 44)
                .overlay(
                    Circle()
                        .stroke(viewModel.isJoined(room) ? Color.green : Color.clear, lineWidth: 2)
                )

            // 房间信息
            VStack(alignment: .leading, spacing: 4) {
                Text(room.displayName ?? room.roomId)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(room.topic ?? "无简介")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let count = room.memberCount {
                        Text("\(count) 人")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray6))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: room.isWorldReadable ? "globe" : "lock")
                        .font(.caption2)
                    Text(room.joinRule?.localizedDescription ?? "未知")
                        .font(.caption2)
                }
                .foregroundColor(room.isWorldReadable ? .green : .secondary)
            }

            Spacer()

            // 加入按钮
            if !viewModel.isJoined(room) {
                Button {
                    Task { await viewModel.joinRoom(room) }
                } label: {
                    if viewModel.isJoining(room) {
                        ProgressView()
                            .frame(width: 20, height: 20)
                    } else {
                        Text(room.joinRule == .public_ ? "加入" : "敲门")
                            .font(.subheadline.bold())
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isJoining(room))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe.desk")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text(searchTerm.isEmpty ? "输入关键词搜索公开房间" : "未找到匹配的房间")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if !searchTerm.isEmpty {
                Button("清除搜索") {
                    searchTerm = ""
                    viewModel.reset()
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func performSearchIfNeeded() {
        if !searchTerm.isEmpty {
            viewModel.searchTerm = searchTerm
            Task { await viewModel.performSearch() }
        }
    }
}