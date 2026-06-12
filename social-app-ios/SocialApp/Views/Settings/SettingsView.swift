import SwiftUI

// MARK: - SettingsView
/// 设置与偏好主视图

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showChangePassword = false
    @State private var showSetPIN = false

    var body: some View {
        NavigationView {
            Form {
                // MARK: 通用
                Section("通用") {
                    Toggle("推送通知", isOn: $viewModel.notificationsEnabled)

                    Picker("外观", selection: $viewModel.darkMode) {
                        ForEach(viewModel.darkModeOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }

                    Picker("语言", selection: $viewModel.language) {
                        ForEach(viewModel.languageOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                }

                // MARK: 隐私
                Section("隐私") {
                    Toggle("显示在线状态", isOn: $viewModel.showOnlineStatus)
                    Toggle("已读回执", isOn: $viewModel.readReceipts)
                    Toggle("输入状态提示", isOn: $viewModel.typingIndicators)
                    Toggle("允许通过手机号找到我", isOn: $viewModel.allowSearchByPhone)
                    Toggle("允许通过邮箱找到我", isOn: $viewModel.allowSearchByEmail)
                }

                // MARK: 安全
                Section("安全") {
                    Button("修改密码") {
                        showChangePassword = true
                    }

                    Toggle("应用锁 (PIN)", isOn: Binding(
                        get: { viewModel.pinEnabled },
                        set: { newValue in
                            if newValue {
                                showSetPIN = true
                            } else {
                                viewModel.setPIN("")
                            }
                        }
                    ))

                    if let msg = viewModel.passwordChangeMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                // MARK: 存储
                Section("存储") {
                    HStack {
                        Text("缓存大小")
                        Spacer()
                        Text(viewModel.cacheSize)
                            .foregroundColor(.secondary)
                    }

                    Button("清理缓存") {
                        Task { await viewModel.clearCache() }
                    }
                    .disabled(viewModel.isClearingCache)
                }

                // MARK: 账户
                Section("账户") {
                    HStack {
                        Text("Matrix ID")
                        Spacer()
                        Text(viewModel.matrixUserId)
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }

                    HStack {
                        Text("显示名称")
                        Spacer()
                        Text(viewModel.displayName)
                            .foregroundColor(.secondary)
                    }

                    Button("导出数据") {
                        Task {
                            do {
                                _ = try await viewModel.exportData()
                            } catch {
                                print("[Settings] 导出失败: \(error)")
                            }
                        }
                    }

                    Button("注销账户") {
                        Task {
                            do {
                                try await viewModel.deactivateAccount()
                            } catch {
                                print("[Settings] 注销失败: \(error)")
                            }
                        }
                    }
                    .foregroundColor(.red)
                }

                // MARK: 关于
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("SDK")
                        Spacer()
                        Text(viewModel.sdkVersion)
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }

                    Button("检查更新") {
                        viewModel.checkForUpdates()
                    }

                    Button("反馈问题") {
                        viewModel.reportProblem()
                    }
                }

                // MARK: 危险操作
                Section {
                    Button("退出登录") {
                        viewModel.logout()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showChangePassword) {
                ChangePasswordView(viewModel: viewModel, isPresented: $showChangePassword)
            }
            .sheet(isPresented: $showSetPIN) {
                SetPINView(viewModel: viewModel, isPresented: $showSetPIN)
            }
            .onAppear {
                viewModel.calculateCacheSize()
            }
        }
    }
}

// MARK: - ChangePasswordView

struct ChangePasswordView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isPresented: Bool

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section("修改密码") {
                    SecureField("当前密码", text: $oldPassword)
                    SecureField("新密码", text: $newPassword)
                    SecureField("确认新密码", text: $confirmPassword)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button("确认修改") {
                        changePassword()
                    }
                    .disabled(oldPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
                }
            }
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
            }
        }
    }

    private func changePassword() {
        guard newPassword == confirmPassword else {
            errorMessage = "两次输入的新密码不一致"
            return
        }
        guard newPassword.count >= 8 else {
            errorMessage = "新密码长度至少8位"
            return
        }
        Task {
            do {
                try await viewModel.changePassword(oldPassword: oldPassword, newPassword: newPassword)
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - SetPINView

struct SetPINView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isPresented: Bool

    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section("设置应用锁 PIN") {
                    SecureField("6位数字 PIN", text: $pin)
                        .keyboardType(.numberPad)
                    SecureField("确认 PIN", text: $confirmPIN)
                        .keyboardType(.numberPad)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button("确认设置") {
                        setPIN()
                    }
                    .disabled(pin.count != 6 || confirmPIN.count != 6)
                }
            }
            .navigationTitle("应用锁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
            }
        }
    }

    private func setPIN() {
        guard pin == confirmPIN else {
            errorMessage = "两次输入的 PIN 不一致"
            return
        }
        guard pin.allSatisfy({ $0.isNumber }) else {
            errorMessage = "PIN 只能包含数字"
            return
        }
        viewModel.setPIN(pin)
        isPresented = false
    }
}

// MARK: - SettingsView_Previews

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}