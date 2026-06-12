import SwiftUI

struct MomentCard: View {
    let moment: Moment
    var onLike: () -> Void = {}
    var onComment: () -> Void = {}
    var onForward: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                AvatarView(url: moment.authorAvatar, name: moment.authorName, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.authorName).font(.subheadline.weight(.semibold))
                    Text(moment.createdAt, style: .relative).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }

            // Text
            Text(moment.text)
                .font(.body)
                .lineLimit(6)

            // Images
            AsyncImageGrid(urls: moment.images)

            // Actions
            HStack(spacing: 24) {
                actionButton(icon: "heart", count: moment.likeCount, action: onLike)
                actionButton(icon: "bubble.right", count: moment.commentCount, action: onComment)
                actionButton(icon: "arrowshape.turn.up.right", count: nil, action: onForward)
                Spacer()
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func actionButton(icon: String, count: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                if let c = count, c > 0 {
                    Text("\(c)")
                }
            }
        }
        .buttonStyle(.plain)
    }
}