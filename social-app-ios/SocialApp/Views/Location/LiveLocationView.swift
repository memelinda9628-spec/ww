import SwiftUI
import MapKit

// MARK: - LiveLocationView
/// 实时位置共享界面，对应 LiveLocationService。
/// 展示位置共享列表和地图视图。

struct LiveLocationView: View {
    @StateObject private var viewModel = LiveLocationViewModel()
    @State private var showStartSheet: Bool = false
    @State private var selectedTab: Tab = .active

    enum Tab: String, CaseIterable {
        case active = "共享中"
        case history = "历史"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab 切换
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // 内容
                switch selectedTab {
                case .active:
                    activeSharesView
                case .history:
                    historyView
                }
            }
            .navigationTitle("实时位置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isSharing {
                        Button("停止共享") {
                            if let bid = viewModel.sharingBeaconId {
                                Task { await viewModel.stopSharing(beaconId: bid) }
                            }
                        }
                    } else {
                        Button { showStartSheet = true } label: {
                            Image(systemName: "location.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showStartSheet) {
                startShareSheet
            }
            .onAppear {
                viewModel.startAutoRefresh(roomId: "")
            }
            .onDisappear {
                viewModel.cleanup()
            }
        }
    }

    // MARK: - 活跃共享

    private var activeSharesView: some View {
        VStack(spacing: 0) {
            if viewModel.activeShares.isEmpty {
                emptyActiveState
            } else {
                // 地图预览
                Map(coordinateRegion: $viewModel.currentRegion, annotationItems: shareAnnotations) { item in
                    MapAnnotation(coordinate: item.coordinate) {
                        VStack(spacing: 2) {
                            Image(systemName: "location.circle.fill")
                                .font(.title2)
                                .foregroundColor(item.isSelf ? .blue : .red)
                            Text(item.label)
                                .font(.system(size: 8))
                                .padding(2)
                                .background(.regularMaterial)
                                .cornerRadius(4)
                        }
                    }
                }
                .frame(height: 220)
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom, 8)

                // 分享列表
                List {
                    ForEach(viewModel.activeShares) { share in
                        shareRow(share)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func shareRow(_ share: LiveLocationShare) -> some View {
        Button {
            viewModel.selectShare(share)
        } label: {
            HStack(spacing: 12) {
                AvatarView(url: nil, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(share.userId)
                        .font(.subheadline.bold())
                    HStack(spacing: 8) {
                        Label(share.formattedRemaining, systemImage: "timer")
                            .font(.caption)
                        if let desc = share.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .foregroundColor(.primary)
    }

    // MARK: - 历史记录

    private var historyView: some View {
        Group {
            if let share = viewModel.selectedShare {
                VStack(spacing: 0) {
                    // 地图历史轨迹
                    Map(coordinateRegion: $viewModel.currentRegion, annotationItems: historyAnnotations) { item in
                        MapAnnotation(coordinate: item.coordinate) {
                            Circle()
                                .fill(Color.blue.opacity(0.6))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .frame(height: 250)
                    .cornerRadius(12)
                    .padding()

                    // 历史位置列表
                    List {
                        Section("位置历史 (\(viewModel.locationHistory.count))") {
                            ForEach(viewModel.locationHistory.indices, id: \.self) { idx in
                                let content = viewModel.locationHistory[idx]
                                HStack {
                                    Text("\(content.geoUri)")
                                        .font(.caption.monospaced())
                                    Spacer()
                                    if let ts = content.timestamp {
                                        Text(ts, style: .time)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("选择一个位置共享查看历史轨迹")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - 开始共享

    private var startShareSheet: some View {
        NavigationView {
            Form {
                Section("共享设置") {
                    HStack {
                        Text("描述")
                        TextField("可选描述", text: $viewModel.shareDescription)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("超时时长", selection: $viewModel.shareTimeout) {
                        ForEach(viewModel.timeoutOptions, id: \.0) { (interval, label) in
                            Text(label).tag(interval)
                        }
                    }
                }

                Section {
                    Button {
                        Task {
                            await viewModel.startSharing(roomId: "")
                            showStartSheet = false
                        }
                    } label: {
                        Label("开始共享位置", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.isSharing)
                }
            }
            .navigationTitle("共享位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { showStartSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - 空状态

    private var emptyActiveState: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("当前没有活跃的位置共享")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button {
                showStartSheet = true
            } label: {
                Label("开始共享位置", systemImage: "location.fill.viewfinder")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Map Annotations

    private var shareAnnotations: [ShareAnnotation] {
        viewModel.activeShares.map { share in
            let coord = share.currentLocation as? GeoCoordinate
            ?? GeoCoordinate(latitude: 0, longitude: 0)
            return ShareAnnotation(
                id: share.beaconId,
                coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude),
                label: share.userId,
                isSelf: viewModel.sharingBeaconId == share.beaconId
            )
        }
    }

    private var historyAnnotations: [HistoryAnnotation] {
        viewModel.locationHistory.map { content in
            let uri = content.geoUri.replacingOccurrences(of: "geo:", with: "")
            let parts = uri.split(separator: ",")
            let lat = Double(parts.first ?? "0") ?? 0
            let lon = Double(parts.last ?? "0") ?? 0
            return HistoryAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }
    }
}

// MARK: - Annotation Types

private struct ShareAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let label: String
    let isSelf: Bool
}

private struct HistoryAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}