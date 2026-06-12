import SwiftUI
import PhotosUI

// MARK: - MediaPicker
/// 多媒体选择器组件（PHPickerViewController 的 SwiftUI 桥接）。
/// 选择照片/视频后返回 Data + mimeType，供 MessageService.sendAttachment 使用。

struct MediaPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let selectionLimit: Int
    let onSelect: (([MediaAttachment]) -> Void)?

    init(isPresented: Binding<Bool>,
         selectionLimit: Int = 1,
         onSelect: (([MediaAttachment]) -> Void)? = nil) {
        self._isPresented = isPresented
        self.selectionLimit = max(1, min(selectionLimit, 10))
        self.onSelect = onSelect
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = selectionLimit
        config.filter = .any(of: [.images, .videos, .livePhotos])

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MediaPicker

        init(parent: MediaPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false

            guard let onSelect = parent.onSelect else { return }

            var attachments: [MediaAttachment] = []
            let group = DispatchGroup()

            for result in results {
                group.enter()

                let itemProvider = result.itemProvider

                // 确定 mimeType
                var mimeType = "application/octet-stream"
                if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    mimeType = "image/jpeg"
                } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    mimeType = "video/mp4"
                }

                // 尝试获取文件名
                var filename = "attachment"
                if let suggestedName = result.itemProvider.suggestedName {
                    filename = suggestedName
                }

                itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, error in
                    defer { group.leave() }

                    guard let url = url, error == nil else { return }

                    if let data = try? Data(contentsOf: url) {
                        let attachment = MediaAttachment(
                            id: UUID().uuidString,
                            filename: filename,
                            mimeType: mimeType,
                            data: data
                        )
                        attachments.append(attachment)
                    }
                }
            }

            group.notify(queue: .main) {
                onSelect(attachments)
            }
        }
    }
}

// MARK: - MediaAttachment

struct MediaAttachment: Identifiable, Sendable {
    let id: String
    let filename: String
    let mimeType: String
    let data: Data
}

// MARK: - MediaPickerSheet Modifier

struct MediaPickerSheet: ViewModifier {
    @Binding var isPresented: Bool
    let onSelect: ([MediaAttachment]) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                MediaPicker(isPresented: $isPresented, selectionLimit: 5, onSelect: onSelect)
            }
    }
}

extension View {
    func mediaPicker(isPresented: Binding<Bool>, onSelect: @escaping ([MediaAttachment]) -> Void) -> some View {
        modifier(MediaPickerSheet(isPresented: isPresented, onSelect: onSelect))
    }
}