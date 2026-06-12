//
//  AccountSettingsViewModel.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: ViewModel for AccountSettings settings, bridging
//    AccountSettingsService to SwiftUI views.

import Foundation
import Combine
import SwiftUI

// MARK: - AccountSettingsViewModel

@MainActor
final class AccountSettingsViewModel: ObservableObject {

    @Published var displayName: String = ""
    @Published var avatarUrl: String?
    @Published var email: String?
    @Published var phone: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = AccountSettingsService.shared

    func loadProfile() {
        isLoading = true
        Task {
            do {
                let name = try await service.getDisplayName()
                let avatar = try? await service.getAvatarUrl()
                await MainActor.run {
                    self.displayName = name
                    self.avatarUrl = avatar
                    self.isLoading = false
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
            }
        }
    }

    func updateDisplayName(_ name: String) {
        Task {
            do {
                try await service.setDisplayName(name)
                await MainActor.run { self.displayName = name }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func changePassword(new: String, auth: [String: Any]?) {
        Task {
            do {
                try await service.changePassword(newPassword: new, authData: auth)
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func logout() {
        Task {
            do { try await service.logout() }
            catch { await MainActor.run { self.errorMessage = error.localizedDescription } }
        }
    }

}
