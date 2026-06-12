//
//  LocationShareService.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: Encapsulates LocationShare-related
//    UniFFI calls into typed async throws Swift methods.

import Foundation
import Combine

// MARK: - LocationShareService

/// Wraps matrix-rust-sdk UniFFI bindings for LocationShare operations.
/// All methods are async throws and access the FFI Client via KeychainManager.

@MainActor
final class LocationShareService: ObservableObject {
    static let shared = LocationShareService()

    private init() {}


    // MARK: - Live Location Sharing

    /// 开始实时位置共享
    func startLiveLocationShare(geoUri: String, timeoutMs: UInt64, roomId: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.notInitialized }
        guard let room = try? await client.getRoom(roomId: roomId) else { throw SocialFeedError.roomNotFound }
        try await room.startLiveLocationShare(geoUri: geoUri, timeout: timeoutMs)
    }

    /// 停止实时位置共享
    func stopLiveLocationShare(roomId: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.notInitialized }
        guard let room = try? await client.getRoom(roomId: roomId) else { throw SocialFeedError.roomNotFound }
        try await room.stopLiveLocationShare()
    }

    /// 发送位置更新
    func sendLiveLocation(geoUri: String, roomId: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.notInitialized }
        guard let room = try? await client.getRoom(roomId: roomId) else { throw SocialFeedError.roomNotFound }
        try await room.sendLiveLocation(geoUri: geoUri)
    }

    /// 获取位置观察者
    func getLiveLocationsObserver(roomId: String) async throws -> LiveLocationsObserver? {
        guard let client = Self.ffiClient else { throw SocialFeedError.notInitialized }
        guard let room = try? await client.getRoom(roomId: roomId) else { throw SocialFeedError.roomNotFound }
        return room.liveLocationsObserver()
    }

    /// 订阅位置更新
    func subscribeLiveLocations(roomId: String, onUpdate: @escaping (LiveLocationShareUpdate) -> Void) -> TaskHandle? {
        Task { @MainActor in
            guard let client = Self.ffiClient else { return }
            guard let room = try? await client.getRoom(roomId: roomId) else { return }
            guard let observer = room.liveLocationsObserver() else { return }
            _ = observer.subscribe(listener: LiveLocationListenerImpl(onUpdate: onUpdate))
        }
        return nil
    }

    // MARK: - Helpers

    static var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

}
