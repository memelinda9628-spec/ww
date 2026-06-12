import SwiftUI

// MARK: - RoomSettingsView
/// 房间设置界面，对应 RoomSettingsService。
/// 当前支持：修改当前用户在房间内的显示名（房间昵称）。

struct RoomSettingsView: View {
    let roomId: String

    @StateObject private var viewModel = RoomSettingsViewModel()
    @State private var showSaveAlert = false
    @State private var saveError: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            // 房间昵称
            Section(header: Text("房间昵称")) {
                TextField("输入在此房间的显示名（留空则使用默认昵称）", text: $viewModel.displayName)
                    .textContentType(.nickname)
                    .onSubmit { save() }
            }
            if let hint = viewModel.nameHint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 保存按钮
            Section {
                Button {
                    save()
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("保存")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .navigationTitle("房间设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadCurrentDisplayName(roomId: roomId)
        }
        .alert("保存成功", isPresented: $showSaveAlert) {
            Button("确定") { dismiss() }
        } message: {
            Text("房间昵称已更新")
        }
        .alert("保存失败", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("确定") { saveError = nil }
        } message: {
            Text(saveError ?? "未知错误")
        }
    }

    private func save() {
        Task {
            do {
                try await viewModel.saveDisplayName(roomId: roomId)
                showSaveAlert = true
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}

// MARK: - RoomSettingsViewModel
/// 房间设置 ViewModel，持有 RoomSettingsService 调用逻辑。

@MainActor
final class RoomSettingsViewModel: ObservableObject {
    @Published var displayName: String = ""
    @Published var isSaving: Bool = false
    @Published var nameHint: String?

    private let service = RoomSettingsService.shared()

    /// 加载当前用户在房间内的显示名
    func loadCurrentDisplayName(roomId: String) async {
        do {
            let name = try await service.getOwnMemberDisplayName(roomId: roomId)
            displayName = name ?? ""
        } catch {
            nameHint = "无法加载当前昵称：\(error.localizedDescription)"
        }
    }

    /// 保存房间昵称
    func saveDisplayName(roomId: String) async throws {
        isSaving = true
        defer { isSaving = false }
        try await service.setOwnMemberDisplayName(roomId: roomId, displayName: displayName.isEmpty ? nil : displayName)
    }
}
