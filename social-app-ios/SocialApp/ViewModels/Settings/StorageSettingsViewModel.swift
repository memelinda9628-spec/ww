//
//  StorageSettingsViewModel.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: ViewModel for StorageSettingsService settings, bridging
//    StorageSettingsServiceService to SwiftUI views.

import Foundation
import Combine
import SwiftUI

// MARK: - StorageSettingsViewModel

@MainActor
final class StorageSettingsViewModel: ObservableObject {

    @Published var cacheSize: String = "计算中..."
    @Published var mediaRetentionDays: UInt32 = 30
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = StorageSettingsService.shared

    func loadStorageInfo() {
        isLoading = true
        Task {
            do {
                let sizes = try await service.getStoreSizes()
                await MainActor.run { self.cacheSize = "\(sizes)"; self.isLoading = false }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
            }
        }
    }

    func clearCache() {
        Task {
            do { try await service.clearCaches(); await loadStorageInfo() }
            catch { await MainActor.run { self.errorMessage = error.localizedDescription } }
        }
    }

    func setRetention(days: UInt32) {
        Task { try? await service.setMediaRetentionPolicy(maxAgeDays: days) }
    }

    func optimizeStorage() {
        Task { try? await service.optimizeStores() }
    }

}
