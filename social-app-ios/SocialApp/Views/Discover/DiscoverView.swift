import SwiftUI

struct DiscoverView: View {
    @State private var vm = DiscoverViewModel()
    @State private var showSortMenu = false

    var body: some View {
        NavigationStack {
            List(vm.sortedResults) { moment in
                MomentCard(moment: moment)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .searchable(text: $vm.keyword, prompt: "搜索动态...")
            .navigationTitle("发现")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("排序", selection: $vm.sortOrder) {
                            Label("最新", systemImage: "clock").tag(SortOrder.timeDesc)
                            Label("最早", systemImage: "clock.arrow.circlepath").tag(SortOrder.timeAsc)
                            Label("最多赞", systemImage: "heart").tag(SortOrder.likesDesc)
                            Label("最多评", systemImage: "message").tag(SortOrder.commentsDesc)
                            Label("最热", systemImage: "flame").tag(SortOrder.hotDesc)
                        }
                    } label: {
                        Label("排序", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
    }
}