//! 全文搜索索引模块 [倒排索引，供 App 层对已拉取的 Moment 建索引全文搜索]
//!
//! 使用倒排索引支持高效的全文搜索。
//! 可选集成 tantivy 或 elastic 搜索引擎实现更高级功能。

use crate::types::models::Moment;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::RwLock;

/// 单个搜索词条
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SearchToken {
    /// 词条文本（已小写）
    pub term: String,
    /// 词条类型（单词、标签、提及等）
    pub token_type: TokenType,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum TokenType {
    /// 普通单词
    Word,
    /// 话题标签 (#tag)
    Hashtag,
    /// 用户提及 (@user)
    Mention,
    /// URL
    Url,
}

impl SearchToken {
    /// 创建新的搜索词条
    pub fn new(term: String, token_type: TokenType) -> Self {
        Self {
            term: term.to_lowercase(),
            token_type,
        }
    }

    /// 从文本分词
    pub fn tokenize(text: &str) -> Vec<SearchToken> {
        let mut tokens = Vec::new();

        // 简单分词器
        for part in text.split_whitespace() {
            if part.starts_with('#') && part.len() > 1 {
                // 标签
                tokens.push(SearchToken::new(
                    part[1..].to_string(),
                    TokenType::Hashtag,
                ));
            } else if part.starts_with('@') && part.len() > 1 {
                // 提及
                tokens.push(SearchToken::new(
                    part[1..].to_string(),
                    TokenType::Mention,
                ));
            } else if part.starts_with("http") {
                // URL
                tokens.push(SearchToken::new(part.to_string(), TokenType::Url));
            } else if !part.is_empty() {
                // 普通单词
                tokens.push(SearchToken::new(part.to_string(), TokenType::Word));
            }
        }

        tokens
    }
}

/// 倒排索引条目
#[derive(Debug, Clone)]
pub struct InvertedIndexEntry {
    /// 包含此词条的事件 ID 列表
    pub event_ids: HashSet<String>,
    /// 该词条的出现频率
    pub frequency: HashMap<String, usize>,
}

/// 全文搜索索引
pub struct SearchIndex {
    /// 词条 → 倒排索引条目
    inverted_index: Arc<RwLock<HashMap<SearchToken, InvertedIndexEntry>>>,
    /// 事件 ID → Moment
    moments: Arc<RwLock<HashMap<String, Moment>>>,
    /// 最大索引大小
    max_index_size: usize,
}

impl std::fmt::Debug for SearchIndex {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SearchIndex")
            .field("max_index_size", &self.max_index_size)
            .finish()
    }
}

impl SearchIndex {
    /// 创建新的搜索索引
    pub fn new(max_index_size: usize) -> Self {
        Self {
            inverted_index: Arc::new(RwLock::new(HashMap::new())),
            moments: Arc::new(RwLock::new(HashMap::new())),
            max_index_size,
        }
    }

    /// 添加 Moment 到索引
    pub async fn index_moment(&self, moment: &Moment) -> Result<(), String> {
        let moments = self.moments.read().await;
        
        // 检查索引大小限制
        if moments.len() >= self.max_index_size {
            return Err("索引已满，无法添加更多内容".to_string());
        }
        drop(moments);

        // 分词
        let mut tokens = SearchToken::tokenize(&moment.text);
        tokens.extend(SearchToken::tokenize(&moment.author_name));

        // 更新倒排索引
        let mut index = self.inverted_index.write().await;
        for token in tokens {
            let entry = index
                .entry(token.clone())
                .or_insert_with(|| InvertedIndexEntry {
                    event_ids: HashSet::new(),
                    frequency: HashMap::new(),
                });

            entry.event_ids.insert(moment.id.clone());
            *entry
                .frequency
                .entry(moment.id.clone())
                .or_insert(0) += 1;
        }

        // 存储 Moment
        let mut moments = self.moments.write().await;
        moments.insert(moment.id.clone(), moment.clone());

        Ok(())
    }

    /// 搜索关键词
    pub async fn search(&self, query: &str, limit: usize) -> Vec<Moment> {
        let tokens = SearchToken::tokenize(query);
        if tokens.is_empty() {
            return Vec::new();
        }

        let index = self.inverted_index.read().await;
        let moments = self.moments.read().await;

        // 获取所有匹配的事件 ID
        let mut results = HashSet::new();
        let mut first = true;

        for token in tokens {
            if let Some(entry) = index.get(&token) {
                if first {
                    results = entry.event_ids.clone();
                    first = false;
                } else {
                    // 取交集（AND 搜索）
                    results.retain(|id| entry.event_ids.contains(id));
                }
            } else if !first {
                // 如果某个词条不在索引中，结果为空（AND 逻辑）
                return Vec::new();
            }
        }

        // 按点赞数排序并限制结果数量
        let mut result_moments: Vec<_> = results
            .iter()
            .filter_map(|id| moments.get(id))
            .cloned()
            .collect();

        result_moments.sort_by(|a, b| b.like_count.cmp(&a.like_count));
        result_moments.truncate(limit);

        result_moments
    }

