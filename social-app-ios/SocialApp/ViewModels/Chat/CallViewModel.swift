import Foundation
import SwiftUI

// MARK: - Rust FFI 通话 API 状态（待 Rust 侧补全后接入）
//
// 当前状态：
//   callService 为 nil，所有通话操作为本地模拟。
//
// 原因：
//   Rust 核心层和 FFI 绑定层均不存在以下类型和 API：
//     - CallService / ElementCall / VoipCall：通话服务与实例
//     - 发起通话 (placeCall / startCall)：创建并发送 m.call 事件
//     - 接听通话 (answerCall)：响应来电
//     - 挂断通话 (hangupCall / endCall)：终止通话
//     - 静音切换 (toggleMute)：麦克风静音/取消静音
//     - 扬声器切换 (toggleSpeaker)：音频输出切换
//     - 原生 WebRTC 引擎：音视频流采集与传输
//
// 现有 FFI 能力（仅被动级）：
//     - Room.hasActiveRoomCall()：检查房间是否有活跃通话
//     - Room.activeRoomCallParticipants()：获取通话参与者列表
//     - Room.declineCall(rtcNotificationEventId:)：拒绝来电
//     - RoomInfo.activeRoomCallConsensusIntent：通话意图共识 (Audio/Video)
//     - VirtualElementCallWidget：在 WebView 中启动 Element Call（独立 Web 应用）
//
// 未来接入步骤：
//     1. Rust 核心层实现 CallService + VoipCall + WebRTC 引擎
//     2. FFI 绑定层 (matrix-sdk-ffi) 导出通话 API
//     3. UniFFI 生成对应 Swift 绑定类型
//     4. 将 callService 从 nil 替换为真实 FFI CallService 实例
//     5. 逐个替换本地模拟方法为真实 FFI 调用
//     6. 删除此注释块

// MARK: - CallState
/// 通话状态枚举

enum CallState: Sendable {
    case idle
    case calling          // 拨号中
    case ringing          // 振铃中
    case connected        // 通话中
    case reconnecting     // 重连中
    case ended            // 已挂断
    case declined        // 已拒绝
    case missed           // 未接
    case busy             // 对方占线

    var localizedDescription: String {
        switch self {
        case .idle: return "空闲"
        case .calling: return "正在呼叫..."
        case .ringing: return "振铃中..."
        case .connected: return "通话中"
        case .reconnecting: return "重新连接..."
        case .ended: return "通话结束"
        case .declined: return "已拒绝"
        case .missed: return "未接来电"
        case .busy: return "对方忙"
        }
    }
}

// MARK: - CallType
/// 通话类型

enum CallType: String, Sendable {
    case voice = "voice"
    case video = "video"

    var localizedDescription: String {
        switch self {
        case .voice: return "语音通话"
        case .video: return "视频通话"
        }
    }

    var iconName: String {
        switch self {
        case .voice: return "phone"
        case .video: return "video"
        }
    }
}

// MARK: - CallParticipant
/// 通话参与者

struct CallParticipant: Identifiable, Sendable {
    let id: String
    let userId: String
    let displayName: String
    let avatarUrl: URL?
    let isVideoEnabled: Bool
    let isAudioEnabled: Bool
    let isScreenSharing: Bool
}

// MARK: - CallRecord
/// 通话记录

struct CallRecord: Identifiable, Sendable {
    let id: String
    let participantId: String
    let participantName: String
    let callType: CallType
    let state: CallState
    let startTime: Date
    let endTime: Date?
    let duration: TimeInterval?
    let isIncoming: Bool

    var formattedDuration: String {
        guard let d = duration else { return "" }
        let mins = Int(d) / 60
        let secs = Int(d) % 60
        if mins > 0 {
            return "\(mins)分\(secs)秒"
        }
        return "\(secs)秒"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(startTime) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(startTime) {
            return "昨天 \(DateFormatter.HHmm.string(from: startTime))"
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        return formatter.string(from: startTime)
    }
}

private extension DateFormatter {
    static let HHmm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - CallViewModel
/// 通话 ViewModel，对应第7章 VoIP 的 CallService。
/// 管理通话状态、发起/接听/挂断、通话记录。

@MainActor
final class CallViewModel: ObservableObject {
    @Published var callState: CallState = .idle
    @Published var callType: CallType = .voice
    @Published var remoteUserId: String = ""
    @Published var remoteDisplayName: String = ""
    @Published var callDuration: TimeInterval = 0
    @Published var isMuted: Bool = false
    @Published var isSpeakerOn: Bool = true
    @Published var isVideoOn: Bool = false
    @Published var participants: [CallParticipant] = []
    @Published var callHistory: [CallRecord] = []
    @Published var incomingCallFrom: String?
    @Published var widgetUrl: URL?
    @Published var errorMessage: String?

