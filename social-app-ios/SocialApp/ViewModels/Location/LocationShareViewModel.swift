//
//  LocationShareViewModel.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: ViewModel for LocationShareService settings, bridging
//    LocationShareServiceService to SwiftUI views.

import Foundation
import Combine
import SwiftUI

// MARK: - LocationShareViewModel

@MainActor
final class LocationShareViewModel: ObservableObject {

    @Published var activeShares: [LiveLocationShare] = []
    @Published var isSharing = false
    @Published var errorMessage: String?

    private let service = LocationShareService.shared

    func startSharing(geoUri: String, timeoutMs: UInt64, roomId: String) {
        Task {
            do {
                try await service.startLiveLocationShare(geoUri: geoUri, timeoutMs: timeoutMs, roomId: roomId)
                await MainActor.run { self.isSharing = true }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func stopSharing(roomId: String) {
        Task {
            do {
                try await service.stopLiveLocationShare(roomId: roomId)
                await MainActor.run { self.isSharing = false }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func updateLocation(geoUri: String, roomId: String) {
        Task { try? await service.sendLiveLocation(geoUri: geoUri, roomId: roomId) }
    }

}
