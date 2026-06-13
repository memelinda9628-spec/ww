//
//  SecuritySettingsViewModel.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: ViewModel for SecuritySettingsService settings, bridging
//    SecuritySettingsServiceService to SwiftUI views.

import Foundation
import Combine
import SwiftUI

// MARK: - SecuritySettingsViewModel

@MainActor
final class SecuritySettingsViewModel: ObservableObject {

    @Published var showVerificationEmoji = false
    @Published var verificationState: String = "unknown"
    @Published var backupState: String = "unknown"
    @Published var recoveryState: String = "unknown"
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = SecuritySettingsService.shared

    func loadStates() {
        isLoading = true
        Task {
            do {
                let vs = try await service.getVerificationState()
                let bs = try await service.getBackupState()
                let rs = try await service.getRecoveryState()
                await MainActor.run {
                    self.verificationState = "\(vs)"
                    self.backupState = "\(bs)"
                    self.recoveryState = "\(rs)"
                    self.isLoading = false
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
            }
        }
    }

    func enableBackups() {
        Task {
            do { try await service.enableBackups() }
            catch { await MainActor.run { self.errorMessage = error.localizedDescription } }
        }
    }

    func resetIdentity() {
        Task {
            do { try await service.resetIdentity() }
            catch { await MainActor.run { self.errorMessage = error.localizedDescription } }
        }
    }

    func recover(key: String) {
        Task {
            do { try await service.recover(recoveryKey: key) }
            catch { await MainActor.run { self.errorMessage = error.localizedDescription } }
        }
    }

}
