//! 多媒体处理模块 [MediaMetadata / MediaUploadConfig，供 App 层在上传前验证格式/大小]
//!
//! 支持图片上传、缩放、格式转换和媒体服务器集成。

use serde::{Deserialize, Serialize};

/// 媒体类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MediaType {
    /// 图片
    Image,
    /// 视频
    Video,
    /// 音频
    Audio,
    /// 其他
    Other,
}

impl MediaType {
    /// 从 MIME 类型判断媒体类型
    pub fn from_mime(mime: &str) -> Self {
        match mime {
            m if m.starts_with("image/") => MediaType::Image,
            m if m.starts_with("video/") => MediaType::Video,
            m if m.starts_with("audio/") => MediaType::Audio,
            _ => MediaType::Other,
        }
    }

    /// 获取媒体类型对应的 MIME 前缀
    pub fn mime_prefix(&self) -> &'static str {
        match self {
            MediaType::Image => "image/",
            MediaType::Video => "video/",
            MediaType::Audio => "audio/",
            MediaType::Other => "application/",
        }
    }
}

/// 媒体元数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaMetadata {
    /// 媒体 URL（mxc:// 格式）
    pub url: String,
    /// 媒体类型
    pub media_type: MediaType,
    /// MIME 类型
    pub mime_type: String,
    /// 大小（字节）
    pub size: u64,
    /// 原始宽度（仅图片/视频）
    pub width: Option<u32>,
    /// 原始高度（仅图片/视频）
    pub height: Option<u32>,
    /// 时长（仅视频/音频，秒）
    pub duration_secs: Option<u32>,
    /// 缩略图 URL
    pub thumbnail_url: Option<String>,
    /// 上传时间戳
    pub uploaded_at: i64,
}

impl MediaMetadata {
    /// 创建新的媒体元数据
    pub fn new(url: String, mime_type: String, size: u64) -> Self {
        Self {
            url,
            media_type: MediaType::from_mime(&mime_type),
            mime_type,
            size,
            width: None,
            height: None,
            duration_secs: None,
            thumbnail_url: None,
            uploaded_at: chrono::Utc::now().timestamp(),
        }
    }

    /// 验证媒体大小限制
    pub fn validate_size(&self, max_size_bytes: u64) -> Result<(), String> {
        if self.size > max_size_bytes {
            Err(format!(
                "媒体大小 {} 字节超过限制 {} 字节",
                self.size, max_size_bytes
            ))
        } else {
            Ok(())
        }
    }

    /// 检查是否为支持的格式
    pub fn is_supported_format(&self) -> bool {
        matches!(
            self.media_type,
            MediaType::Image | MediaType::Video | MediaType::Audio
        )
    }

    /// 生成缩略图 URL（使用 Matrix 媒体服务器缩放）
    pub fn build_thumbnail_url(&self, width: u32, height: u32) -> Option<String> {
        if self.media_type == MediaType::Image {
            // matrix 缩略图 API 格式：/_matrix/media/r0/thumbnail/{serverName}/{mediaId}?width=X&height=Y
            if let Some(path) = self.url.strip_prefix("mxc://") {
                let parts: Vec<&str> = path.split('/').collect();
                if parts.len() == 2 {
                    return Some(format!(
                        "mxc://{}/{}?thumbnail&width={}&height={}",
                        parts[0], parts[1], width, height
                    ));
                }
            }
        }
        None
    }
}

/// 媒体上传配置
#[derive(Debug, Clone)]
pub struct MediaUploadConfig {
    /// 最大图片大小（字节）
    pub max_image_size: u64,
    /// 最大视频大小（字节）
    pub max_video_size: u64,
    /// 最大音频大小（字节）
    pub max_audio_size: u64,
    /// 支持的图片格式
    pub supported_image_formats: Vec<String>,
    /// 支持的视频格式
    pub supported_video_formats: Vec<String>,
    /// 支持的音频格式
    pub supported_audio_formats: Vec<String>,
    /// 是否启用缩略图生成
    pub generate_thumbnails: bool,
    /// 缩略图宽度
    pub thumbnail_width: u32,
    /// 缩略图高度
    pub thumbnail_height: u32,
}

impl Default for MediaUploadConfig {
    fn default() -> Self {
        Self {
            max_image_size: 20 * 1024 * 1024,  // 20 MB
            max_video_size: 100 * 1024 * 1024, // 100 MB
            max_audio_size: 50 * 1024 * 1024,  // 50 MB
            supported_image_formats: vec![
                "image/jpeg".to_string(),
                "image/png".to_string(),
                "image/webp".to_string(),
                "image/gif".to_string(),
            ],
            supported_video_formats: vec![
                "video/mp4".to_string(),
                "video/webm".to_string(),
                "video/quicktime".to_string(),
            ],
            supported_audio_formats: vec![
                "audio/mpeg".to_string(),
                "audio/wav".to_string(),
                "audio/ogg".to_string(),
            ],
            generate_thumbnails: true,
            thumbnail_width: 320,
            thumbnail_height: 240,
        }
    }
}

