//! 高级集成测试
//!
//! 测试优化后的功能模块的集成和协作。
//! 这些测试验证了缓存热更新、计数聚合、转发、分页等新功能。

#[cfg(test)]
mod advanced_integration_tests {
    use crate::{Moment, SocialFeedError, Result};
    use crate::services::cache::{ProfileCache, CacheInvalidationEvent};
    use crate::services::aggregation::{AggregationCache, AggregationStats};
    use crate::services::quote_forward::{ForwardMetadata, ForwardManager};
    use crate::services::pagination::{PaginationToken, PaginationDirection, PagedResult, PaginationState};
    use crate::services::search_index::SearchIndex;
    use crate::services::media::{MediaMetadata, MediaUploadConfig, MediaProcessor};
    use crate::services::rate_limit::{RateLimiter, RateLimitConfig, OperationType};
    use chrono::Utc;
    use matrix_sdk::ruma::OwnedUserId;

    // 模拟 Moment 创建
    fn create_test_moment(id: &str, text: &str, author: &str, likes: u64) -> Moment {
        Moment {
            id: id.to_string(),
            author_id: format!("@{}:example.com", author),
            author_name: author.to_string(),
            author_avatar: Some(format!("mxc://example.com/{}", author)),
            text: text.to_string(),
            images: vec![],
            created_at: Utc::now(),
            like_count: likes,
            comment_count: 0,
        }
    }

    #[test]
    fn test_pagination_bidirectional_flow() {
        // 创建初始令牌（向前）
        let token_forward = PaginationToken::forward("sync_token_1".to_string(), 0, 20);
        assert_eq!(token_forward.direction, PaginationDirection::Forward);

        // 移到下一页（向前）
        let next_forward = token_forward.next_token();
        assert_eq!(next_forward.start, 20);

        // 反向分页（向后）
        let token_backward = next_forward.reverse_direction();
        assert_eq!(token_backward.direction, PaginationDirection::Backward);

        // 验证不是陈旧的
        assert!(!token_backward.is_stale());
    }

    #[tokio::test]
    async fn test_cache_with_invalidation() {
        let cache = ProfileCache::new();
        let user_id = "@alice:example.com".parse::<OwnedUserId>().unwrap();

        // 设置缓存
        cache
            .set(
                user_id.clone(),
                "Alice".to_string(),
                Some("mxc://example.com/avatar1".to_string()),
            )
            .await;

        let cached = cache.get(&user_id).await;
        assert!(cached.is_some());

        // 注册失效监听器
        let invalidated = std::sync::Arc::new(std::sync::Mutex::new(false));
        let invalidated_clone = invalidated.clone();

        cache
            .on_invalidation(move |event| {
                if matches!(event, CacheInvalidationEvent::UserProfileChanged(_)) {
                    *invalidated_clone.lock().unwrap() = true;
                }
            })
            .await;

        // 触发失效
        cache.invalidate(&user_id).await;

        // 验证缓存已清除
        let cached = cache.get(&user_id).await;
        assert!(cached.is_none());

        // 验证监听器已触发
        assert!(*invalidated.lock().unwrap());
    }

    #[tokio::test]
    async fn test_aggregation_stats_update() {
        let cache = AggregationCache::new();
        let room_id = "!room:example.com";
        let event_id = "$event123";

        // 模拟实时点赞
        cache.increment_likes(room_id, event_id).await;
        cache.increment_likes(room_id, event_id).await;
        cache.increment_replies(room_id, event_id).await;

        let stats = cache.get_stats(room_id, event_id).await;
        assert_eq!(stats.like_count, 2);
        assert_eq!(stats.reply_count, 1);

        // 模拟删除点赞（reaction 撤回）
        cache.decrement_likes(room_id, event_id).await;
        let stats = cache.get_stats(room_id, event_id).await;
        assert_eq!(stats.like_count, 1);

        // 批量更新
        let updates = vec![(
            room_id.to_string(),
            "$event456".to_string(),
            AggregationStats {
                like_count: 10,
                reply_count: 5,
                forward_count: 2,
            },
        )];
        cache.update_batch(updates).await;

        let stats = cache.get_stats(room_id, "$event456").await;
        assert_eq!(stats.like_count, 10);
        assert_eq!(stats.reply_count, 5);
    }

    #[test]
    fn test_forward_metadata_chain() {
        let moment = create_test_moment("$original", "Great insights!", "alice", 10);

        let url = ForwardManager::build_event_url(
            "example.com",
            "!room:example.com",
            "$original",
        );

        let metadata = ForwardMetadata::from_moment(
            &moment,
            "!room:example.com".to_string(),
            "I totally agree!".to_string(),
            url,
        );

        // 验证原文保存
        assert_eq!(metadata.original_author_id, "@alice:example.com");
        assert_eq!(metadata.original_text, "Great insights!");
        assert_eq!(metadata.quote_text, "I totally agree!");

        // 检查格式化输出
        let formatted = metadata.formatted_body();
        assert!(formatted.contains("blockquote"));
        assert!(formatted.contains("alice"));

        // 检查防无限转发
        let deep_forward = "<blockquote><blockquote><blockquote><blockquote>Too deep</blockquote></blockquote></blockquote></blockquote>";
        assert!(ForwardManager::detect_forward_loop(deep_forward, 3));
    }

