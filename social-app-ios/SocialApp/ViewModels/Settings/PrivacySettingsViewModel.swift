//
//  PrivacySettingsViewModel.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: ViewModel for PrivacySettingsService settings, bridging
//    PrivacySettingsServiceService to SwiftUI views.

import Foundation
import Combine
import SwiftUI

// MARK: - PrivacySettingsViewModel

@MainActor
final class PrivacySettingsViewModel: ObservableObject {

    @Published var ignoredUsers: [String] = []
    @Published var forgetRoomWhenLeaving = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = PrivacySettingsService.shared

    func loadIgnoredUsers() {
        isLoading = true
        Task {
            do {
                let users = try await service.getIgnoredUsers()
                let forget = try await service.getForgetRoomWhenLeaving()
                await MainActor.run { self.ignoredUsers = users; self.forgetRoomWhenLeaving = forget; self.isLoading = false }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
            }
        }
    }

    func unignoreUser(_ userId: String) {
        Task { try? await service.unignoreUser(userId: userId); await loadIgnoredUsers() }
    }

}
