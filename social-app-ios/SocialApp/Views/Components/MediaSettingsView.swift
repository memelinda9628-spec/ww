import SwiftUI

// MARK: - MediaSettingsView
/// 媒体展示设置页（对应 GAP §8.7）。
/// 开关：媒体预览策略、邀请头像策略。

struct MediaSettingsView: View {
    @StateObject private var viewModel = MediaSettingsViewModel()

    var body: some View {
        Form {
            // MARK: 媒体预览策略
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("媒体预览策略")
                        .font(.headline)

                    Text("控制客户端在消息列表和通知中如何展示图片和文件预览。更改设置后，需重新打开对话以生效。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ForEach(MediaPreviewPolicyOption.allCases) { option in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(.body)
                            Text(option.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if viewModel.selectedPreviewPolicy == option {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await viewModel.setPreviewPolicy(option) }
                    }
                }
            } header: {
                Text("消息内媒体展示")
            }

            // MARK: 邀请头像策略
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("邀请用户头像")
                        .font(.headline)

                    Text("在新成员邀请列表中，是否展示受邀用户的头像。关闭后仅显示用户名以节省带宽。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle("展示邀请用户头像", isOn: $viewModel.showInviteAvatars)
                    .onChange(of: viewModel.showInviteAvatars) { newValue in
                        Task { await viewModel.setInviteAvatarPolicy(show: newValue) }
                    }

                if viewModel.showInviteAvatars {
                    Text("头像将从各用户 Homeserver 获取，可能增加加载时间")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("邀请成员展示")
            }

            // MARK: 状态
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView("正在加载配置...")
                    Spacer()
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("媒体设置")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadConfig() }
    }
}

// MARK: - MediaPreviewPolicyOption

enum MediaPreviewPolicyOption: String, CaseIterable, Identifiable {
    case auto
    case always
    case wifiOnly
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动"
        case .always: return "始终预览"
        case .wifiOnly: return "仅 Wi-Fi 下预览"
        case .never: return "从不预览"
        }
    }

    var description: String {
        switch self {
        case .auto: return "根据网络状况和服务器配置自动选择"
        case .always: return "始终在消息列表中展示媒体预览"
        case .wifiOnly: return "仅在 Wi-Fi 环境下自动加载预览图"
        case .never: return "不自动加载，点击后手动查看"
        }
    }
}

// MARK: - MediaSettingsViewModel

@MainActor
final class MediaSettingsViewModel: ObservableObject {
    @Published var selectedPreviewPolicy: MediaPreviewPolicyOption = .auto
    @Published var showInviteAvatars: Bool = true
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    private func mapPolicy(_ raw: String) -> MediaPreviewPolicyOption {
        switch raw {
        case "always": return .always
        case "wifi_only": return .wifiOnly
        case "never": return .never
        default: return .auto
        }
    }

    func loadConfig() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }

            let policy = try await client.getMediaPreviewDisplayPolicy()
            let config = try await client.fetchMediaPreviewConfig()
            selectedPreviewPolicy = mapMediaPreviews(policy)
            showInviteAvatars = config?.mediaPreviews != .off
        } catch {
            errorMessage = "加载配置失败: \(error.localizedDescription)"
        }
    }

    func setPreviewPolicy(_ option: MediaPreviewPolicyOption) async {
        selectedPreviewPolicy = option

        do {
            guard let client = ffiClient else { return }
            try await client.setMediaPreviewDisplayPolicy(policy: policyOptionToMediaPreviews(option))
        } catch {
            errorMessage = "设置失败: \(error.localizedDescription)"
        }
    }

    func setInviteAvatarPolicy(show: Bool) async {
        do {
            guard let client = ffiClient else { return }
            try await client.setInviteAvatarsDisplayPolicy(policy: show ? .on : .off)
        } catch {
            errorMessage = "设置失败: \(error.localizedDescription)"
            showInviteAvatars = !show // 回滚
        }
    }

    private func mapMediaPreviews(_ policy: MediaPreviews?) -> MediaPreviewPolicyOption {
        switch policy {
        case .on: return .always
        case .private: return .wifiOnly
        case .off: return .never
        case .none: return .auto
        }
    }

    private func policyOptionToMediaPreviews(_ option: MediaPreviewPolicyOption) -> MediaPreviews {
        switch option {
        case .always: return .on
        case .wifiOnly, .auto: return .private
        case .never: return .off
        }
    }
}