impl MediaUploadConfig {
    /// 验证 MIME 类型
    pub fn validate_mime_type(&self, mime_type: &str) -> Result<MediaType, String> {
        let media_type = MediaType::from_mime(mime_type);
        
        match media_type {
            MediaType::Image => {
                if self.supported_image_formats.contains(&mime_type.to_string()) {
                    Ok(media_type)
                } else {
                    Err(format!("不支持的图片格式: {}", mime_type))
                }
            }
            MediaType::Video => {
                if self.supported_video_formats.contains(&mime_type.to_string()) {
                    Ok(media_type)
                } else {
                    Err(format!("不支持的视频格式: {}", mime_type))
                }
            }
            MediaType::Audio => {
                if self.supported_audio_formats.contains(&mime_type.to_string()) {
                    Ok(media_type)
                } else {
                    Err(format!("不支持的音频格式: {}", mime_type))
                }
            }
            MediaType::Other => Err(format!("不支持的媒体类型: {}", mime_type)),
        }
    }

    /// 获取指定媒体类型的大小限制
    pub fn get_size_limit(&self, media_type: MediaType) -> u64 {
        match media_type {
            MediaType::Image => self.max_image_size,
            MediaType::Video => self.max_video_size,
            MediaType::Audio => self.max_audio_size,
            MediaType::Other => 10 * 1024 * 1024, // 10 MB 默认
        }
    }
}

/// 媒体处理器
pub struct MediaProcessor;

impl MediaProcessor {
    /// 验证媒体
    pub fn validate(
        media: &MediaMetadata,
        config: &MediaUploadConfig,
    ) -> Result<(), String> {
        // 验证格式
        config.validate_mime_type(&media.mime_type)?;

        // 验证大小
        let size_limit = config.get_size_limit(media.media_type);
        media.validate_size(size_limit)?;

        Ok(())
    }

    /// 从 URL 列表提取媒体元数据
    pub fn extract_media_from_urls(urls: &[String]) -> Vec<MediaMetadata> {
        urls.iter()
            .filter_map(|url| {
                if url.starts_with("mxc://") {
                    Some(MediaMetadata::new(
                        url.clone(),
                        "image/jpeg".to_string(), // 默认假设为图片
                        0, // 大小未知
                    ))
                } else {
                    None
                }
            })
            .collect()
    }

    /// 生成媒体摘要（用于分享）
    pub fn generate_summary(media: &MediaMetadata, content_preview: &str) -> String {
        match media.media_type {
            MediaType::Image => format!("[图片] {}", content_preview),
            MediaType::Video => format!("[视频] {}", content_preview),
            MediaType::Audio => format!("[音频] {}", content_preview),
            MediaType::Other => format!("[媒体] {}", content_preview),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_media_type_from_mime() {
        assert_eq!(MediaType::from_mime("image/jpeg"), MediaType::Image);
        assert_eq!(MediaType::from_mime("video/mp4"), MediaType::Video);
        assert_eq!(MediaType::from_mime("audio/mpeg"), MediaType::Audio);
        assert_eq!(MediaType::from_mime("application/json"), MediaType::Other);
    }

    #[test]
    fn test_media_metadata_creation() {
        let media = MediaMetadata::new(
            "mxc://example.com/abc123".to_string(),
            "image/jpeg".to_string(),
            1024 * 1024, // 1 MB
        );

        assert_eq!(media.media_type, MediaType::Image);
        assert_eq!(media.size, 1024 * 1024);
    }

    #[test]
    fn test_media_size_validation() {
        let media = MediaMetadata::new(
            "mxc://example.com/abc123".to_string(),
            "image/jpeg".to_string(),
            20 * 1024 * 1024 + 1, // 超过 20 MB
        );

        assert!(media.validate_size(20 * 1024 * 1024).is_err());
    }

    #[test]
    fn test_thumbnail_url_generation() {
        let media = MediaMetadata::new(
            "mxc://example.com/abc123".to_string(),
            "image/png".to_string(),
            1024,
        );

        let thumb = media.build_thumbnail_url(320, 240);
        assert!(thumb.is_some());
        assert!(thumb.unwrap().contains("320"));
    }

    #[test]
    fn test_media_upload_config_validation() {
        let config = MediaUploadConfig::default();
        
        assert!(config.validate_mime_type("image/jpeg").is_ok());
        assert!(config.validate_mime_type("image/unsupported").is_err());
        assert!(config.validate_mime_type("video/mp4").is_ok());
    }

    #[test]
    fn test_media_processor_extract() {
        let urls = vec![
            "mxc://example.com/img1".to_string(),
            "https://example.com/img2".to_string(),
        ];

        let media = MediaProcessor::extract_media_from_urls(&urls);
        assert_eq!(media.len(), 1); // 只提取 mxc 开头的
    }

    #[test]
    fn test_media_processor_summary() {
        let media = MediaMetadata::new(
            "mxc://example.com/abc".to_string(),
            "image/jpeg".to_string(),
            1024,
        );

        let summary = MediaProcessor::generate_summary(&media, "Beautiful sunset");
        assert!(summary.contains("图片"));
        assert!(summary.contains("Beautiful sunset"));
    }
}
