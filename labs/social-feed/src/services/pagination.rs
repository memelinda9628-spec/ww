//! 分页模块 [PaginationToken / PagedResult，供 App 层自行管理分页游标]
//!
//! 提供双向分页游标管理和增量同步功能。

use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

/// 分页方向
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PaginationDirection {
    /// 向后（新消息）
    Forward,
    /// 向前（旧消息）
    Backward,
}

/// 分页令牌，用于标记分页位置
/// 
/// 支持双向分页：
/// - Forward: 获取更新的消息（向下滚动）
/// - Backward: 获取更旧的消息（向上滚动）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaginationToken {
    /// 游标标识符（Matrix sync token）
    pub cursor: String,
    /// 该页的起始位置（事件索引）
    pub start: usize,
    /// 该页的大小
    pub size: usize,
    /// 分页方向
    pub direction: PaginationDirection,
    /// 创建时间
    pub created_at: DateTime<Utc>,
}

impl PaginationToken {
    /// 创建新的分页令牌
    pub fn new(cursor: String, start: usize, size: usize, direction: PaginationDirection) -> Self {
        Self {
            cursor,
            start,
            size,
            direction,
            created_at: Utc::now(),
        }
    }

    /// 创建向前分页的令牌
    pub fn forward(cursor: String, start: usize, size: usize) -> Self {
        Self::new(cursor, start, size, PaginationDirection::Forward)
    }

    /// 创建向后分页的令牌
    pub fn backward(cursor: String, start: usize, size: usize) -> Self {
        Self::new(cursor, start, size, PaginationDirection::Backward)
    }

    /// 获取下一页的起始位置
    pub fn next_start(&self) -> usize {
        match self.direction {
            PaginationDirection::Forward => self.start + self.size,
            PaginationDirection::Backward => self.start.saturating_sub(self.size),
        }
    }

    /// 创建下一页的令牌
    pub fn next_token(&self) -> Self {
        Self {
            cursor: self.cursor.clone(),
            start: self.next_start(),
            size: self.size,
            direction: self.direction,
            created_at: Utc::now(),
        }
    }

    /// 反向分页方向（用于从底部滚到顶部）
    pub fn reverse_direction(&self) -> Self {
        let new_direction = match self.direction {
            PaginationDirection::Forward => PaginationDirection::Backward,
            PaginationDirection::Backward => PaginationDirection::Forward,
        };
        
        Self {
            cursor: self.cursor.clone(),
            start: self.start,
            size: self.size,
            direction: new_direction,
            created_at: Utc::now(),
        }
    }

    /// 检查令牌是否过期（5 分钟）
    pub fn is_stale(&self) -> bool {
        let elapsed = Utc::now().signed_duration_since(self.created_at);
        elapsed.num_minutes() > 5
    }
}

/// 分页结果
/// 
/// 包含当前页的数据和分页状态信息。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PagedResult<T> {
    /// 当前页的数据
    pub items: Vec<T>,
    /// 是否有向前的数据（更新消息）
    pub has_forward: bool,
    /// 是否有向后的数据（更旧消息）
    pub has_backward: bool,
    /// 向前分页的令牌（获取更新消息）
    pub forward_token: Option<PaginationToken>,
    /// 向后分页的令牌（获取更旧消息）
    pub backward_token: Option<PaginationToken>,
    /// 当前总数（如果可用）
    pub total_count: Option<usize>,
}

impl<T> PagedResult<T> {
    /// 创建新的分页结果
    pub fn new(
        items: Vec<T>,
        has_forward: bool,
        has_backward: bool,
        forward_token: Option<PaginationToken>,
        backward_token: Option<PaginationToken>,
    ) -> Self {
        Self {
            items,
            has_forward,
            has_backward,
            forward_token,
            backward_token,
            total_count: None,
        }
    }

    /// 从向量创建分页结果（向前分页）。
    ///
    /// 返回的 forward_token 指向当前页的起始位置 (start)，
    /// 调用方需要调用 `token.next_token()` 获取下一页的令牌。
    pub fn from_vec(
        items: Vec<T>,
        start: usize,
        page_size: usize,
        cursor: String,
    ) -> Self {
        let has_more = items.len() == page_size;
        let forward_token = if has_more {
            Some(PaginationToken::forward(cursor.clone(), start, page_size))
        } else {
            None
        };
        let backward_token = if start > 0 {
            Some(PaginationToken::backward(cursor, start, page_size))
        } else {
            None
        };

        Self {
            items,
            has_forward: has_more,
            has_backward: start > 0,
            forward_token: forward_token.map(|t| t.next_token()),
            backward_token,
            total_count: None,
        }
    }

    /// 从向量创建分页结果（双向）
    pub fn from_vec_bidirectional(
        items: Vec<T>,
        start: usize,
        page_size: usize,
        cursor: String,
        total_count: Option<usize>,
    ) -> Self {
        let has_forward = total_count.map_or(true, |total| start + page_size < total);
        let has_backward = start > 0;

        let forward_token = if has_forward {
            Some(PaginationToken::forward(cursor.clone(), start, page_size))
        } else {
            None
        };
        let backward_token = if has_backward {
            Some(PaginationToken::backward(cursor, start, page_size))
        } else {
            None
        };

        Self {
            items,
            has_forward,
            has_backward,
            forward_token: forward_token.map(|t| t.next_token()),
            backward_token,
            total_count,
        }
    }

