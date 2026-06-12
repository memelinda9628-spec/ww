import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - ChatDetailView
/// 聊天详情视图，显示与某个联系人的完整聊天记录

struct ChatDetailView: View {
    let roomId: String
    let roomName: String

    @StateObject private var viewModel: ConversationViewModel
    @State private var messageText = ""
    @State private var replyingTo: ChatMessage?
    @State private var editingMessage: ChatMessage?
    @State private var editText = ""
    @State private var showEditAlert = false
    @FocusState private var isInputFocused: Bool

    // 附件选择器
    @State private var showAttachmentOptions = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    // 转发
    @State private var showForwardSheet = false
    @State private var selectedForwardMessage: ChatMessage?
    @State private var availableRooms: [ChatRoom] = []

    init(roomId: String, roomName: String) {
        self.roomId = roomId
        self.roomName = roomName
        _viewModel = StateObject(wrappedValue: ConversationViewModel(roomId: roomId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message) { action in
                                handleMessageAction(action, message: message)
                            }
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let lastId = viewModel.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            // 回复预览条
            if let reply = replyingTo {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("回复 \(reply.senderName)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        Text(reply.body)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(action: { replyingTo = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }

            // 输入栏
            HStack(alignment: .bottom, spacing: 8) {
                // 附件按钮
                Button(action: { showAttachmentOptions = true }) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundColor(.blue)
                }

                // 输入框
                TextField("输入消息...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }
                    .lineLimit(1...5)

                // 发送按钮
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .navigationTitle(roomName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    RoomSettingsView(roomId: roomId)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task {
            await viewModel.loadMessages()
        }
        .alert("编辑消息", isPresented: $showEditAlert) {
            TextField("消息内容", text: $editText)
            Button("取消", role: .cancel) {
                editingMessage = nil
            }
            Button("保存") {
                performEdit()
            }
        } message: {
            Text("修改已发送的消息内容")
        }
        // 附件选择：弹出类型选项
        .confirmationDialog("选择附件类型", isPresented: $showAttachmentOptions) {
            Button("图片/视频") { showPhotoPicker = true }
            Button("文件") { showFilePicker = true }
            Button("取消", role: .cancel) {}
        }
        // PhotosPicker：iOS 16+ 原生图片选择器
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { newItem in
            guard let item = newItem else { return }
            Task { await handlePhotoSelection(item) }
        }
        // fileImporter：通用文件选择器，覆盖文档/文件
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): Task { await handleFileSelection(url) }
            case .failure: break
            }
        }
        // 转发：房间选择 sheet
        .sheet(isPresented: $showForwardSheet) {
            ForwardRoomPickerView(rooms: availableRooms) { targetRoom in
                showForwardSheet = false
                if let msg = selectedForwardMessage {
                    Task { await viewModel.forwardMessage(msg, toRoomId: targetRoom.id) }
                }
            }
        }
        .onChange(of: showForwardSheet) { showing in
            if showing {
                Task {
                    if let rooms = try? await MessageService.shared.fetchRooms() {
                        availableRooms = rooms
                    }
                }
            }
        }
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let reply = replyingTo {
            viewModel.sendReply(to: reply, text: trimmed)
            replyingTo = nil
        } else {
            viewModel.sendMessage(trimmed)
        }
        messageText = ""
        isInputFocused = false
    }

    private func handleMessageAction(_ action: MessageAction, message: ChatMessage) {
        switch action {
        case .reply:
            replyingTo = message
            isInputFocused = true
        case .edit:
            editingMessage = message
            editText = message.body
            showEditAlert = true
        case .delete:
            viewModel.deleteMessage(message.id)
        case .react(let emoji):
            viewModel.addReaction(to: message.id, emoji: emoji)
        case .forward:
            selectedForwardMessage = message
            showForwardSheet = true
        }
    }

    private func performEdit() {
        guard let message = editingMessage,
              !editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let newBody = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            guard let client = KeychainManager.shared.ffiClient else { return }
            guard let room = try? await client.getRoom(roomId: roomId) else { return }
            let timeline = room.timeline()
            let content = messageEventContentFromMarkdown(md: newBody)
            try? await timeline.edit(
                eventOrTransactionId: .eventId(message.id),
                newContent: .roomMessage(content: content)
            )
            await viewModel.loadMessages()
        }
        editingMessage = nil
    }

    // MARK: - 附件选择处理

    /// 处理 PhotosPicker 选中的图片/视频
    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let filename = item.itemIdentifier ?? "photo.jpg"
        let mimeType = "image/jpeg"
        await viewModel.sendAttachment(fileName: filename, mimeType: mimeType, data: data)
    }

    /// 处理 fileImporter 选中的文件
    private func handleFileSelection(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let filename = url.lastPathComponent
        let mimeType = mimeTypeForPath(filename)
        await viewModel.sendAttachment(fileName: filename, mimeType: mimeType, data: data)
    }

    /// 根据文件扩展名推断 MIME 类型
    private func mimeTypeForPath(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "zip": return "application/zip"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - MessageAction

enum MessageAction {
    case reply
    case edit
    case delete
    case react(emoji: String)
    case forward
}

// MARK: - MessageBubbleView

struct MessageBubbleView: View {
    let message: ChatMessage
    let onAction: (MessageAction) -> Void

    @State private var showActions = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isMine { Spacer(minLength: 60) }

            if !message.isMine {
                AvatarView(name: message.senderName, url: message.senderAvatar, size: 32)
            }

            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
                if !message.isMine {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 引用的消息
                if let replyId = message.replyTo {
                    Text("回复了一条消息")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.bottom, 2)
                }

                // 消息正文
                Text(message.body)
                    .font(.body)
                    .foregroundColor(message.isMine ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isMine ? Color.blue : Color(.systemGray5))
                    .cornerRadius(16)

                // 反应表情
                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.reactions.sorted(by: { $0.value > $1.value }), id: \.key) { emoji, count in
                            HStack(spacing: 2) {
                                Text(emoji)
                                Text("\(count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                }
            }
            .contextMenu {
                Button { onAction(.reply) } label: {
                    Label("回复", systemImage: "arrowshape.turn.up.left")
                }
                Button { onAction(.react(emoji: "👍")) } label: {
                    Label("👍 赞", systemImage: "hand.thumbsup")
                }
                Button { onAction(.react(emoji: "❤️")) } label: {
                    Label("❤️ 爱心", systemImage: "heart")
                }
                Button { onAction(.react(emoji: "😄")) } label: {
                    Label("😄 大笑", systemImage: "face.smiling")
                }
                Button { onAction(.react(emoji: "🔥")) } label: {
                    Label("🔥 火", systemImage: "flame")
                }
                if message.isMine {
                    Divider()
                    Button { onAction(.edit) } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) { onAction(.delete) } label: {
                        Label("撤回", systemImage: "trash")
                    }
                }
                Divider()
                Button { onAction(.forward) } label: {
                    Label("转发", systemImage: "arrowshape.turn.up.forward")
                }
            }

            if !message.isMine { Spacer(minLength: 60) }
        }
    }
}

// MARK: - ForwardRoomPickerView
/// 转发消息时选择目标房间的列表视图

struct ForwardRoomPickerView: View {
    let rooms: [ChatRoom]
    let onSelect: (ChatRoom) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(rooms) { room in
                Button {
                    onSelect(room)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(name: room.displayName, url: room.avatarUrl, size: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room.displayName)
                                .font(.body)
                                .foregroundColor(.primary)
                            if let last = room.lastMessage {
                                Text(last)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("选择转发对象")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}