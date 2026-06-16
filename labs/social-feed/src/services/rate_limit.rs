//! 速率限制模块 [令牌桶 + 指数退避，供 core 层所有写操作入口调用]
//!
//! 实现客户端侧的速率限制和自适应退避重试机制。
//! 支持令牌桶算法和指数退避。

use std::{
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant},
};

use rand::Rng;
use tokio::sync::RwLock;

/// 速率限制配置
#[derive(Debug, Clone)]
pub struct RateLimitConfig {
    /// 每秒允许的请求数
    pub requests_per_second: f64,
    /// 令牌桶容量
    pub bucket_capacity: u32,
    /// 最大重试次数
    pub max_retries: u32,
    /// 初始退避延迟（毫秒）
    pub initial_backoff_ms: u64,
    /// 最大退避延迟（毫秒）
    pub max_backoff_ms: u64,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            requests_per_second: 10.0,
            bucket_capacity: 100,
            max_retries: 3,
            initial_backoff_ms: 100,
            max_backoff_ms: 30000, // 30 秒
        }
    }
}

/// 令牌桶速率限制器
#[derive(Debug)]
struct TokenBucket {
    /// 当前令牌数
    tokens: f64,
    /// 桶容量
    capacity: f64,
    /// 令牌生成速率（令牌/秒）
    refill_rate: f64,
    /// 上次补充时间
    last_refill: Instant,
}

impl TokenBucket {
    /// 创建新的令牌桶
    fn new(capacity: f64, refill_rate: f64) -> Self {
        Self { tokens: capacity, capacity, refill_rate, last_refill: Instant::now() }
    }

    /// 补充令牌
    fn refill(&mut self) {
        let now = Instant::now();
        let elapsed = now.duration_since(self.last_refill).as_secs_f64();
        self.tokens = (self.tokens + self.refill_rate * elapsed).min(self.capacity);
        self.last_refill = now;
    }

    /// 尝试消费令牌
    fn try_consume(&mut self, tokens: f64) -> bool {
        self.refill();
        if self.tokens >= tokens {
            self.tokens -= tokens;
            true
        } else {
            false
        }
    }

    /// 计算需要等待的时间（毫秒）
    fn wait_time_ms(&self) -> u64 {
        if self.tokens <= 0.0 {
            ((1.0 - self.tokens) / self.refill_rate * 1000.0) as u64
        } else {
            0
        }
    }
}

/// 操作类型（用于分别限制）
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum OperationType {
    /// 发布动态
    PostMoment,
    /// 点赞
    Like,
    /// 评论
    Comment,
    /// 转发
    Forward,
    /// 关注
    Follow,
    /// 其他
    Other,
}

/// 重试策略
#[derive(Debug, Clone)]
pub struct RetryPolicy {
    /// 当前重试次数
    pub attempt: u32,
    /// 下次重试的延迟（毫秒）
    pub next_backoff_ms: u64,
}

impl RetryPolicy {
    /// 创建新的重试策略
    pub fn new(config: &RateLimitConfig) -> Self {
        Self { attempt: 0, next_backoff_ms: config.initial_backoff_ms }
    }

    /// 计算下次重试的延迟（指数退避）
    pub fn calculate_backoff(&mut self, config: &RateLimitConfig) -> u64 {
        let backoff = self.next_backoff_ms;
        self.attempt += 1;

        // 指数退避：2^attempt * initial_backoff，加上随机抖动
        let next_backoff = ((config.initial_backoff_ms as u64) * (1u64 << self.attempt))
            .min(config.max_backoff_ms);

        // 添加 ±10% 的随机抖动
        let jitter = (next_backoff as f64 * 0.1) as u64;
        self.next_backoff_ms = next_backoff;

        let mut rng = rand::thread_rng();
        backoff + rng.gen_range(0..jitter.max(1))
    }

    /// 是否可以重试
    pub fn can_retry(&self, config: &RateLimitConfig) -> bool {
        self.attempt < config.max_retries
    }
}

/// 速率限制器
#[derive(Debug)]
pub struct RateLimiter {
    /// 配置
    config: RateLimitConfig,
    /// 操作类型 → 令牌桶
    buckets: Arc<RwLock<HashMap<OperationType, TokenBucket>>>,
    /// 操作类型 → 重试策略
    retry_policies: Arc<RwLock<HashMap<OperationType, RetryPolicy>>>,
}

