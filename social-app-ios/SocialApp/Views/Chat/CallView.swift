import SwiftUI
import WebKit

// MARK: - 通话状态管理说明
//
// 当前 mute/speaker 切换为本地 UI 状态翻转，
// 待 Rust FFI 补全 VoipCall 类型后接入真实通话控制。

// MARK: - CallView
/// 通话界面容器（对应 CallViewModel）。
/// SwiftUI + WKWebView 桥接，加载 Element Call URL。
/// 含：顶部通话状态栏、底部挂断/静音/扬声器按钮。

struct CallView: View {
    @StateObject private var viewModel = CallViewModel()
    let callUrl: String
    let roomName: String

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 通话内容区（Element Call WebView）
                CallWebView(urlString: callUrl)
                    .edgesIgnoringSafeArea(.all)

                // 顶部状态栏
                VStack {
                    callStatusBar
                        .padding(.horizontal, 20)
                        .padding(.top, geometry.safeAreaInsets.top + 10)
                    Spacer()
                }

                // 底部控制按钮
                VStack {
                    Spacer()
                    bottomControls
                        .padding(.horizontal, 30)
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                }
            }
        }
        .background(Color.black)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(true)
        .task { viewModel.startCall() }
        .onDisappear { viewModel.cleanup() }
    }

    // MARK: - Call Status Bar

    private var callStatusBar: some View {
        VStack(spacing: 2) {
            Text(roomName)
                .font(.headline)
                .foregroundColor(.white)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var statusText: String {
        switch viewModel.callState {
        case .connecting: return "正在连接..."
        case .ringing: return "正在呼叫..."
        case .connected:
            let mins = viewModel.callDuration / 60
            let secs = viewModel.callDuration % 60
            return String(format: "%02d:%02d", mins, secs)
        case .ended: return "通话结束"
        case .failed: return "连接失败"
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 40) {
            // 静音
            ControlButton(
                icon: viewModel.isMuted ? "mic.slash.fill" : "mic.fill",
                label: viewModel.isMuted ? "取消静音" : "静音",
                foregroundColor: .white,
                backgroundColor: viewModel.isMuted ? Color.white.opacity(0.3) : Color.white.opacity(0.15)
            ) {
                // TODO: Rust FFI 补全后接入真实通话控制
                viewModel.toggleMute()
            }

            // 挂断
            ControlButton(
                icon: "phone.down.fill",
                label: "挂断",
                foregroundColor: .white,
                backgroundColor: .red
            ) {
                // TODO: Rust FFI 补全后接入真实通话控制
                viewModel.hangUp()
            }

            // 扬声器
            ControlButton(
                icon: viewModel.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.slash.fill",
                label: "扬声器",
                foregroundColor: .white,
                backgroundColor: viewModel.isSpeakerOn ? Color.white.opacity(0.3) : Color.white.opacity(0.15)
            ) {
                // TODO: Rust FFI 补全后接入真实通话控制
                viewModel.toggleSpeaker()
            }
        }
    }
}

// MARK: - ControlButton

struct ControlButton: View {
    let icon: String
    let label: String
    let foregroundColor: Color
    let backgroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(backgroundColor)
                    .clipShape(Circle())
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Call WebView

struct CallWebView: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - CallState

enum CallState {
    case connecting
    case ringing
    case connected
    case ended
    case failed
}

// MARK: - CallViewModel

@MainActor
final class CallViewModel: ObservableObject {
    @Published var callState: CallState = .connecting
    @Published var callDuration: Int = 0
    @Published var isMuted: Bool = false
    @Published var isSpeakerOn: Bool = true

    private var timer: Timer?
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    func startCall() {
        callState = .connecting

        // 模拟连接过程
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                if callState == .connecting {
                    callState = .connected
                    startTimer()
                }
            }
        }
    }

    func hangUp() {
        callState = .ended
        timer?.invalidate()
        timer = nil
    }

    func toggleMute() {
        isMuted.toggle()
        // TODO: UniFFI - Call mute/unmute (待 Call FFI 暴露 mute 接口)
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        // TODO: iOS AVAudioSession override
    }

    func cleanup() {
        timer?.invalidate()
        timer = nil
        callState = .ended
    }

    private func startTimer() {
        timer?.invalidate()
        callDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.callDuration += 1
            }
        }
    }
}