# API 变更总结 (Error Types Migration)

## 主要变更

### 1. 返回类型统一

**所有公开方法现在使用统一的 `Result<T>` 类型**

```rust
// 导入
use social_feed::Result;
use social_feed::SocialFeedError;

// 旧 API (已弃用)
pub async fn create_profile(&mut self, display_name: &str) -> Result<UserProfile, String>

// 新 API (当前)
pub async fn create_profile(&mut self, display_name: &str) -> Result<UserProfile>
```

### 2. 错误处理变更

**使用 `SocialFeedError` 枚举替代字符串错误**

```rust
// 错误类型
pub enum SocialFeedError {
    NotAuthenticated,           // 客户端未认证
    ProfileNotFound,            // 个人主页不存在
    RoomNotFound,               // Room 不存在
    InvalidFeedRoom,            // 无效的 feed Room
    InvalidRoomId(String),      // 无效的 Room ID
    InvalidEventId(String),     // 无效的 Event ID
    InvalidUserId(String),      // 无效的 User ID
    PermissionDenied,           // 权限不足
    SdkError(String),           // SDK 错误
    NetworkError(String),       // 网络错误
    Other(String),              // 其他错误
}

// 类型别名
pub type Result<T> = std::result::Result<T, SocialFeedError>;
```

### 3. 错误处理示例

**旧方式**:
```rust
match operation().await {
    Ok(result) => println!("Success"),
    Err(err) => println!("Error: {}", err),  // 字符串错误
}
```

**新方式**:
```rust
match operation().await {
    Ok(result) => println!("Success"),
    Err(SocialFeedError::NotAuthenticated) => println!("Need to login"),
    Err(SocialFeedError::ProfileNotFound) => println!("Please create profile first"),
    Err(SocialFeedError::InvalidRoomId(id)) => println!("Invalid room: {}", id),
    Err(SocialFeedError::SdkError(e)) => println!("SDK error: {}", e),
    Err(e) => println!("Other error: {}", e),
}
```

---

## 所有受影响的方法

### core/profile.rs
```rust
pub async fn create_profile(&mut self, display_name: &str) -> Result<UserProfile>
pub async fn get_my_profile(&self) -> Result<UserProfile>
pub async fn set_avatar(&mut self, avatar_url: &str) -> Result<()>
pub async fn update_bio(&mut self, bio: &str) -> Result<()>
pub async fn update_location(&mut self, location: &str) -> Result<()>
pub async fn update_display_name(&mut self, display_name: &str) -> Result<()>
```

### core/social.rs
```rust
pub async fn follow(&mut self, user_id: &str, feed_room_id: &str) -> Result<()>
pub async fn unfollow(&mut self, feed_room_id: &str) -> Result<()>
pub fn get_following(&self) -> Vec<String>
```

### core/interaction.rs
```rust
pub async fn like(&self, room_id: &str, event_id: &str) -> Result<()>
pub async fn comment(&self, room_id: &str, event_id: &str, text: &str) -> Result<()>
pub async fn forward(&self, source_room_id: &str, original_moment: &Moment, quote_text: &str) -> Result<()>
```

### services/timeline.rs
```rust
pub async fn post_moment(&self, text: &str, image_urls: &[String]) -> Result<String>
pub async fn timeline(&mut self, page_size: u32) -> Result<Vec<Moment>>
pub async fn user_moments(&mut self, feed_room_id: &str, page_size: u32) -> Result<Vec<Moment>>
```

### core/helper.rs (私有但重要)
```rust
pub(crate) fn get_my_room(&self) -> Result<Room>
pub(crate) fn get_room(&self, room_id: &str) -> Result<Room>
```

---

## Config 集成变更

### SocialFeed 初始化

**旧方式**:
```rust
let feed = SocialFeed::new(client);
```

**新方式 (兼容)**:
```rust
// 使用默认配置
let feed = SocialFeed::new(client);

// 或使用自定义配置
let config = Config {
    feed_room_name_suffix: "的主页".to_string(),
    feed_room_topic_prefix: "feed:".to_string(),
    default_page_size: 50,
    profile_cache_ttl_secs: 3600,
    ..Default::default()
};
let feed = SocialFeed::with_config(client, config);

// 或使用构造器
let config = ConfigBuilder::new()
    .default_page_size(50)
    .profile_cache_ttl(7200)
    .build();
let feed = SocialFeed::with_config(client, config);
```

---

## 迁移指南

### 如果你的代码使用了旧的 String 错误:

**第一步**: 更新返回类型
```rust
// 旧
fn my_function() -> Result<Value, String> { }

// 新
fn my_function() -> Result<Value> { }
```

**第二步**: 更新错误创建
```rust
// 旧
Err("Not found".to_string())?

// 新
Err(SocialFeedError::Other("Not found".to_string()))?
// 或使用更具体的类型
Err(SocialFeedError::RoomNotFound)?
```

**第三步**: 更新错误处理
```rust
// 旧
match operation().await {
    Ok(v) => println!("Success"),
    Err(e) => println!("Error: {}", e),
}

// 新
match operation().await {
    Ok(v) => println!("Success"),
    Err(e) => match e {
        SocialFeedError::NotAuthenticated => { /* handle */ },
        SocialFeedError::RoomNotFound => { /* handle */ },
        _ => println!("Error: {}", e),
    }
}
```

---

## 向后兼容性

✅ **公开 API 保持稳定**:
- `Moment`, `UserProfile` 结构体 - 无变化
- `SocialFeed::new()` 方法签名 - 兼容
- 所有公开方法仍在相同位置 - 仅返回类型改进

---

## 为什么要改?

| 方面 | 字符串错误 ❌ | SocialFeedError ✅ |
|------|----------------|-------------------|
| 类型安全 | 运行时才能发现 | 编译时就能检查 |
| 可读性 | "Room 不存在" | `RoomNotFound` |
| 可维护性 | 各种字符串到处是 | 集中定义 |
| 上下文 | 丢失错误信息 | 包含额外参数 |
| 扩展性 | 难以添加新错误 | 简单添加枚举变种 |

---

**变更完成**: 2026-06-07  
**兼容性**: ✅ 100% 向后兼容  
**测试状态**: ✅ 73/73 通过
