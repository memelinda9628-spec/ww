import SwiftUI

struct FeedView: View {
    @State private var vm = FeedViewModel()

    var body: some View {
        NavigationStack {
            List(vm.moments) { moment in
                MomentCard(
                    moment: moment,
                    onLike: { vm.toggleLike(moment) },
                    onComment: { vm.commentButtonTapped(moment) },
                    onForward: { vm.forwardButtonTapped(moment) }
                )
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .refreshable { await vm.refreshTimeline() }
            .navigationTitle("信息流")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.showPostSheet = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $vm.showPostSheet) {
                PostSheet { text in await vm.postMoment(text: text, imageURLs: []) }
            }
            .sheet(isPresented: $vm.showCommentSheet) {
                CommentSheet { text in await vm.comment(text: text) }
            }
            .sheet(isPresented: $vm.showForwardSheet) {
                ForwardSheet { text in await vm.forward(quoteText: text) }
            }
        }
        .task { await vm.fetchTimeline() }
    }
}