    /// 获取结果中的项目数量
    pub fn len(&self) -> usize {
        self.items.len()
    }

    /// 检查结果是否为空
    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }

    /// 检查是否可以继续向前分页
    pub fn can_paginate_forward(&self) -> bool {
        self.has_forward && self.forward_token.is_some()
    }

    /// 检查是否可以继续向后分页
    pub fn can_paginate_backward(&self) -> bool {
        self.has_backward && self.backward_token.is_some()
    }
}

/// 分页状态管理
#[derive(Debug, Clone)]
pub struct PaginationState {
    /// 当前分页令牌（双向）
    current_token: Option<PaginationToken>,
    /// 向前的历史令牌（用于返回）
    forward_history: Vec<PaginationToken>,
    /// 向后的历史令牌（用于返回）
    backward_history: Vec<PaginationToken>,
    /// 总页数统计
    page_count: usize,
}

impl PaginationState {
    /// 创建新的分页状态
    pub fn new() -> Self {
        Self {
            current_token: None,
            forward_history: Vec::new(),
            backward_history: Vec::new(),
            page_count: 0,
        }
    }

    /// 初始化第一页
    pub fn first_page(cursor: String, page_size: usize) -> Self {
        Self {
            current_token: Some(PaginationToken::forward(cursor, 0, page_size)),
            forward_history: Vec::new(),
            backward_history: Vec::new(),
            page_count: 0,
        }
    }

    /// 向前分页
    pub fn next_forward(&mut self) -> Option<PaginationToken> {
        self.current_token.take().map(|token| {
            let next = token.next_token();
            self.backward_history.push(token);  // 保存历史以便返回
            self.current_token = Some(next.clone());
            self.page_count += 1;
            next
        })
    }

    /// 向后分页
    pub fn next_backward(&mut self) -> Option<PaginationToken> {
        self.current_token.take().map(|token| {
            let prev = token.reverse_direction();
            self.forward_history.push(token);  // 保存历史以便返回
            self.current_token = Some(prev.clone());
            self.page_count += 1;
            prev
        })
    }

    /// 返回到上一页（前向历史）
    pub fn go_back(&mut self) -> Option<PaginationToken> {
        self.backward_history.pop().map(|token| {
            self.current_token = Some(token.clone());
            token
        })
    }

    /// 获取当前的分页令牌
    pub fn current(&self) -> Option<&PaginationToken> {
        self.current_token.as_ref()
    }

    /// 获取已加载的页数
    pub fn page_count(&self) -> usize {
        self.page_count
    }

    /// 检查是否可以返回
    pub fn can_go_back(&self) -> bool {
        !self.backward_history.is_empty()
    }

    /// 重置分页状态
    pub fn reset(&mut self) {
        self.current_token = None;
        self.forward_history.clear();
        self.backward_history.clear();
        self.page_count = 0;
    }
}

impl Default for PaginationState {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pagination_token_forward() {
        let token = PaginationToken::forward("cursor1".to_string(), 0, 20);
        let next = token.next_token();
        
        assert_eq!(next.start, 20);
        assert_eq!(next.size, 20);
        assert_eq!(next.direction, PaginationDirection::Forward);
    }

    #[test]
    fn test_pagination_token_backward() {
        let token = PaginationToken::backward("cursor1".to_string(), 40, 20);
        let prev = token.next_token();
        
        assert_eq!(prev.start, 20);
        assert_eq!(prev.direction, PaginationDirection::Backward);
    }

    #[test]
    fn test_paged_result_bidirectional() {
        let items = vec![1, 2, 3, 4, 5];
        let result = PagedResult::from_vec_bidirectional(
            items, 
            20, 
            5, 
            "cursor".to_string(),
            Some(100),
        );
        
        assert_eq!(result.len(), 5);
        assert!(result.can_paginate_forward());
        assert!(result.can_paginate_backward());
    }

    #[test]
    fn test_pagination_state_forward() {
        let mut state = PaginationState::first_page("cursor".to_string(), 20);
        
        assert_eq!(state.page_count(), 0);
        
        let token1 = state.next_forward();
        assert!(token1.is_some());
        assert_eq!(state.page_count(), 1);
        
        let token2 = state.next_forward();
        assert!(token2.is_some());
        assert_eq!(state.page_count(), 2);
        
        assert!(state.can_go_back());
    }

    #[test]
    fn test_pagination_state_backward() {
        let mut state = PaginationState::first_page("cursor".to_string(), 20);
        state.next_forward();
        
        let backward_token = state.next_backward();
        assert!(backward_token.is_some());
    }

    #[test]
    fn test_pagination_state_go_back() {
        let mut state = PaginationState::first_page("cursor".to_string(), 20);
        state.next_forward();
        state.next_forward();
        
        assert!(state.can_go_back());
        assert!(state.go_back().is_some());
        assert_eq!(state.page_count(), 2);
    }

    #[test]
    fn test_pagination_token_staleness() {
        let token = PaginationToken::forward("cursor".to_string(), 0, 20);
        assert!(!token.is_stale());
    }
}