    /// 搜索标签
    pub async fn search_hashtag(&self, tag: &str, limit: usize) -> Vec<Moment> {
        let token = SearchToken::new(tag.to_string(), TokenType::Hashtag);
        
        let index = self.inverted_index.read().await;
        if let Some(entry) = index.get(&token) {
            let moments = self.moments.read().await;
            let mut results: Vec<_> = entry
                .event_ids
                .iter()
                .filter_map(|id| moments.get(id))
                .cloned()
                .collect();

            results.sort_by(|a, b| b.created_at.cmp(&a.created_at));
            results.truncate(limit);
            results
        } else {
            Vec::new()
        }
    }

    /// 搜索提及
    pub async fn search_mention(&self, user_id: &str, limit: usize) -> Vec<Moment> {
        let token = SearchToken::new(user_id.to_string(), TokenType::Mention);
        
        let index = self.inverted_index.read().await;
        if let Some(entry) = index.get(&token) {
            let moments = self.moments.read().await;
            let mut results: Vec<_> = entry
                .event_ids
                .iter()
                .filter_map(|id| moments.get(id))
                .cloned()
                .collect();

            results.sort_by(|a, b| b.created_at.cmp(&a.created_at));
            results.truncate(limit);
            results
        } else {
            Vec::new()
        }
    }

    /// 从索引中删除 Moment
    pub async fn remove_moment(&self, moment_id: &str) -> Result<(), String> {
        let mut moments = self.moments.write().await;
        moments.remove(moment_id);

        let mut index = self.inverted_index.write().await;
        for entry in index.values_mut() {
            entry.event_ids.remove(moment_id);
        }

        Ok(())
    }

    /// 清除索引
    pub async fn clear(&self) {
        self.inverted_index.write().await.clear();
        self.moments.write().await.clear();
    }

    /// 获取索引大小
    pub async fn size(&self) -> usize {
        self.moments.read().await.len()
    }

    /// 获取索引统计信息
    pub async fn stats(&self) -> IndexStats {
        let index = self.inverted_index.read().await;
        let moments = self.moments.read().await;

        IndexStats {
            total_moments: moments.len(),
            total_tokens: index.len(),
            avg_tokens_per_moment: if moments.is_empty() {
                0.0
            } else {
                index.values().map(|e| e.event_ids.len()).sum::<usize>() as f64 / moments.len() as f64
            },
        }
    }
}

/// 索引统计信息
#[derive(Debug, Clone)]
pub struct IndexStats {
    pub total_moments: usize,
    pub total_tokens: usize,
    pub avg_tokens_per_moment: f64,
}

impl Default for SearchIndex {
    fn default() -> Self {
        Self::new(10000) // 默认最大 10000 条
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    fn create_test_moment(id: &str, text: &str, author_name: &str) -> Moment {
        Moment {
            id: id.to_string(),
            author_id: "@alice:example.com".to_string(),
            author_name: author_name.to_string(),
            author_avatar: None,
            text: text.to_string(),
            images: vec![],
            created_at: Utc::now(),
            like_count: 5,
            comment_count: 2,
        }
    }

    #[test]
    fn test_search_token_tokenize() {
        let text = "Hello #world @alice https://example.com";
        let tokens = SearchToken::tokenize(text);

        assert_eq!(tokens.len(), 4);
        assert_eq!(tokens[0].token_type, TokenType::Word);
        assert_eq!(tokens[1].token_type, TokenType::Hashtag);
        assert_eq!(tokens[2].token_type, TokenType::Mention);
        assert_eq!(tokens[3].token_type, TokenType::Url);
    }

    #[tokio::test]
    async fn test_search_index_add_moment() {
        let index = SearchIndex::new(100);
        let moment = create_test_moment("$1", "Hello world", "Alice");

        assert!(index.index_moment(&moment).await.is_ok());
        assert_eq!(index.size().await, 1);
    }

    #[tokio::test]
    async fn test_search_index_search() {
        let index = SearchIndex::new(100);
        let moment1 = create_test_moment("$1", "Hello world", "Alice");
        let moment2 = create_test_moment("$2", "Goodbye world", "Bob");

        index.index_moment(&moment1).await.unwrap();
        index.index_moment(&moment2).await.unwrap();

        let results = index.search("hello", 10).await;
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "$1");
    }

    #[tokio::test]
    async fn test_search_hashtag() {
        let index = SearchIndex::new(100);
        let moment = create_test_moment("$1", "Great #photography #art", "Alice");

        index.index_moment(&moment).await.unwrap();

        let results = index.search_hashtag("photography", 10).await;
        assert_eq!(results.len(), 1);
    }

    #[tokio::test]
    async fn test_search_index_remove() {
        let index = SearchIndex::new(100);
        let moment = create_test_moment("$1", "Test content", "Alice");

        index.index_moment(&moment).await.unwrap();
        assert_eq!(index.size().await, 1);

        index.remove_moment("$1").await.unwrap();
        assert_eq!(index.size().await, 0);
    }

    #[tokio::test]
    async fn test_search_index_stats() {
        let index = SearchIndex::new(100);
        let moment = create_test_moment("$1", "Hello world test", "Alice");

        index.index_moment(&moment).await.unwrap();
        let stats = index.stats().await;

        assert_eq!(stats.total_moments, 1);
        assert!(stats.total_tokens > 0);
    }
}
