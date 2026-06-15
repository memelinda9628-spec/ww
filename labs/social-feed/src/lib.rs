#![recursion_limit = "256"]
//! 动态流模块 (Social Feed)
//!
//! 基于 Matrix 协议 + matrix-rust-sdk 实现的社交动态功能封装。
//! 每个用户的个人主页 = 一个公开 Room，关注 = join Room，信息流 = 多 Room 时间线聚合。
//!
//! # 功能
//! - 个人主页创建 / 发动态（文字 + 图片）
//! - 关注 / 取关
//! - 信息流聚合（拉取并按时序合并）
//! - 点赞 (Reaction) / 评论 (Reply) / 转发 (Quote)
//! - 搜索和过滤
//! - 分页管理
//! - 缓存管理
//!
//! # 架构
//! - `types/`     — Moment / SocialFeedError / Config（零 SDK 依赖）
//! - `core/`      — SocialFeed + profile / social / interaction（业务入口）
//! - `services/`  — timeline / cache / aggregation / rate_limit / search / ...
//! - `utils/`     — validators / text / images（纯函数）
//!
//! # 依赖
//! matrix-rust-sdk (Apache 2.0)
//!
//! # 测试
//! 运行单元测试：
//! ```shell
//! cargo test -p social-feed
//! ```
//!
//! 注意：由于 matrix-sdk 需要实际的服务器连接，部分测试需要通过集成测试环境运行。

// ── 子模块声明 ──

pub mod types;
mod core;
pub mod services;
pub mod utils;

#[cfg(test)]
mod tests;

// ── 公开 API 重导出 ──

pub use types::models::{Moment, UserProfile};
pub use core::feed::SocialFeed;
pub use types::error::{SocialFeedError, Result};
pub use types::config::{Config, ConfigBuilder};