    private var ffiClient: Client? { KeychainManager.shared.ffiClient }
    private var timer: Timer?
    /// RTC notification event ID for declineCall
    var rtcNotificationEventId: String?
    /// Room ID for the current call
    var callRoomId: String?
    private let callService: Any? = nil   // TODO: 后续接入 CallService

    // MARK: - 通话操作

    // TODO: Rust FFI 补全后接入 → callService.placeCall(roomId:isVideo:)
    /// 发起通话
    func startCall(userId: String, displayName: String, callType: CallType) async {
        remoteUserId = userId
        remoteDisplayName = displayName
        self.callType = callType

        callState = .calling
        let props = VirtualElementCallWidgetProperties(
            elementCallUrl: "https://call.element.io",
            widgetId: UUID().uuidString,
            encryption: .perParticipantKeys
        )
        let config = VirtualElementCallWidgetConfig(intent: .startCall)
        _ = try newVirtualElementCallWidget(props: props, config: config)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        callState = .connected
        startTimer()
    }

    // TODO: Rust FFI 补全后接入 → callService.answerCall()
    /// 接听来电
    func acceptCall() {
        guard callState == .ringing else { return }
        callState = .connected
        startTimer()
    }

    // TODO: Rust FFI 补全后接入 → callService.declineCall(rtcNotificationEventId:)
    /// 拒绝来电
    func declineCall() async {
        if let eventId = rtcNotificationEventId,
           let roomId = callRoomId,
           let client = ffiClient {
            do {
                let room = try await client.getRoom(roomId: roomId)
                try await room.declineCall(rtcNotificationEventId: eventId)
            } catch { }
        }
        callState = .declined
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.reset()
        }
    }

    // TODO: Rust FFI 补全后接入 → callService.hangupCall()
    /// 挂断
    func hangUp() {
        timer?.invalidate()
        timer = nil
        callState = .ended
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.reset()
        }
    }

    // TODO: Rust FFI 补全后接入 → voipCall.toggleMute()
    /// 切换静音
    func toggleMute() {
        isMuted.toggle()
    }

    // TODO: Rust FFI 补全后接入 → voipCall.toggleSpeaker()
    /// 切换扬声器
    func toggleSpeaker() {
        isSpeakerOn.toggle()
    }

    // TODO: Rust FFI 补全后接入 → voipCall.toggleVideo()
    /// 切换视频
    func toggleVideo() {
        isVideoOn.toggle()
    }

    // MARK: - 模拟来电

    func simulateIncomingCall(from userId: String, displayName: String, callType: CallType = .voice) {
        remoteUserId = userId
        remoteDisplayName = displayName
        self.callType = callType
        incomingCallFrom = displayName
        callState = .ringing
    }

    // MARK: - 通话记录

    func loadCallHistory() {
        let now = Date()
        callHistory = [
            CallRecord(id: "cr1", participantId: "@alice:example.com", participantName: "Alice", callType: .video, state: .ended, startTime: now.addingTimeInterval(-7200), endTime: now.addingTimeInterval(-5400), duration: 1800, isIncoming: false),
            CallRecord(id: "cr2", participantId: "@bob:example.com", participantName: "Bob", callType: .voice, state: .missed, startTime: now.addingTimeInterval(-86400), endTime: nil, duration: nil, isIncoming: true),
            CallRecord(id: "cr3", participantId: "@charlie:example.com", participantName: "Charlie", callType: .voice, state: .ended, startTime: now.addingTimeInterval(-100000), endTime: now.addingTimeInterval(-99900), duration: 100, isIncoming: true),
            CallRecord(id: "cr4", participantId: "@eve:example.com", participantName: "Eve", callType: .video, state: .declined, startTime: now.addingTimeInterval(-200000), endTime: nil, duration: nil, isIncoming: false),
        ]
    }

    func deleteCallRecord(_ record: CallRecord) {
        callHistory.removeAll { $0.id == record.id }
    }

    func clearCallHistory() {
        callHistory.removeAll()
    }

    // MARK: - Private

    private func startTimer() {
        callDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.callDuration += 1
            }
        }
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        callState = .idle
        callDuration = 0
        isMuted = false
        isSpeakerOn = true
        isVideoOn = false
        incomingCallFrom = nil
        widgetUrl = nil
    }

    var formattedDuration: String {
        let mins = Int(callDuration) / 60
        let secs = Int(callDuration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}