//! 搜索和过滤模块 [SearchFilter + SearchEngine，供 App 层对 `Vec<Moment>` 过滤排序]
//!
//! 提供动态内容搜索和高级过滤功能。

use crate::types::models::Moment;
use chrono::{DateTime, Utc};

/// 搜索过滤器
#[derive(Debug, Clone)]
pub struct SearchFilter {
    /// 关键词（搜索 text 字段）
    pub keyword: Option<String>,
    /// 作者 ID
    pub author_id: Option<String>,
    /// 起始时间
    pub start_time: Option<DateTime<Utc>>,
    /// 结束时间
    pub end_time: Option<DateTime<Utc>>,
    /// 最小点赞数
    pub min_likes: Option<u64>,
    /// 最小评论数
    pub min_comments: Option<u64>,
    /// 是否只包含有图片的动态
    pub has_images: bool,
}

impl SearchFilter {
    /// 创建空的过滤器
    pub fn new() -> Self {
        Self {
            keyword: None,
            author_id: None,
            start_time: None,
            end_time: None,
            min_likes: None,
            min_comments: None,
            has_images: false,
        }
    }

    /// 设置关键词
    pub fn with_keyword(mut self, keyword: String) -> Self {
        self.keyword = Some(keyword);
        self
    }

    /// 设置作者 ID
    pub fn with_author(mut self, author_id: String) -> Self {
        self.author_id = Some(author_id);
        self
    }

    /// 设置时间范围
    pub fn with_time_range(mut self, start: DateTime<Utc>, end: DateTime<Utc>) -> Self {
        self.start_time = Some(start);
        self.end_time = Some(end);
        self
    }

    /// 设置最小点赞数
    pub fn with_min_likes(mut self, min_likes: u64) -> Self {
        self.min_likes = Some(min_likes);
        self
    }

    /// 设置最小评论数
    pub fn with_min_comments(mut self, min_comments: u64) -> Self {
        self.min_comments = Some(min_comments);
        self
    }

    /// 只包含有图片的动态
    pub fn only_with_images(mut self) -> Self {
        self.has_images = true;
        self
    }

    /// 检查动态是否匹配过滤器
    pub fn matches(&self, moment: &Moment) -> bool {
        // 检查关键词
        if let Some(keyword) = &self.keyword {
            if !moment.text.to_lowercase().contains(&keyword.to_lowercase()) {
                return false;
            }
        }

        // 检查作者
        if let Some(author_id) = &self.author_id {
            if moment.author_id != *author_id {
                return false;
            }
        }

        // 检查时间范围
        if let Some(start) = self.start_time {
            if moment.created_at < start {
                return false;
            }
        }
        if let Some(end) = self.end_time {
            if moment.created_at > end {
                return false;
            }
        }

        // 检查点赞数
        if let Some(min_likes) = self.min_likes {
            if moment.like_count < min_likes {
                return false;
            }
        }

        // 检查评论数
        if let Some(min_comments) = self.min_comments {
            if moment.comment_count < min_comments {
                return false;
            }
        }

        // 检查是否有图片
        if self.has_images && moment.images.is_empty() {
            return false;
        }

        true
    }
}

impl Default for SearchFilter {
    fn default() -> Self {
        Self::new()
    }
}

/// 搜索结果排序方式
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortBy {
    /// 按时间倒序（最新优先）
    TimeDesc,
    /// 按时间正序（最早优先）
    TimeAsc,
    /// 按点赞数倒序
    LikesDesc,
    /// 按评论数倒序
    CommentsDesc,
    /// 按热度倒序（点赞 + 评论）
    HotDesc,
}

/// 搜索和过滤工具
pub struct SearchEngine;

impl SearchEngine {
    /// 搜索动态
    pub fn search(moments: &[Moment], filter: &SearchFilter) -> Vec<Moment> {
        moments
            .iter()
            .filter(|m| filter.matches(m))
            .cloned()
            .collect()
    }

