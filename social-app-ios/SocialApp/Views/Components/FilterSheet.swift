import SwiftUI

// MARK: - FilterSheet
/// 高级动态过滤面板（时间范围 / 作者 / 最少点赞 / 最少评论 / 仅图片）。

struct FilterSheet: View {
    @Binding var isPresented: Bool
    @State var filter: SearchFilter

    var onApply: (SearchFilter) -> Void

    @State private var selectedTimeRange: TimeRangeOption = .all
    @State private var authorId: String = ""
    @State private var minLikes: String = ""
    @State private var minComments: String = ""
    @State private var hasImagesOnly: Bool = false

    var body: some View {
        NavigationView {
            Form {
                // 时间范围
                Section("时间范围") {
                    Picker("时间范围", selection: $selectedTimeRange) {
                        ForEach(TimeRangeOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // 内容过滤
                Section("内容过滤") {
                    HStack {
                        Text("作者 ID")
                        Spacer()
                        TextField("可选", text: $authorId)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("最少点赞")
                        Spacer()
                        TextField("0", text: $minLikes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("最少评论")
                        Spacer()
                        TextField("0", text: $minComments)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }

                    Toggle("仅含图片的动态", isOn: $hasImagesOnly)
                }

                // 操作
                Section {
                    Button("应用过滤") {
                        applyFilter()
                    }
                    .frame(maxWidth: .infinity)
                    .font(.body.bold())

                    Button("清除过滤", role: .destructive) {
                        clearFilter()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("高级过滤")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("应用") { applyFilter() }
                }
            }
            .onAppear { syncFromFilter() }
        }
    }

    // MARK: - Actions

    private func applyFilter() {
        let newFilter = SearchFilter(
            keyword: filter.keyword,
            authorId: authorId.isEmpty ? nil : authorId,
            timeRange: selectedTimeRange.timeRange,
            minLikes: Int(minLikes) ?? 0,
            minComments: Int(minComments) ?? 0,
            hasImages: hasImagesOnly
        )
        onApply(newFilter)
        isPresented = false
    }

    private func clearFilter() {
        authorId = ""
        minLikes = ""
        minComments = ""
        hasImagesOnly = false
        selectedTimeRange = .all
        let cleared = SearchFilter(keyword: "", authorId: nil, timeRange: nil, minLikes: 0, minComments: 0, hasImages: false)
        onApply(cleared)
        isPresented = false
    }

    private func syncFromFilter() {
        authorId = filter.authorId ?? ""
        minLikes = filter.minLikes > 0 ? "\(filter.minLikes)" : ""
        minComments = filter.minComments > 0 ? "\(filter.minComments)" : ""
        hasImagesOnly = filter.hasImages
        if let range = filter.timeRange {
            selectedTimeRange = .fromRange(range)
        } else {
            selectedTimeRange = .all
        }
    }
}

// MARK: - TimeRangeOption

private enum TimeRangeOption: String, CaseIterable, Identifiable {
    case all
    case last24h
    case last7d
    case last30d
    case last90d

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "不限"
        case .last24h: return "最近 24 小时"
        case .last7d: return "最近 7 天"
        case .last30d: return "最近 30 天"
        case .last90d: return "最近 90 天"
        }
    }

    var timeRange: SearchFilter.TimeRange {
        let now = Date()
        switch self {
        case .all: return SearchFilter.TimeRange(start: .distantPast, end: now)
        case .last24h: return SearchFilter.TimeRange(start: now.addingTimeInterval(-86400), end: now)
        case .last7d: return SearchFilter.TimeRange(start: now.addingTimeInterval(-604800), end: now)
        case .last30d: return SearchFilter.TimeRange(start: now.addingTimeInterval(-2592000), end: now)
        case .last90d: return SearchFilter.TimeRange(start: now.addingTimeInterval(-7776000), end: now)
        }
    }

    static func fromRange(_ range: SearchFilter.TimeRange) -> TimeRangeOption {
        let duration = range.end.timeIntervalSince(range.start)
        switch abs(duration - 86400) {
        case let d where d < 60: return .last24h
        default: break
        }
        switch abs(duration - 604800) {
        case let d where d < 3600: return .last7d
        default: break
        }
        switch abs(duration - 2592000) {
        case let d where d < 86400: return .last30d
        default: break
        }
        switch abs(duration - 7776000) {
        case let d where d < 86400: return .last90d
        default: break
        }
        return .all
    }
}