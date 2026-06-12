import Foundation

// MARK: - ImageUtils
// MARK: - 待接入
/// 图片提取工具，对应 Rust 的 images.rs（3 函数）

enum ImageUtils {
    /// 从 Markdown 文本中提取 ![](url) 格式的图片
    static func extractMarkdownImages(from text: String) -> [String] {
        let pattern = #"!\[.*?\]\((.*?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            return nsText.substring(with: match.range(at: 1))
        }
    }

    /// 从 HTML 文本中提取 <img src="url"> 格式的图片
    static func extractHTMLImages(from html: String) -> [String] {
        let pattern = #"<img[^>]+src=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsText = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            return nsText.substring(with: match.range(at: 1))
        }
    }

    /// 从文本中提取所有图片 URL（Markdown + HTML）
    static func extractAllImages(from text: String) -> [String] {
        let md = extractMarkdownImages(from: text)
        let html = extractHTMLImages(from: text)
        // 去重保持顺序
        var seen = Set<String>()
        var result: [String] = []
        for url in md + html {
            if !seen.contains(url) {
                seen.insert(url)
                result.append(url)
            }
        }
        return result
    }
}