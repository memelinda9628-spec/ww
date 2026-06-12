import SwiftUI

// MARK: - AsyncImageGrid
/// 独立图片网格组件，支持 1/2/3 列自适应布局，从 MomentCard 中抽出复用。

struct AsyncImageGrid: View {
    let urls: [URL]
    var onImageTap: ((URL, Int) -> Void)? = nil

    var body: some View {
        if !urls.isEmpty {
            gridLayout(for: urls)
        }
    }

    @ViewBuilder
    private func gridLayout(for urls: [URL]) -> some View {
        switch urls.count {
        case 1:
            singleImage(urls[0])
        case 2:
            twoColumnGrid(urls)
        case 3:
            threeColumnGrid(urls)
        case 4:
            twoByTwoGrid(urls)
        default:
            multiRowGrid(urls)
        }
    }

    // MARK: - 单图

    private func singleImage(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { onImageTap?(url, 0) }
            case .failure:
                placeholderView
            case .empty:
                ProgressView().frame(height: 200)
            @unknown default:
                placeholderView
            }
        }
    }

    // MARK: - 两列

    private func twoColumnGrid(_ urls: [URL]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                gridCell(url: url, idx: idx, height: 200)
            }
        }
    }

    // MARK: - 三列

    private func threeColumnGrid(_ urls: [URL]) -> some View {
        HStack(spacing: 4) {
            gridCell(url: urls[0], idx: 0, height: 240)
            VStack(spacing: 4) {
                gridCell(url: urls[1], idx: 1, height: 118)
                gridCell(url: urls[2], idx: 2, height: 118)
            }
        }
    }

    // MARK: - 四图

    private func twoByTwoGrid(_ urls: [URL]) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                gridCell(url: urls[0], idx: 0, height: 150)
                gridCell(url: urls[1], idx: 1, height: 150)
            }
            HStack(spacing: 4) {
                gridCell(url: urls[2], idx: 2, height: 150)
                gridCell(url: urls[3], idx: 3, height: 150)
            }
        }
    }

    // MARK: - 多行（5+）

    private func multiRowGrid(_ urls: [URL]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                gridCell(url: url, idx: idx, height: 120)
            }
        }
    }

    // MARK: - 通用网格单元

    private func gridCell(url: URL, idx: Int, height: CGFloat) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: height, maxHeight: height)
                    .clipped()
                    .onTapGesture { onImageTap?(url, idx) }
            case .failure:
                placeholderCell(height: height)
            case .empty:
                ProgressView().frame(height: height)
            @unknown default:
                placeholderCell(height: height)
            }
        }
    }

    private func placeholderCell(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(height: height)
            .overlay(
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundColor(.secondary)
            )
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(height: 200)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                    Text("图片加载失败")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            Text("单图").font(.headline)
            AsyncImageGrid(urls: [
                URL(string: "https://picsum.photos/400/300")!
            ])

            Text("两图").font(.headline)
            AsyncImageGrid(urls: [
                URL(string: "https://picsum.photos/200/200")!,
                URL(string: "https://picsum.photos/201/200")!,
            ])

            Text("三图").font(.headline)
            AsyncImageGrid(urls: [
                URL(string: "https://picsum.photos/200/300")!,
                URL(string: "https://picsum.photos/201/150")!,
                URL(string: "https://picsum.photos/202/150")!,
            ])

            Text("四图").font(.headline)
            AsyncImageGrid(urls: [
                URL(string: "https://picsum.photos/200/200")!,
                URL(string: "https://picsum.photos/201/200")!,
                URL(string: "https://picsum.photos/202/200")!,
                URL(string: "https://picsum.photos/203/200")!,
            ])

            Text("六图").font(.headline)
            AsyncImageGrid(urls: [
                URL(string: "https://picsum.photos/100/100")!,
                URL(string: "https://picsum.photos/101/100")!,
                URL(string: "https://picsum.photos/102/100")!,
                URL(string: "https://picsum.photos/103/100")!,
                URL(string: "https://picsum.photos/104/100")!,
                URL(string: "https://picsum.photos/105/100")!,
            ])
        }
        .padding()
    }
}