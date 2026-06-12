import SwiftUI

// MARK: - SpacesView
/// 空间列表页（对应 SpacesViewModel）。
/// 网格/列表展示空间卡片，点击进入空间详情。

struct SpacesView: View {
    @StateObject private var viewModel = SpacesViewModel()
    @State private var selectedSpace: SpaceInfo?
    @State private var showCreateSpace = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("加载空间...")
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("重试") { Task { await viewModel.loadSpaces() } }
                            .buttonStyle(.bordered)
                    }
                } else if viewModel.filteredSpaces.isEmpty {
                    ContentUnavailableView(
                        "暂无空间",
                        systemImage: "square.stack.3d.up",
                        description: Text("创建一个空间，邀请团队成员加入")
                    )
                } else {
                    spacesGrid
                }
            }
            .navigationTitle("空间")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateSpace = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "搜索空间")
            .sheet(isPresented: $showCreateSpace) {
                CreateSpaceSheet(viewModel: viewModel)
            }
            .task { await viewModel.loadSpaces() }
            .refreshable { await viewModel.loadSpaces() }
        }
    }

    // MARK: - Spaces Grid

    private var spacesGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                spacing: 16
            ) {
                ForEach(viewModel.filteredSpaces) { space in
                    SpaceCard(space: space)
                        .onTapGesture {
                            selectedSpace = space
                        }
                }
            }
            .padding(16)
        }
        .sheet(item: $selectedSpace) { space in
            SpaceDetailView(space: space, viewModel: viewModel)
        }
    }
}

// MARK: - SpaceCard

struct SpaceCard: View {
    let space: SpaceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 空间头像占位
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.7), .purple.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(height: 80)
                Text(String(space.name.prefix(2)))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.headline)
                    .lineLimit(1)
                if let topic = space.topic, !topic.isEmpty {
                    Text(topic)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 12) {
                    Label("\(space.memberCount)", systemImage: "person.2")
                    Label("\(space.childRoomCount)", systemImage: "rectangle.3.group")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - SpaceDetailView

struct SpaceDetailView: View {
    let space: SpaceInfo
    @ObservedObject var viewModel: SpacesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showConfirmLeave = false

    var body: some View {
        NavigationStack {
            List {
                Section("空间信息") {
                    LabeledContent("名称", value: space.name)
                    if let topic = space.topic, !topic.isEmpty {
                        LabeledContent("描述", value: topic)
                    }
                    LabeledContent("成员", value: "\(space.memberCount)")
                    LabeledContent("子房间", value: "\(space.childRoomCount)")
                }

                Section("子房间") {
                    if viewModel.childRooms.isEmpty {
                        Text("暂无子房间")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.childRooms) { child in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(child.name).fontWeight(.medium)
                                    if let topic = child.topic {
                                        Text(topic).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(child.memberCount) 人")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showConfirmLeave = true
                    } label: {
                        Label("退出空间", systemImage: "rectangle.portrait.and.arrow.forward")
                    }
                }
            }
            .navigationTitle(space.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .confirmationDialog("退出空间", isPresented: $showConfirmLeave) {
                Button("确认退出", role: .destructive) {
                    Task {
                        try? await viewModel.leaveSpace(spaceId: space.id)
                        dismiss()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后您将无法访问该空间的子房间和消息。")
            }
            .task { await viewModel.loadSpaceRooms(spaceId: space.id) }
        }
    }
}

// MARK: - CreateSpaceSheet

struct CreateSpaceSheet: View {
    @ObservedObject var viewModel: SpacesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var topic: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("空间名称") {
                    TextField("输入空间名称", text: $name)
                }
                Section("空间描述（可选）") {
                    TextField("描述这个空间的目的", text: $topic)
                }
            }
            .navigationTitle("创建空间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("创建") {
                        Task {
                            try? await viewModel.createSpace(name: name, topic: topic)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}