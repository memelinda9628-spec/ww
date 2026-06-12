import Foundation
import SwiftUI
import MapKit

// MARK: - LiveLocationViewModel
/// 实时位置共享 ViewModel，对应 LiveLocationService。
/// 管理位置共享列表、地图交互、位置历史。

@MainActor
final class LiveLocationViewModel: ObservableObject {
    @Published var activeShares: [LiveLocationShare] = []
    @Published var selectedShare: LiveLocationShare?
    @Published var locationHistory: [LiveLocationContent] = []
    @Published var currentRegion: MKCoordinateRegion = .init(
        center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @Published var isSharing: Bool = false
    @Published var sharingBeaconId: String?
    @Published var errorMessage: String?
    @Published var shareDescription: String = ""
    @Published var shareTimeout: TimeInterval = 3600
    @Published var selectedRoomId: String?

    private let service = LiveLocationService.shared
    private var refreshTimer: Timer?

    // MARK: - 查询

    /// 加载指定房间的活跃位置共享
    func loadActiveShares(roomId: String) {
        activeShares = service.activeShares(in: roomId).sorted {
            $0.lastUpdate > $1.lastUpdate
        }
    }

    /// 选择位置共享并加载历史
    func selectShare(_ share: LiveLocationShare) {
        selectedShare = share
        locationHistory = service.locationHistory(for: share.beaconId)
        if let last = share.currentLocation as GeoCoordinate? {
            withAnimation {
                currentRegion = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
        }
    }

    // MARK: - 操作

    /// 开始位置共享
    func startSharing(roomId: String) async {
        isSharing = true
        errorMessage = nil
        defer { isSharing = false }

        let coordinate = GeoCoordinate(
            latitude: currentRegion.center.latitude,
            longitude: currentRegion.center.longitude
        )

        do {
            let share = try await service.startLiveLocationShare(
                coordinate: coordinate,
                roomId: roomId,
                timeout: shareTimeout,
                description: shareDescription.isEmpty ? nil : shareDescription
            )
            sharingBeaconId = share.beaconId
            activeShares.append(share)
            shareDescription = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 停止位置共享
    func stopSharing(beaconId: String) async {
        errorMessage = nil

        do {
            try await service.stopLiveLocationShare(beaconId: beaconId)
            activeShares.removeAll { $0.beaconId == beaconId }
            if sharingBeaconId == beaconId {
                sharingBeaconId = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 发送新位置
    func sendCurrentLocation() async {
        guard let bid = sharingBeaconId else { return }

        let coordinate = GeoCoordinate(
            latitude: currentRegion.center.latitude,
            longitude: currentRegion.center.longitude
        )

        do {
            try await service.sendLiveLocation(coordinate: coordinate, beaconId: bid)
            if let share = activeShares.first(where: { $0.beaconId == bid }) {
                selectShare(share)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 定时器

    func startAutoRefresh(roomId: String) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadActiveShares(roomId: roomId)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - 地图

    func focusOnCoordinate(_ coordinate: GeoCoordinate) {
        withAnimation {
            currentRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
    }

    let timeoutOptions: [(TimeInterval, String)] = [
        (900, "15 分钟"),
        (1800, "30 分钟"),
        (3600, "1 小时"),
        (14400, "4 小时"),
        (28800, "8 小时"),
    ]

    // MARK: - 清理

    func cleanup() {
        stopAutoRefresh()
    }

    private func withAnimation(_ block: @escaping () -> Void) {
        SwiftUI.withAnimation(.easeInOut(duration: 0.3), block)
    }
}