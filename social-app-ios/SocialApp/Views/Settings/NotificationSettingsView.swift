//
//  NotificationSettingsView.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: SwiftUI view for NotificationSettings settings.

import SwiftUI

// MARK: - NotificationSettingsView

struct NotificationSettingsView: View {

    @StateObject private var viewModel = NotificationSettingsViewModel()

    var body: some View {
        Form {
            Section("推送通知") {
                Toggle("@提及通知", isOn: Binding(get: { viewModel.roomMentionEnabled }, set: { viewModel.toggleRoomMention($0) }))
                Toggle("用户 @通知", isOn: Binding(get: { viewModel.userMentionEnabled }, set: { viewModel.toggleUserMention($0) }))
                Toggle("通话通知", isOn: Binding(get: { viewModel.callEnabled }, set: { viewModel.toggleCall($0) }))
                Toggle("邀请通知", isOn: Binding(get: { viewModel.inviteEnabled }, set: { viewModel.toggleInvite($0) }))
            }
            Section("设备推送") {
                Button("注册推送通道") { viewModel.registerPusher(token: "device-token", appId: "com.example.app") }
            }
        }
        .navigationTitle("通知设置")
        .onAppear { viewModel.loadSettings() }
    }

}

#Preview {
    NavigationView { NotificationSettingsView() }
}