    #[tokio::test]
    async fn test_rate_limiter_backoff() {
        let config = RateLimitConfig {
            requests_per_second: 5.0,
            bucket_capacity: 5,
            max_retries: 3,
            initial_backoff_ms: 100,
            ..Default::default()
        };

        let limiter = RateLimiter::new(config.clone());

        // 耗尽令牌
        for _ in 0..5 {
            let _ = limiter.allow(OperationType::PostMoment).await;
        }

        // 第6个请求应该被限制
        assert!(limiter.allow(OperationType::PostMoment).await.is_err());

        // 验证重试策略
        let policy = limiter.get_retry_policy(OperationType::PostMoment).await;
        assert_eq!(policy.attempt, 0);
        assert!(policy.can_retry(&config));

        // 模拟 homeserver 返回限制
        limiter
            .handle_rate_limit(OperationType::PostMoment, 5000)
            .await;

        let updated_policy = limiter.get_retry_policy(OperationType::PostMoment).await;
        assert_eq!(updated_policy.next_backoff_ms, 5000);
    }

    #[tokio::test]
    async fn test_search_index_integration() {
        let index = SearchIndex::new(100);

        let m1 = create_test_moment("$1", "Love #photography and #nature", "alice", 5);
        let m2 = create_test_moment("$2", "Check out @alice's new portfolio", "bob", 3);
        let m3 = create_test_moment("$3", "Photography tips for beginners", "charlie", 8);

        index.index_moment(&m1).await.unwrap();
        index.index_moment(&m2).await.unwrap();
        index.index_moment(&m3).await.unwrap();

        // 全文搜索（只匹配 Word 类型 token，不含 Hashtag 类型的 #photography）
        let results = index.search("photography", 10).await;
        assert_eq!(results.len(), 1);

        // 标签搜索
        let hashtag_results = index.search_hashtag("photography", 10).await;
        assert_eq!(hashtag_results.len(), 1);
        assert_eq!(hashtag_results[0].id, "$1");

        // 提及搜索（@alice's 分词后的 token 是 "alice's"）
        let mention_results = index.search_mention("alice's", 10).await;
        assert_eq!(mention_results.len(), 1);

        // 获取统计信息
        let stats = index.stats().await;
        assert_eq!(stats.total_moments, 3);
        assert!(stats.total_tokens > 0);

        // 删除并验证
        index.remove_moment("$1").await.unwrap();
        assert_eq!(index.size().await, 2);
    }

    #[test]
    fn test_media_metadata_complete_flow() {
        let config = MediaUploadConfig::default();

        // 创建媒体元数据
        let media = MediaMetadata::new(
            "mxc://example.com/abc123".to_string(),
            "image/jpeg".to_string(),
            5 * 1024 * 1024, // 5 MB
        );

        // 验证格式
        assert!(config.validate_mime_type(&media.mime_type).is_ok());
        assert!(media.validate_size(config.max_image_size).is_ok());

        // 生成缩略图
        let thumb = media.build_thumbnail_url(320, 240);
        assert!(thumb.is_some());
        assert!(thumb.unwrap().contains("320"));

        // 生成摘要
        let summary = MediaProcessor::generate_summary(&media, "Sunset photo");
        assert!(summary.contains("图片"));
        assert!(summary.contains("Sunset"));
    }

    #[test]
    fn test_error_handling_granular() {
        // 测试各种细粒度错误
        let err = SocialFeedError::RateLimited {
            retry_after_ms: 5000,
        };
        assert!(err.to_string().contains("5000"));

        let err = SocialFeedError::InvalidJson("Invalid data".to_string());
        assert!(err.to_string().contains("JSON"));

        let err = SocialFeedError::CyclicDependency;
        assert!(err.to_string().contains("循环依赖"));

        // 验证 Result 类型
        let result: Result<()> = Err(SocialFeedError::TokenExpired);
        assert!(result.is_err());
    }

    #[test]
    fn test_paged_result_dual_direction() {
        let items = vec![1, 2, 3, 4, 5];
        let result = PagedResult::from_vec_bidirectional(
            items,
            50,
            5,
            "sync_token".to_string(),
            Some(100),
        );

        assert_eq!(result.len(), 5);
        assert!(result.can_paginate_forward());  // 50 + 5 < 100
        assert!(result.can_paginate_backward()); // 50 > 0

        // 验证令牌方向
        if let Some(forward) = result.forward_token {
            assert_eq!(forward.direction, PaginationDirection::Forward);
        }
        if let Some(backward) = result.backward_token {
            assert_eq!(backward.direction, PaginationDirection::Backward);
        }
    }

    #[tokio::test]
    async fn test_pagination_state_navigation() {
        let mut state = PaginationState::first_page("sync_token".to_string(), 20);

        // 向前分页 3 次
        state.next_forward();
        state.next_forward();
        state.next_forward();

        assert_eq!(state.page_count(), 3);
        assert!(state.can_go_back());

        // 返回
        state.go_back();
        assert_eq!(state.page_count(), 3); // 页数不减，但位置改变

        // 向后分页
        state.next_backward();
        assert!(state.page_count() > 0);
    }
}
