import SwiftUI

// MARK: - TypingIndicator
/// "正在输入..."指示器组件。
/// 订阅 Room.subscribeToTypingNotifications() + Room.typingNotice()，
/// 展示对方 typing 状态。

struct TypingIndicator: View {
    let typingUserIds: [String]
    let maxDisplayNames: Int

    init(typingUserIds: [String], maxDisplayNames: Int = 2) {
        self.typingUserIds = typingUserIds
        self.maxDisplayNames = maxDisplayNames
    }

    var body: some View {
        if !typingUserIds.isEmpty {
            HStack(spacing: 4) {
                TypingDotsView()
                    .frame(width: 28, height: 14)

                Text(displayText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var displayText: String {
        let names = typingUserIds.map { extractDisplayName($0) }
        switch names.count {
        case 1:
            return names[0]
        case 2:
            return "\(names[0])、\(names[1])"
        default:
            return "\(names[0])、\(names[1]) 等 \(names.count) 人"
        }
    }

    private func extractDisplayName(_ userId: String) -> String {
        // 从 userId 提取用户名部分（@username:domain → username）
        if let atRange = userId.range(of: "@"),
           let colonRange = userId.range(of: ":") {
            let name = userId[atRange.upperBound..<colonRange.lowerBound]
            return String(name)
        }
        return userId
    }
}

// MARK: - TypingDotsView

struct TypingDotsView: View {
    @State private var animationProgress: Double = 0

    private let dotCount = 3
    private let dotSize: CGFloat = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(dotScale(for: index))
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animationProgress
                    )
            }
        }
        .onAppear {
            animationProgress = 1
        }
    }

    private func dotScale(for index: Int) -> CGFloat {
        let phase = animationProgress - Double(index) * 0.2
        let normalized = phase.truncatingRemainder(dividingBy: 1.0)
        return normalized > 0.5 ? 1.0 : 0.4
    }
}

// MARK: - TypingIndicatorViewModel

/// 用于管理 typing 通知的 ViewModel
/// 订阅 Room.subscribeToTypingNotifications()，更新 typingUserIds。
/// TypingNotificationsListener FFI adapter
private final class TypingNotificationListener: TypingNotificationsListener {
    private let onUpdate: ([String]) -> Void
    init(onUpdate: @escaping ([String]) -> Void) { self.onUpdate = onUpdate }
    func call(typingUserIds: [String]) { onUpdate(typingUserIds) }
}

@MainActor
final class TypingIndicatorViewModel: ObservableObject {
    @Published var typingUserIds: [String] = []

    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    func startObserving(roomId: String) async {
        do {
            guard let client = ffiClient else { return }
            let room = try await client.getRoom(roomId: roomId)
            let listener = TypingNotificationListener { [weak self] userIds in
                Task { @MainActor in
                    self?.typingUserIds = userIds
                }
            }
            _ = room.subscribeToTypingNotifications(listener: listener)
        } catch {
            // Silently fail for typing indicator
        }
    }

}