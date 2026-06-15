//! [从 Markdown/HTML 提取图片 URL，供 fetch_room_moments 使用]

/// 从文本中提取 Markdown 格式的图片 URL
/// 匹配格式：![alt text](url)
pub fn extract_markdown_images(text: &str) -> Vec<String> {
    let mut images = Vec::new();
    let mut current_pos = 0;

    while let Some(start) = text[current_pos..].find("![") {
        let start = current_pos + start;
        if let Some(close_bracket) = text[start..].find("](") {
            let close_bracket = start + close_bracket;
            if let Some(close_paren) = text[close_bracket + 2..].find(")") {
                let url_start = close_bracket + 2;
                let url_end = url_start + close_paren;
                let url = &text[url_start..url_end];

                if url.starts_with("http://") || url.starts_with("https://") || url.starts_with("mxc://") {
                    images.push(url.to_string());
                }
                current_pos = url_end + 1;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    images
}

/// 从 HTML 中提取图片 URL
/// 匹配格式：<img ... src="url" ...>
pub fn extract_html_images(html: &str) -> Vec<String> {
    let mut images = Vec::new();
    let mut current_pos = 0;

    while let Some(start) = html[current_pos..].find("<img") {
        let start = current_pos + start;
        if let Some(end) = html[start..].find(">") {
            let tag = &html[start..start + end + 1];

            if let Some(src_pos) = tag.find("src=\"") {
                let src_start = src_pos + 5;
                if let Some(src_end) = tag[src_start..].find("\"") {
                    let url = &tag[src_start..src_start + src_end];

                    if url.starts_with("http://") || url.starts_with("https://") || url.starts_with("mxc://") {
                        images.push(url.to_string());
                    }
                }
            }

            current_pos = start + end + 1;
        } else {
            break;
        }
    }

    images
}

/// 从动态文本中提取所有图片 URL
/// 支持 Markdown 和 HTML 两种格式
pub fn extract_all_images(text: &str) -> Vec<String> {
    let mut images = Vec::new();
    images.extend(extract_markdown_images(text));
    images.extend(extract_html_images(text));
    images.sort();
    images.dedup();
    images
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_markdown_images_single() {
        let text = "Check out ![landscape](https://example.com/image.jpg)";
        let images = extract_markdown_images(text);
        assert_eq!(images.len(), 1);
        assert_eq!(images[0], "https://example.com/image.jpg");
    }

    #[test]
    fn test_extract_markdown_images_multiple() {
        let text = "![img1](https://example.com/1.jpg) and ![img2](https://example.com/2.jpg)";
        let images = extract_markdown_images(text);
        assert_eq!(images.len(), 2);
    }

    #[test]
    fn test_extract_markdown_images_mxc() {
        let text = "Avatar: ![avatar](mxc://example.com/abc123)";
        let images = extract_markdown_images(text);
        assert_eq!(images.len(), 1);
        assert!(images[0].starts_with("mxc://"));
    }

    #[test]
    fn test_extract_markdown_images_empty() {
        let text = "No images here!";
        let images = extract_markdown_images(text);
        assert_eq!(images.len(), 0);
    }

    #[test]
    fn test_extract_markdown_images_invalid_format() {
        let text = "Invalid: ![alt](not_a_url) and ![alt](ftp://bad.com)";
        let images = extract_markdown_images(text);
        assert_eq!(images.len(), 0);  // ftp:// not supported
    }

    #[test]
    fn test_extract_html_images_single() {
        let html = r#"<img alt="landscape" src="https://example.com/image.jpg" width="100">"#;
        let images = extract_html_images(html);
        assert_eq!(images.len(), 1);
        assert_eq!(images[0], "https://example.com/image.jpg");
    }

    #[test]
    fn test_extract_html_images_multiple() {
        let html = r#"<img src="https://example.com/1.jpg"/><img src="https://example.com/2.jpg"/>"#;
        let images = extract_html_images(html);
        assert_eq!(images.len(), 2);
    }

    #[test]
    fn test_extract_html_images_mxc() {
        let html = r#"<img src="mxc://example.com/xyz789" />"#;
        let images = extract_html_images(html);
        assert_eq!(images.len(), 1);
        assert!(images[0].starts_with("mxc://"));
    }

    #[test]
    fn test_extract_html_images_empty() {
        let html = "<p>No images</p>";
        let images = extract_html_images(html);
        assert_eq!(images.len(), 0);
    }

    #[test]
    fn test_extract_all_images_mixed() {
        let text = r#"Check ![md](https://example.com/md.jpg) and <img src="https://example.com/html.jpg"/>"#;
        let images = extract_all_images(text);
        assert_eq!(images.len(), 2);
        assert!(images.contains(&"https://example.com/md.jpg".to_string()));
        assert!(images.contains(&"https://example.com/html.jpg".to_string()));
    }

    #[test]
    fn test_extract_all_images_dedup() {
        let text = r#"![img](https://example.com/same.jpg) and ![img2](https://example.com/same.jpg)"#;
        let images = extract_all_images(text);
        assert_eq!(images.len(), 1);  // Should be deduped
    }

    #[test]
    fn test_extract_all_images_empty() {
        let images = extract_all_images("");
        assert_eq!(images.len(), 0);
    }

    #[test]
    fn test_extract_all_images_http() {
        let text = "![pic](http://example.com/pic.jpg)";
        let images = extract_all_images(text);
        assert_eq!(images.len(), 1);
        assert!(images[0].starts_with("http://"));
    }
}

