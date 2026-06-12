import SwiftUI

struct FollowingListView: View {
    let userIds: [String]

    var body: some View {
        List(userIds, id: \.self) { userId in
            HStack(spacing: 12) {
                AvatarView(url: nil, name: userId, size: 40)
                VStack(alignment: .leading) {
                    Text(userId).font(.body)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("关注")
    }
}