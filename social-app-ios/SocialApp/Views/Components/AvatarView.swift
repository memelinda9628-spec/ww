import SwiftUI

// MARK: - AvatarView
/// 通用头像组件，支持图片 URL 和纯文字初始头像

struct AvatarView: View {
    let name: String
    let url: URL?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        fallbackView
                    @unknown default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(avatarColor)
            Text(initial)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(.white)
        }
    }

    private var initial: String {
        String(name.prefix(1))
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .mint]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}