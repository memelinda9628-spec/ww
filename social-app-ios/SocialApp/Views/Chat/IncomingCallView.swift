import SwiftUI

// MARK: - IncomingCallView
/// 来电界面。
/// 全屏展示来电者头像+名称 + "接听"/"拒接"按钮。

struct IncomingCallView: View {
    @StateObject private var viewModel = IncomingCallViewModel()
    let callerName: String
    let callerAvatar: URL?
    let roomId: String
    let onAccept: (() -> Void)?
    let onDecline: (() -> Void)?

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [Color(.systemGray6), Color(.systemBackground)],
                startPoint: .top, endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)

            VStack(spacing: 40) {
                Spacer()

                // 来电标题
                VStack(spacing: 4) {
                    Text("来电邀请")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Text("Matrix Call")
                        .font(.headline)
                        .foregroundColor(.blue)
                }

                // 头像
                AvatarView(url: callerAvatar, name: callerName, size: 100)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )

                // 来电者信息
                VStack(spacing: 8) {
                    Text(callerName)
                        .font(.title)
                        .fontWeight(.bold)
                    Text(viewModel.statusText)
                        .font(.body)
                        .foregroundColor(.secondary)

                    // 来电动画指示器
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .scaleEffect(viewModel.isVibrating ? 1.5 : 1.0)
                            .opacity(viewModel.isVibrating ? 0.3 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(), value: viewModel.isVibrating)

                        Text("正在响铃...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // 操作按钮
                HStack(spacing: 60) {
                    // 拒接
                    VStack(spacing: 8) {
                        Button {
                            viewModel.decline(roomId: roomId)
                            onDecline?()
                        } label: {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                                .frame(width: 68, height: 68)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                        Text("拒接")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    // 接听
                    VStack(spacing: 8) {
                        Button {
                            viewModel.accept()
                            onAccept?()
                        } label: {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                                .frame(width: 68, height: 68)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                        Text("接听")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                // 提示信息
                Text("滑动接听或点击上方按钮")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 16)

                Spacer()
            }
            .padding(40)
        }
        .onAppear {
            viewModel.startRinging()
        }
        .onDisappear {
            viewModel.stopRinging()
        }
    }
}

// MARK: - IncomingCallViewModel

@MainActor
final class IncomingCallViewModel: ObservableObject {
    @Published var isVibrating: Bool = false
    @Published var statusText: String = "正在等待接听"

    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    func startRinging() {
        isVibrating = true

        // 模拟振铃 30 秒自动超时
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await MainActor.run {
                if isVibrating {
                    statusText = "对方未接听"
                    isVibrating = false
                }
            }
        }
    }

    func stopRinging() {
        isVibrating = false
    }

    func accept() {
        stopRinging()
        statusText = "已接听"
    }

    func decline(roomId: String) async {
        stopRinging()
        statusText = "已拒接"
        // FFI 已暴露，由上层 CallViewModel 管理 rtcNotificationEventId 并调用
    }
}