impl RateLimiter {
    /// 创建新的速率限制器
    pub fn new(config: RateLimitConfig) -> Self {
        let mut buckets = HashMap::new();

        // 为不同操作类型创建令牌桶
        let op_types = vec![
            OperationType::PostMoment,
            OperationType::Like,
            OperationType::Comment,
            OperationType::Forward,
            OperationType::Follow,
            OperationType::Other,
        ];

        for op_type in op_types {
            buckets.insert(
                op_type,
                TokenBucket::new(config.bucket_capacity as f64, config.requests_per_second),
            );
        }

        Self {
            config,
            buckets: Arc::new(RwLock::new(buckets)),
            retry_policies: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// 检查是否允许操作
    pub async fn allow(&self, op_type: OperationType) -> Result<(), u64> {
        let mut buckets = self.buckets.write().await;
        if let Some(bucket) = buckets.get_mut(&op_type) {
            if bucket.try_consume(1.0) {
                Ok(())
            } else {
                Err(bucket.wait_time_ms())
            }
        } else {
            Ok(())
        }
    }

    /// 处理 homeserver 速率限制响应
    pub async fn handle_rate_limit(&self, op_type: OperationType, retry_after_ms: u64) {
        let mut policies = self.retry_policies.write().await;
        let policy = policies.entry(op_type).or_insert_with(|| RetryPolicy::new(&self.config));

        policy.next_backoff_ms = retry_after_ms;
    }

    /// 获取重试策略
    pub async fn get_retry_policy(&self, op_type: OperationType) -> RetryPolicy {
        let mut policies = self.retry_policies.write().await;
        policies.entry(op_type).or_insert_with(|| RetryPolicy::new(&self.config)).clone()
    }

    /// 重置操作类型的限制
    pub async fn reset(&self, op_type: OperationType) {
        let mut buckets = self.buckets.write().await;
        if let Some(bucket) = buckets.get_mut(&op_type) {
            *bucket = TokenBucket::new(
                self.config.bucket_capacity as f64,
                self.config.requests_per_second,
            );
        }

        let mut policies = self.retry_policies.write().await;
        policies.remove(&op_type);
    }

    /// 等待直到允许操作
    pub async fn wait_until_allowed(&self, op_type: OperationType) {
        loop {
            match self.allow(op_type).await {
                Ok(()) => break,
                Err(wait_ms) => {
                    tokio::time::sleep(Duration::from_millis(wait_ms)).await;
                }
            }
        }
    }
}

impl Default for RateLimiter {
    fn default() -> Self {
        Self::new(RateLimitConfig::default())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_rate_limiter_allow() {
        let config = RateLimitConfig {
            requests_per_second: 10.0,
            bucket_capacity: 10,
            ..Default::default()
        };
        let limiter = RateLimiter::new(config);

        // 前 10 个请求应该被允许
        for _ in 0..10 {
            assert!(limiter.allow(OperationType::PostMoment).await.is_ok());
        }

        // 第 11 个应该被拒绝
        assert!(limiter.allow(OperationType::PostMoment).await.is_err());
    }

    #[tokio::test]
    async fn test_retry_policy_backoff() {
        let config = RateLimitConfig::default();
        let mut policy = RetryPolicy::new(&config);

        assert_eq!(policy.attempt, 0);
        assert!(policy.can_retry(&config));

        policy.calculate_backoff(&config);
        assert_eq!(policy.attempt, 1);
    }

    #[tokio::test]
    async fn test_rate_limiter_reset() {
        let config = RateLimitConfig {
            requests_per_second: 10.0,
            bucket_capacity: 10,
            ..Default::default()
        };
        let limiter = RateLimiter::new(config);

        // 耗尽令牌
        for _ in 0..10 {
            let _ = limiter.allow(OperationType::Like).await;
        }

        assert!(limiter.allow(OperationType::Like).await.is_err());

        // 重置
        limiter.reset(OperationType::Like).await;
        assert!(limiter.allow(OperationType::Like).await.is_ok());
    }

    #[tokio::test]
    async fn test_handle_rate_limit() {
        let limiter = RateLimiter::default();
        limiter.handle_rate_limit(OperationType::Comment, 5000).await;

        let policy = limiter.get_retry_policy(OperationType::Comment).await;
        assert_eq!(policy.next_backoff_ms, 5000);
    }
}
