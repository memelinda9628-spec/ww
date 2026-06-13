//
//  PrivacySettingsView.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: SwiftUI view for PrivacySettings settings.

import SwiftUI

// MARK: - PrivacySettingsView

struct PrivacySettingsView: View {

    @StateObject private var viewModel = PrivacySettingsViewModel()

    var body: some View {
        Form {
            Section("屏蔽用户") {
                if viewModel.ignoredUsers.isEmpty {
                    Text("没有被屏蔽的用户").foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.ignoredUsers, id: \.self) { userId in
                        HStack {
                            Text(userId).font(.caption)
                            Spacer()
                            Button("取消屏蔽") { viewModel.unignoreUser(userId) }
                        }
                    }
                }
            }
            Section("房间设置") {
                Toggle("离开时遗忘房间", isOn: $viewModel.forgetRoomWhenLeaving)
            }
        }
        .navigationTitle("隐私设置")
        .onAppear { viewModel.loadIgnoredUsers() }
    }

}

#Preview {
    NavigationView { PrivacySettingsView() }
}
