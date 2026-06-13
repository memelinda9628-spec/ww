//
//  NotificationSettingsViewModel.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: ViewModel for NotificationSettingsService settings, bridging
//    NotificationSettingsServiceService to SwiftUI views.

import Foundation
import Combine
import SwiftUI

// MARK: - NotificationSettingsViewModel

@MainActor
final class NotificationSettingsViewModel: ObservableObject {

    @Published var roomMentionEnabled = true
    @Published var userMentionEnabled = true
    @Published var callEnabled = true
    @Published var inviteEnabled = true
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = NotificationSettingsService.shared

    func loadSettings() {
        isLoading = true
        Task {
            do {
                let r = try await service.isRoomMentionEnabled()
                let u = try await service.isUserMentionEnabled()
                let c = try await service.isCallEnabled()
                let i = try await service.isInviteForMeEnabled()
                await MainActor.run {
                    self.roomMentionEnabled = r; self.userMentionEnabled = u
                    self.callEnabled = c; self.inviteEnabled = i; self.isLoading = false
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
            }
        }
    }

    func toggleRoomMention(_ enabled: Bool) {
        Task { try? await service.setRoomMentionEnabled(enabled) }
    }

    func toggleUserMention(_ enabled: Bool) {
        Task { try? await service.setUserMentionEnabled(enabled) }
    }

    func toggleCall(_ enabled: Bool) {
        Task { try? await service.setCallEnabled(enabled) }
    }

    func toggleInvite(_ enabled: Bool) {
        Task { try? await service.setInviteForMeEnabled(enabled) }
    }

    func registerPusher(token: String, appId: String) {
        Task { try? await service.setPusher(deviceToken: token, appId: appId) }
    }

}
