import Foundation

// MARK: - BeaconInfo
/// 信标信息，对应 Rust BeaconInfo

struct BeaconInfo: Sendable {
    let beaconId: String
    let geoUri: String
    let location: GeoCoordinate
    let timestamp: Date
}

// MARK: - GeoCoordinate
/// 地理坐标

struct GeoCoordinate: Sendable, Hashable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double?

    var formattedString: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }

    init(latitude: Double, longitude: Double, accuracy: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
    }
}

// MARK: - LiveLocationContent
/// 实时位置内容，对应 Rust LiveLocationContent

struct LiveLocationContent: Sendable {
    let geoUri: String
    let coordinate: GeoCoordinate
    let description: String?
    let timestamp: Date
}

// MARK: - LiveLocationShareUpdate
/// 位置共享状态变更，对应 Rust LiveLocationShareUpdate 枚举

enum LiveLocationShareUpdate: Sendable {
    case started(LiveLocationShare)
    case stopped(beaconId: String)
    case locationUpdated(LiveLocationShare)
    case expired(beaconId: String)

    var beaconId: String {
        switch self {
        case .started(let share): return share.beaconId
        case .stopped(let id): return id
        case .locationUpdated(let share): return share.beaconId
        case .expired(let id): return id
        }
    }

    var isActive: Bool {
        switch self {
        case .started, .locationUpdated: return true
        case .stopped, .expired: return false
        }
    }
}

// MARK: - LiveLocationShare
/// 实时位置共享会话，对应 Rust LiveLocationShare

struct LiveLocationShare: Identifiable, Sendable {
    let id: String
    let beaconId: String
    let roomId: String
    let initiatorId: String
    let initiatorName: String
    var currentLocation: GeoCoordinate
    let lastUpdate: Date
    let timeout: TimeInterval
    let isActive: Bool
    let participantIds: [String]

    var timeoutDate: Date {
        lastUpdate.addingTimeInterval(timeout)
    }

    var remainingTime: TimeInterval {
        max(0, timeoutDate.timeIntervalSinceNow)
    }

    var formattedRemaining: String {
        let remain = Int(remainingTime)
        if remain >= 3600 { return "\(remain / 3600)小时" }
        if remain >= 60 { return "\(remain / 60)分钟" }
        return "\(remain)秒"
    }
}

// MARK: - LiveLocationService
/// 实时位置共享服务，对应 Rust live_locations_observer.rs。
/// 负责开始/停止实时位置共享、发送位置更新、订阅变更。

@MainActor
final class LiveLocationService: ObservableObject {
    static let shared = LiveLocationService()

    @Published private(set) var activeShares: [String: LiveLocationShare] = [:]
    @Published private(set) var shareHistory: [String: [LiveLocationContent]] = [:]

    
    /// Get the FFI Client from KeychainManager
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

private init() {}

    // MARK: - 位置共享

    /// 开始实时位置共享 — 通过 room.startLiveLocationShare() FFI
    func startLiveLocationShare(
        coordinate: GeoCoordinate,
        roomId: String,
        timeout: TimeInterval = 3600,
        description: String? = nil
    ) async throws -> LiveLocationShare {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        let geoUri = "geo:\(coordinate.latitude),\(coordinate.longitude)"
        let beaconId = try await room.startLiveLocationShare(durationMillis: UInt64(timeout * 1000))
        let share = LiveLocationShare(
            id: UUID().uuidString,
            beaconId: beaconId,
            roomId: roomId,
            initiatorId: client.userId(),
            initiatorName: "我",
            currentLocation: coordinate,
            lastUpdate: Date(),
            timeout: timeout,
            isActive: true,
            participantIds: [client.userId()]
        )
        activeShares[beaconId] = share
        shareHistory[beaconId] = [
            LiveLocationContent(
                geoUri: geoUri,
                coordinate: coordinate,
                description: description,
                timestamp: Date()
            )
        ]
        return share
    }

    /// 停止实时位置共享 — 通过 room.stopLiveLocationShare() FFI
    func stopLiveLocationShare(beaconId: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        // 从 activeShares 获取 roomId
        guard let share = activeShares[beaconId] else {
            throw SocialFeedError.invalidState("未找到活跃的位置共享: \(beaconId)")
        }
        let room = try await client.getRoom(roomId: share.roomId)
        try await room.stopLiveLocationShare()

        activeShares[beaconId]?.update(isActive: false)
        activeShares.removeValue(forKey: beaconId)
    }

    /// 发送位置更新 — 通过 room.sendLiveLocation() FFI
    func sendLiveLocation(
        coordinate: GeoCoordinate,
        beaconId: String? = nil
    ) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let targetBeaconId = beaconId ?? activeShares.keys.first
        guard let bid = targetBeaconId, let share = activeShares[bid] else {
            throw SocialFeedError.invalidState("没有活跃的位置共享")
        }
        let geoUri = "geo:\(coordinate.latitude),\(coordinate.longitude)"
        let room = try await client.getRoom(roomId: share.roomId)
        try await room.sendLiveLocation(geoUri: geoUri)

        let content = LiveLocationContent(
            geoUri: geoUri,
            coordinate: coordinate,
            description: nil,
            timestamp: Date()
        )
        if var updatedShare = activeShares[bid] {
            updatedShare.update(currentLocation: coordinate)
            activeShares[bid] = updatedShare
        }
        shareHistory[bid, default: []].append(content)
    }

    // MARK: - 查询

    /// 获取房间内所有活跃的位置共享
    func activeShares(in roomId: String) -> [LiveLocationShare] {
        activeShares.values.filter { $0.roomId == roomId }
    }

    /// 获取指定会话的位置历史
    func locationHistory(for beaconId: String) -> [LiveLocationContent] {
        shareHistory[beaconId] ?? []
    }

    /// 是否有活跃的位置共享
    func hasActiveShare(in roomId: String) -> Bool {
        activeShares.values.contains { $0.roomId == roomId && $0.isActive }
    }

// MARK: - LiveLocationShare Extensions

private extension LiveLocationShare {
    mutating func update(isActive: Bool) {
        self = LiveLocationShare(
            id: id, beaconId: beaconId, roomId: roomId,
            initiatorId: initiatorId, initiatorName: initiatorName,
            currentLocation: currentLocation, lastUpdate: lastUpdate,
            timeout: timeout, isActive: isActive, participantIds: participantIds
        )
    }

    mutating func update(currentLocation: GeoCoordinate) {
        self = LiveLocationShare(
            id: id, beaconId: beaconId, roomId: roomId,
            initiatorId: initiatorId, initiatorName: initiatorName,
            currentLocation: currentLocation, lastUpdate: Date(),
            timeout: timeout, isActive: isActive, participantIds: participantIds
        )
    }
}