    /// 对动态进行排序
    pub fn sort(moments: &mut Vec<Moment>, sort_by: SortBy) {
        match sort_by {
            SortBy::TimeDesc => {
                moments.sort_by(|a, b| b.created_at.cmp(&a.created_at));
            }
            SortBy::TimeAsc => {
                moments.sort_by(|a, b| a.created_at.cmp(&b.created_at));
            }
            SortBy::LikesDesc => {
                moments.sort_by(|a, b| b.like_count.cmp(&a.like_count));
            }
            SortBy::CommentsDesc => {
                moments.sort_by(|a, b| b.comment_count.cmp(&a.comment_count));
            }
            SortBy::HotDesc => {
                moments.sort_by(|a, b| {
                    let a_hot = a.like_count + a.comment_count;
                    let b_hot = b.like_count + b.comment_count;
                    b_hot.cmp(&a_hot)
                });
            }
        }
    }

    /// 搜索、过滤并排序
    pub fn search_and_sort(moments: &[Moment], filter: &SearchFilter, sort_by: SortBy) -> Vec<Moment> {
        let mut results = Self::search(moments, filter);
        Self::sort(&mut results, sort_by);
        results
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    fn create_test_moment(text: &str, author_id: &str, likes: u64, comments: u64) -> Moment {
        Moment {
            id: "test_id".to_string(),
            author_id: author_id.to_string(),
            author_name: "Test User".to_string(),
            author_avatar: None,
            text: text.to_string(),
            images: vec![],
            created_at: Utc::now(),
            like_count: likes,
            comment_count: comments,
        }
    }

    #[test]
    fn test_search_by_keyword() {
        let moments = vec![
            create_test_moment("Hello World", "@alice:example.com", 5, 2),
            create_test_moment("Goodbye", "@bob:example.com", 3, 1),
        ];

        let filter = SearchFilter::new().with_keyword("Hello".to_string());
        let results = SearchEngine::search(&moments, &filter);

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].text, "Hello World");
    }

    #[test]
    fn test_search_by_author() {
        let moments = vec![
            create_test_moment("Message 1", "@alice:example.com", 5, 2),
            create_test_moment("Message 2", "@bob:example.com", 3, 1),
        ];

        let filter = SearchFilter::new().with_author("@alice:example.com".to_string());
        let results = SearchEngine::search(&moments, &filter);

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].author_id, "@alice:example.com");
    }

    #[test]
    fn test_sort_by_likes() {
        let mut moments = vec![
            create_test_moment("A", "@alice:example.com", 5, 2),
            create_test_moment("B", "@bob:example.com", 10, 1),
            create_test_moment("C", "@charlie:example.com", 3, 5),
        ];

        SearchEngine::sort(&mut moments, SortBy::LikesDesc);

        assert_eq!(moments[0].like_count, 10);
        assert_eq!(moments[1].like_count, 5);
        assert_eq!(moments[2].like_count, 3);
    }

    // ── 补充：filter 时间范围 + 阈值 + has_images + 组合 ──

    #[test]
    fn test_filter_by_time_range() {
        let t1 = Utc::now() - chrono::Duration::hours(2);
        let t2 = Utc::now() - chrono::Duration::hours(1);
        let t3 = Utc::now();

        let moments = vec![
            Moment { created_at: t1, ..create_test_moment("old", "@a", 0, 0) },
            Moment { created_at: t2, ..create_test_moment("mid", "@b", 0, 0) },
            Moment { created_at: t3, ..create_test_moment("new", "@c", 0, 0) },
        ];

        let filter = SearchFilter::new()
            .with_time_range(t2 - chrono::Duration::minutes(1), t3 + chrono::Duration::minutes(1));
        let results = SearchEngine::search(&moments, &filter);
        assert_eq!(results.len(), 2);
    }

    #[test]
    fn test_filter_by_min_likes() {
        let moments = vec![
            create_test_moment("A", "@a", 1, 0),
            create_test_moment("B", "@b", 5, 0),
            create_test_moment("C", "@c", 10, 0),
        ];

        let filter = SearchFilter::new().with_min_likes(5);
        let results = SearchEngine::search(&moments, &filter);
        assert_eq!(results.len(), 2);
    }

    #[test]
    fn test_filter_by_min_comments() {
        let moments = vec![
            create_test_moment("A", "@a", 0, 1),
            create_test_moment("B", "@b", 0, 3),
        ];

        let filter = SearchFilter::new().with_min_comments(2);
        let results = SearchEngine::search(&moments, &filter);
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn test_filter_has_images() {
        let moments = vec![
            Moment { images: vec!["https://img.jpg".into()], ..create_test_moment("with", "@a", 0, 0) },
            Moment { images: vec![], ..create_test_moment("without", "@b", 0, 0) },
        ];

        let results = SearchEngine::search(&moments, &SearchFilter::new().only_with_images());
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn test_filter_combined_conditions() {
        let moments = vec![
            create_test_moment("hello world", "@a", 5, 3),
            create_test_moment("hello", "@a", 1, 0),
            create_test_moment("hello rust", "@b", 5, 0),
        ];

        let filter = SearchFilter::new()
            .with_keyword("hello".into())
            .with_author("@a".into())
            .with_min_likes(3);
        let results = SearchEngine::search(&moments, &filter);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].like_count, 5);
    }

    #[test]
    fn test_filter_empty_result() {
        let moments = vec![create_test_moment("hello", "@a", 0, 0)];
        let filter = SearchFilter::new().with_keyword("nonexistent".into());
        let results = SearchEngine::search(&moments, &filter);
        assert!(results.is_empty());
    }

    #[test]
    fn test_filter_default_matches_all() {
        let moments = vec![
            create_test_moment("A", "@a", 0, 0),
            create_test_moment("B", "@b", 0, 0),
        ];
        let results = SearchEngine::search(&moments, &SearchFilter::new());
        assert_eq!(results.len(), 2);
    }

    // ── 补充：sort 剩余 4 种排序 ──

    #[test]
    fn test_sort_by_time_desc() {
        let t1 = Utc::now() - chrono::Duration::hours(2);
        let t2 = Utc::now();
        let mut moments = vec![
            Moment { created_at: t1, ..create_test_moment("old", "@a", 0, 0) },
            Moment { created_at: t2, ..create_test_moment("new", "@b", 0, 0) },
        ];
        SearchEngine::sort(&mut moments, SortBy::TimeDesc);
        assert_eq!(moments[0].text, "new");
    }

    #[test]
    fn test_sort_by_time_asc() {
        let t1 = Utc::now() - chrono::Duration::hours(2);
        let t2 = Utc::now();
        let mut moments = vec![
            Moment { created_at: t2, ..create_test_moment("new", "@b", 0, 0) },
            Moment { created_at: t1, ..create_test_moment("old", "@a", 0, 0) },
        ];
        SearchEngine::sort(&mut moments, SortBy::TimeAsc);
        assert_eq!(moments[0].text, "old");
    }

    #[test]
    fn test_sort_by_comments_desc() {
        let mut moments = vec![
            create_test_moment("A", "@a", 0, 2),
            create_test_moment("B", "@b", 0, 10),
            create_test_moment("C", "@c", 0, 5),
        ];
        SearchEngine::sort(&mut moments, SortBy::CommentsDesc);
        assert_eq!(moments[0].comment_count, 10);
        assert_eq!(moments[2].comment_count, 2);
    }

    #[test]
    fn test_sort_by_hot_desc() {
        let mut moments = vec![
            create_test_moment("A", "@a", 5, 2),   // hot = 7
            create_test_moment("B", "@b", 3, 10),  // hot = 13
            create_test_moment("C", "@c", 1, 1),   // hot = 2
        ];
        SearchEngine::sort(&mut moments, SortBy::HotDesc);
        assert_eq!(moments[0].like_count + moments[0].comment_count, 13);
        assert_eq!(moments[2].like_count + moments[2].comment_count, 2);
    }

    #[test]
    fn test_search_and_sort_combined() {
        let moments = vec![
            create_test_moment("hello A", "@a", 1, 0),
            create_test_moment("hello B", "@a", 10, 0),
            create_test_moment("world", "@b", 5, 0),
        ];

        let filter = SearchFilter::new().with_keyword("hello".into());
        let results = SearchEngine::search_and_sort(&moments, &filter, SortBy::LikesDesc);
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].like_count, 10);
    }
}
