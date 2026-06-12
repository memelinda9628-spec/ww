//
//  AccountSettingsView.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: SwiftUI view for AccountSettings settings.

import SwiftUI

// MARK: - AccountSettingsView

struct AccountSettingsView: View {

    @StateObject private var viewModel = AccountSettingsViewModel()

    var body: some View {
        Form {
            Section("个人资料") {
                HStack { Text("显示名称"); Spacer(); Text(viewModel.displayName).foregroundColor(.secondary) }
                HStack { Text("头像"); Spacer(); AvatarView(url: viewModel.avatarUrl, size: 40) }
            }
            Section("安全") {
                Button("修改密码") { /* navigate to change password */ }
                    .disabled(viewModel.isLoading)
                Button("管理邮箱/手机") { /* navigate to 3pid management */ }
            }
            Section("会话") {
                Button("登出", role: .destructive) { viewModel.logout() }
                Button("注销账户", role: .destructive) { }
            }
        }
        .navigationTitle("账户设置")
        .onAppear { viewModel.loadProfile() }
        .alert("错误", isPresented: Binding<Bool>((viewModel.errorMessage != nil)) {
            Button("确定") { }
        } message: { Text(viewModel.errorMessage ?? "") }
    }

}

#Preview {
    NavigationView { AccountSettingsView() }
}
