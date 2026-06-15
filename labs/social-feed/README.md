# Social Feed (动态流模块)

基于 Matrix 协议 + matrix-rust-sdk (Apache 2.0) 实现的社交动态功能封装。

位于 `labs/social-feed/`，属于 matrix-rust-sdk 的实验性扩展。

## 设计理念

> 每个用户的个人主页 = 一个公开 Matrix Room

| 社交操作 | Matrix 协议映射 |
|---------|---------------|
| 注册 / 创建主页 | create_room (Public + topic:"feed:...") |
| 关注 | join_room_by_id |
| 取关 | leave |
| 发动态 | room.send(text) |
| 信息流 | 拉取关注 Room 的 Timeline，按时间合并排序 |
| 点赞 | reaction("👍") |
| 评论 | timeline.send_reply(text, event_id) |
| 转发 | 发到自己 Room 的 send_reply，引用原 event |

## API

```rust
use social_feed::{SocialFeed, Result, Config};

let mut feed = SocialFeed::new(client);

// 创建个人主页
let profile = feed.create_profile("小明").await?;

// 发动态（文字 + 可选图片链接）
feed.post_moment("今天天气真好！", &[]).await?;

// 关注好友
feed.follow("@alice:homeserver", "!abc123:homeserver").await?;

// 取关（直接用 Room ID）
feed.unfollow("!abc123:homeserver").await?;

// 拉取信息流（关注 + 自己，按时间倒序）
let timeline = feed.timeline(20).await?;

// 点赞
feed.like("!room:homeserver", "$event_id").await?;

// 评论（回复）
feed.comment("!room:homeserver", "$event_id", "说得对！").await?;

// 转发（附言 + 原文引用到自己主页，需传入源 Room 和原 Moment）
let original = Moment { ... };  // 从 timeline 中获取的原动态
feed.forward("!source_room:homeserver", &original, "转发 // 说得好").await?;

// 用户资料管理
feed.set_avatar("mxc://example.com/avatar").await?;
feed.update_bio("这是我的简介").await?;
feed.update_location("北京").await?;
feed.update_display_name("小明").await?;

// 使用自定义配置
let config = Config::default_config();
let feed = SocialFeed::with_config(client, config);
```

## 架构

```
types/     ← 纯数据，零 SDK 依赖     models / error / config
core/      ← 业务核心，有状态         feed / profile / social / interaction / helper
services/  ← 独立服务                timeline / cache / aggregation / rate_limit
                                    pagination / search / search_index
                                    quote_forward / media
utils/     ← 纯函数工具              validators / text / images
```

## 文件结构

```
labs/social-feed/
├── Cargo.toml
├── README.md
├── API_CHANGES.md
├── TESTING.md
└── src/
    ├── lib.rs
    ├── types/          # 3 文件
    ├── core/           # 5 文件
    ├── services/       # 9 文件
    ├── utils/          # 3 文件
    └── tests/          # 5 文件 + mod.rs (151 tests)
```

Workspace 中 `labs/*` 已自动注册，无需手动编辑根 Cargo.toml。

## 协议兼容性

- matrix-rust-sdk: Apache 2.0，可闭源商用
- 本模块: 与 SDK 协议保持一致

## 已知限制

- `comment_count` 当前为 0：需 SDK 暴露 `m.in_reply_to` 关系字段才能实现评论计数
- `UserProfile.avatar_url/following_count/moments_count` 尚未从 SDK 获取
- `pagination/search/search_index/media` 模块已独立实现，待接入主流程
- `utils/validators` 和 `utils/text` 中部分函数当前无调用者，预留供上层使用
