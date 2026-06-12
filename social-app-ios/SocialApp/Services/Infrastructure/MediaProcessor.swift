import Foundation

// MARK: - MediaType
enum MediaType: String, Sendable, CaseIterable {
    case image
    case video
    case audio
    case other
}

// MARK: - MediaMetadata
struct MediaMetadata: Sendable {
    let url: String
    let type: MediaType
    let mimeType: String?
    let fileSize: Int64?
    let width: Int?
    let height: Int?
    let durationSeconds: Double?
    let thumbnailUrl: String?
    let uploadedAt: Date

    var isImage: Bool { type == .image }
    var isVideo: Bool { type == .video }
    var isAudio: Bool { type == .audio }
}

// MARK: - MediaUploadConfig
struct MediaUploadConfig: Sendable {
    static let maxImageSize: Int64 = 20 * 1024 * 1024       // 20MB
    static let maxVideoSize: Int64 = 100 * 1024 * 1024      // 100MB
    static let maxAudioSize: Int64 = 50 * 1024 * 1024       // 50MB
    static let maxCount = 9                                  // 单次最多 9 个附件
}

// MARK: - MediaProcessor
/// 多媒体校验与处理，对应 Rust 的 MediaProcessor（3 方法）

enum MediaProcessor {
    /// 校验文件格式和大小
    static func validate(fileURL: URL, type: MediaType) throws {
        let ext = fileURL.pathExtension.lowercased()
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? Int64) ?? 0

        let maxSize: Int64
        let allowedFormats: Set<String>

        switch type {
        case .image:
            maxSize = MediaUploadConfig.maxImageSize
            allowedFormats = ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp", "svg"]
        case .video:
            maxSize = MediaUploadConfig.maxVideoSize
            allowedFormats = ["mp4", "mov", "avi", "mkv", "webm"]
        case .audio:
            maxSize = MediaUploadConfig.maxAudioSize
            allowedFormats = ["mp3", "aac", "ogg", "wav", "flac", "m4a"]
        case .other:
            maxSize = MediaUploadConfig.maxImageSize
            allowedFormats = []
        }

        if !allowedFormats.isEmpty && !allowedFormats.contains(ext) {
            throw SocialFeedError.invalidUrl("不支持的\(type.rawValue)格式: \(ext)")
        }

        guard fileSize <= maxSize else {
            throw SocialFeedError.invalidJson(
                "\(type.rawValue)大小超过限制: \(fileSize) bytes (最大 \(maxSize))"
            )
        }
    }

    /// 从 URL 列表提取媒体类型和元信息
    static func extractMedia(from urls: [URL]) -> [MediaMetadata] {
        urls.compactMap { url in
            let ext = url.pathExtension.lowercased()
            let type: MediaType = {
                if ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp", "svg"].contains(ext) { return .image }
                if ["mp4", "mov", "avi", "mkv", "webm"].contains(ext) { return .video }
                if ["mp3", "aac", "ogg", "wav", "flac", "m4a"].contains(ext) { return .audio }
                return .other
            }()
            return MediaMetadata(
                url: url.absoluteString,
                type: type,
                mimeType: mimeType(for: ext),
                fileSize: (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64),
                width: nil, height: nil, durationSeconds: nil,
                thumbnailUrl: nil,
                uploadedAt: Date()
            )
        }
    }

    /// 生成多媒体摘要
    static func generateSummary(from media: [MediaMetadata]) -> String {
        let images = media.filter { $0.isImage }.count
        let videos = media.filter { $0.isVideo }.count
        let audios = media.filter { $0.isAudio }.count
        var parts: [String] = []
        if images > 0 { parts.append("\(images) 张图片") }
        if videos > 0 { parts.append("\(videos) 个视频") }
        if audios > 0 { parts.append("\(audios) 段音频") }
        return parts.isEmpty ? "无多媒体" : parts.joined(separator: ", ")
    }

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "aac": return "audio/aac"
        default: return "application/octet-stream"
        }
    }
}