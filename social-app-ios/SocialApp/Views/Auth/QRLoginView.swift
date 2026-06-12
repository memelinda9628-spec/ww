import SwiftUI

// MARK: - QRLoginView
/// 二维码登录界面，对应 QRLoginService。
/// 支持扫码登录模式和授权登录模式。

struct QRLoginView: View {
    @StateObject private var viewModel = QRLoginViewModel()
    @State private var showScanner: Bool = false
    @State private var scannedRawData: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 模式切换
                modePicker

                Spacer()

                // 主内容区
                mainContent

                Spacer()

                // 底部操作栏
                if viewModel.errorMessage != nil || viewModel.isActive {
                    actionBar
                }
            }
            .navigationTitle("二维码登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.isActive {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("取消") { viewModel.cancel() }
                    }
                }
            }
            .onChange(of: scannedRawData) { data in
                guard !data.isEmpty else { return }
                viewModel.startScanning(data)
                showScanner = false
            }
        }
    }

    // MARK: - 模式切换

    private var modePicker: some View {
        Picker("模式", selection: $viewModel.mode) {
            ForEach(QRLoginViewModel.QRLoginMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding()
        .onChange(of: viewModel.mode) { newMode in
            viewModel.setMode(newMode)
        }
    }

    // MARK: - 主内容

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.mode {
        case .scanLogin:
            scanLoginContent
        case .grantLogin:
            grantLoginContent
        }
    }

    // MARK: - 扫码登录

    private var scanLoginContent: some View {
        VStack(spacing: 24) {
            // 状态图标
            Image(systemName: viewModel.progressIcon)
                .font(.system(size: 64))
                .foregroundColor(progressColor)

            Text(viewModel.progressTitle)
                .font(.title3.bold())

            // 不同阶段不同内容
            switch viewModel.progress {
            case .waitingForScan:
                Text("在其他设备上打开 Matrix 客户端\n获取登录二维码")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    showScanner = true
                } label: {
                    Label("扫描二维码", systemImage: "qrcode.viewfinder")
                        .font(.body.bold())
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)

            case .scanned:
                if let data = viewModel.parsedData {
                    VStack(spacing: 8) {
                        Text("即将登录到:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(data.rendezvousUrl)
                            .font(.subheadline.monospaced())
                            .lineLimit(2)
                    }
                }

                Button("确认登录") {
                    Task { await viewModel.confirmLogin() }
                }
                .buttonStyle(.borderedProminent)

            case .confirmed:
                ProgressView("正在验证身份...")
                ProgressView().padding(.top, 8)

            case .authenticated:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("登录成功！")
                    .font(.title3.bold())
                    .foregroundColor(.green)

            case .failed(let error):
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("重试") { viewModel.retry() }

            case .cancelled:
                Text("已取消")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // 手动输入模式（兜底）
            if viewModel.progress == .waitingForScan {
                Divider().padding(.horizontal, 40)
                Text("或手动输入")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("粘贴二维码数据...", text: $scannedRawData)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                    Button("确认") {
                        viewModel.startScanning(scannedRawData)
                    }
                    .disabled(scannedRawData.isEmpty)
                }
            }
        }
        .padding()
    }

    // MARK: - 授权登录

    private var grantLoginContent: some View {
        VStack(spacing: 24) {
            // 状态图标
            Image(systemName: "qrcode")
                .font(.system(size: 100))
                .foregroundColor(.primary)

            Text("授权登录")
                .font(.title3.bold())

            if let code = viewModel.displayableCode {
                // 展示可显示编码（模拟 QR 码占位）
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .frame(width: 200, height: 200)
                    VStack(spacing: 8) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 60))
                        Text(code.verificationUri)
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Text("请在其他设备上扫描此二维码进行授权")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("点击下方按钮生成授权二维码\n供其他设备扫码授权登录")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await viewModel.startGranting() }
                } label: {
                    Label("生成授权二维码", systemImage: "qrcode")
                        .font(.body.bold())
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
    }

    // MARK: - 底部操作栏

    private var actionBar: some View {
        HStack(spacing: 16) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("取消", role: .destructive) { viewModel.cancel() }
                .buttonStyle(.bordered)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var progressColor: Color {
        switch viewModel.progress {
        case .waitingForScan: return .accentColor
        case .scanned: return .orange
        case .confirmed: return .blue
        case .authenticated: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }
}