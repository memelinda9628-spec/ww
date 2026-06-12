//
//  SecuritySettingsView.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: SwiftUI view for SecuritySettings settings.

import SwiftUI

// MARK: - SecuritySettingsView

struct SecuritySettingsView: View {

    @StateObject private var viewModel = SecuritySettingsViewModel()
    @State private var recoveryKey = ""

    var body: some View {
        Form {
            Section("验证状态") {
                LabeledContent("当前状态", value: viewModel.verificationState)
                Button("发起设备验证") { viewModel.verifyDevice() }
            }
            Section("密钥备份") {
                LabeledContent("备份状态", value: viewModel.backupState)
                Button("启用备份") { viewModel.enableBackups() }
            }
            Section("恢复") {
                SecureField("恢复密钥", text: $recoveryKey)
                Button("恢复") { viewModel.recover(key: recoveryKey) }
            }
            Section("重置") {
                Button("重置加密身份", role: .destructive) { viewModel.resetIdentity() }
            }
        }
        .navigationTitle("安全设置")
        .onAppear { viewModel.loadStates() }
    }

}

#Preview {
    NavigationView { SecuritySettingsView() }
}
