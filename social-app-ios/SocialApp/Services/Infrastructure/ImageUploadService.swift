import Foundation
import ImageIO

// MARK: - ImageUploadService
/// 封装 SDK 图片上传流程：选图 → 压缩 → 上传 → 获取 mxc URI → 传入 post_moment

final class ImageUploadService: @unchecked Sendable {
    /// FFI Client
    private var ffiClient: Client? { KeychainManager.shared.ffiClient }

    /// 最大图片大小 (20MB)
    static let maxImageSize: Int64 = 20 * 1024 * 1024

    /// 支持的图片格式
    static let supportedFormats: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp"]

    /// 压缩质量 (0.0-1.0)
    var compressionQuality: CGFloat = 0.85

    /// 最大尺寸（宽/高限制，0 表示不限制）
    var maxDimension: CGFloat = 2048

    /// 上传单张图片并返回 mxc URI（含压缩流程）
    /// - Parameter localURL: 本地文件 URL
    /// - Returns: mxc URI 字符串 (如 mxc://matrix.example.com/ABCDEFG)
    func uploadImage(localURL: URL) async throws -> String {
        // 1. 校验原始文件格式
        let ext = localURL.pathExtension.lowercased()
        guard Self.supportedFormats.contains(ext) else {
            throw SocialFeedError.invalidUrl("不支持的图片格式: \(ext)")
        }

        guard let client = ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }

        // 2. 压缩图片（若尺寸超限则等比缩放并以 JPEG 重编码，否则返回原 URL）
        let compressedURL = try compressImage(at: localURL)

        // 3. 读取压缩后的图片数据
        let data = try Data(contentsOf: compressedURL)

        // 4. 校验压缩后的数据大小
        guard data.count <= Self.maxImageSize else {
            throw SocialFeedError.invalidJson("图片大小超过限制: \(data.count) bytes (最大 \(Self.maxImageSize))")
        }

        // 5. 根据压缩后文件的实际扩展名推导 MIME 类型
        let actualExt = compressedURL.pathExtension.lowercased()
        let mimeType: String = {
            switch actualExt {
            case "jpg", "jpeg": return "image/jpeg"
            case "png": return "image/png"
            case "gif": return "image/gif"
            case "webp": return "image/webp"
            case "heic": return "image/heic"
            case "bmp": return "image/bmp"
            default: return "application/octet-stream"
            }
        }()

        // 6. 调用 FFI uploadMedia 上传
        let mxcUri = try await client.uploadMedia(mimeType: mimeType, data: [UInt8](data))
        return mxcUri
    }

    /// 批量上传图片
    func uploadImages(localURLs: [URL]) async throws -> [String] {
        guard localURLs.count <= 9 else {
            throw SocialFeedError.quotaExceeded
        }
        var results: [String] = []
        for url in localURLs {
            let mxc = try await uploadImage(localURL: url)
            results.append(mxc)
        }
        return results
    }

    /// 压缩图片：若图片尺寸超过 maxDimension，按比例缩放后以 JPEG 重编码
    /// - Parameter url: 原始图片本地 URL
    /// - Returns: 压缩后图片的临时文件 URL（若无需压缩则返回原 URL）
    func compressImage(at url: URL) throws -> URL {
        // maxDimension 为 0 表示不限制尺寸，直接返回原 URL
        guard maxDimension > 0 else { return url }

        // 创建 ImageIO 源
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return url // 无法读取源文件，跳过压缩
        }

        // 读取原始尺寸
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return url
        }

        // 尺寸已在限制内，无需压缩
        if width <= maxDimension && height <= maxDimension {
            return url
        }

        // 使用 ImageIO 缩略图 API 一步完成等比缩放（CGImageSourceCreateThumbnailAtIndex 自动保持宽高比）
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return url
        }

        // 写入临时 JPEG 文件（以 compressionQuality 控制质量）
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return url
        }

        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return url
        }

        return tempURL
    }
}