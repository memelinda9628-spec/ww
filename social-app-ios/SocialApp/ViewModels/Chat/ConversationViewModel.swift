import Foundation
import Combine

// MARK: - ConversationViewModel
/// 聊天对话页 ViewModel，管理消息列表、发送/编辑/撤回/表情回应。

@MainActor
final class ConversationViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var roomName: String = ""
    @Published var isLoading: Bool = false
    @Published var isSending: Bool = false
    @Published var errorMessage: String?

    private let roomId: String
    private let messageService: MessageService

    init(roomId: String, messageService: MessageService = .shared) {
        self.roomId = roomId
        self.messageService = messageService
    }

    func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        do {
            messages = try await messageService.fetchMessages(roomId: roomId)
        } catch {
            errorMessage = "加载消息失败: \(error.localizedDescription)"
        }
    }

    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        _ = messageService.sendMessage(roomId: roomId, body: text)
        isSending = false
        Task { await loadMessages() }
    }

    func sendReply(to message: ChatMessage, text: String) {
        isSending = true
        _ = messageService.sendReply(roomId, replyTo: message, body: text)
        isSending = false
        Task { await loadMessages() }
    }

    func editMessage(_ messageId: String, newText: String) {
        messageService.editMessage(roomId: roomId, messageId: messageId, newBody: newText)
        Task { await loadMessages() }
    }

    func deleteMessage(_ messageId: String) {
        messageService.redactMessage(roomId: roomId, messageId: messageId)
        Task { await loadMessages() }
    }

    func addReaction(to messageId: String, emoji: String) {
        messageService.sendReaction(roomId: roomId, messageId: messageId, emoji: emoji)
        Task { await loadMessages() }
    }

    func removeReaction(from messageId: String, emoji: String) {
        messageService.removeReaction(roomId: roomId, messageId: messageId, emoji: emoji)
        Task { await loadMessages() }
    }

    /// 发送附件，匹配 MessageService.sendAttachment(roomId:filename:mimeType:data:caption:)
    func sendAttachment(fileName: String, mimeType: String, data: Data, caption: String? = nil) async {
        isSending = true
        defer { isSending = false }
        do {
            try await messageService.sendAttachment(roomId: roomId, filename: fileName,
                                                     mimeType: mimeType, data: data, caption: caption)
            await loadMessages()
        } catch {
            errorMessage = "发送附件失败: \(error.localizedDescription)"
        }
    }

    /// 转发消息到目标房间
    func forwardMessage(_ message: ChatMessage, toRoomId: String) async {
        do {
            try await messageService.forwardMessage(fromRoomId: roomId, toRoomId: toRoomId,
                                                     originalEventId: message.id)
            await loadMessages()
        } catch {
            errorMessage = "转发失败: \(error.localizedDescription)"
        }
    }
}