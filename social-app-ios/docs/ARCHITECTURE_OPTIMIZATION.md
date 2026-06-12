# Social App iOS — 架构优化方案

> 101 个 Swift 文件 · 审查日期 2026-06-08 · Mock 已清零

---

## ✅ 已完成

| # | 问题 | 操作 |
|---|------|------|
| 1 | SocialFeedError 重复定义 (Models + Services) | Services 版移入 Models/，删除 Services/ 副本 |
| 2 | AsyncImageGrid 重复 (Views + Views/Common) | 删除 Common/ 副本 |
| 3 | AvatarView 重复 (Views + Views/Common) | 删除 Common/ 副本 |
| 4 | Friend struct 放错层 (Services/) | 抽取到 Models/Friend.swift |
| 5 | SpaceFeedViewModel 放错层 (Services/) | 抽取到 ViewModels/SpaceFeedViewModel.swift |
| 6 | View 跨层引用 Service（6 处） | 全部修正，经 grep 验证 Service-refs=0 |
| — | 备份文件 (3个 _202*_*.swift) | 全部删除 |

---

## ⬜ 待完成

### 7. 工具文件 — 不存在，需新建

> 2026-06-08 审查：以下 3 个文件在 `SocialApp/Models/` 下不存在，EXECUTION_REPORT 的"已创建"记录有误。

| 文件 | 规划功能 | 优先级 |
|------|---------|--------|
| Models/ImageUtils.swift | extractAllImages() → SocialFeedService.fetchTimeline() | P2 |
| Models/TextUtils.swift | truncate/formatDuration → MomentCard | P3 |
| Models/Validators.swift | isValidUserId → AddFriendViewModel | P3 |

### 8. project.yml / Package.swift

- ✅ `Generated/` 源码路径已在 project.yml 中
- ⬜ 补测试 targets（`UnitTests/` 和 `UITests/` 目录存在但无测试文件）
- ⬜ Package.swift 缺 test target 定义

---

## Rust FFI 绑定现状

> 记录日期：2026-06-08  
> 所有 bindings 位于 `matrix-rust-sdk/bindings/matrix-sdk-ffi/`

### 已暴露的关键 FFI 方法

| FFI 方法 | Rust 位置 | Swift 签名（Generated） | 说明 |
|----------|----------|------------------------|------|
| `create_dm` | `client.rs:1624` | `createDm(userId: String) async throws -> Room` | 创建 DM 房间，返回 `Arc<Room>` |
| `send_attachment` | `room/mod.rs:453` | `sendAttachment(filename: String, mimeType: String, data: Data, caption: String?) async throws` | 上传并发送附件，含 MIME 校验 |
| `change_password` | `client.rs:1649` | `changePassword(newPassword: String, authData: AuthData?) async throws` | 修改密码，`auth` 按值传递 |

### 仍缺失的 FFI 方法（需后续补齐）

| 方法 | 核心位置 | 优先级 | 用途 |
|------|---------|--------|------|
| `get_3pids` | `account.rs` | P1 | 查看已绑定邮箱/手机 |
| `add_3pid` | `account.rs` | P1 | 绑定邮箱/手机 |
| `delete_3pid` | `account.rs` | P1 | 解绑 |
| `request_3pid_email_token` | `account.rs` | P1 | 请求邮箱验证令牌 |
| `request_3pid_msisdn_token` | `account.rs` | P1 | 请求手机验证令牌 |
| `import_export_keys` | `encryption.rs` | P2 | 导入/导出加密密钥 |
| `cross_signing_reset` | `encryption.rs:624` | P2 | 重置交叉签名密钥（#[uniffi::export] 已标注但需验证） |

---

## Generated/ 目录结构

```
social-app-ios/
└── Generated/
    ├── matrix_sdk_ffi.swift          (1.71 MB)  UniFFI 生成的 Swift 绑定
    ├── matrix_sdk_ffiFFI.h           (C 头文件，供 Swift 调用 Rust FFI)
    └── matrix_sdk_ffiFFI.modulemap   (模块映射，定义 Swift 导入路径)
```

### 关键约束

- `matrix_sdk_ffi.swift` 由 `uniffi-bindgen generate` 自动生成，**严禁手动编辑**
- 重新生成方式：
  ```bash
  uniffi-bindgen generate \
    matrix-sdk-ffi/src/matrix_sdk_ffi.udl \
    --language swift \
    --out-dir social-app-ios/Generated/
  ```
- 每次 `cargo build` 后如新增/修改 FFI 方法，**必须**重新运行上述命令以更新 Swift 绑定

---

## 编译命令与流程

### 矩阵联动编译（Rust → Swift）

```bash
# 1. 编译 Rust 侧 FFI 库（含全部 bindings）
cd matrix-rust-sdk
cargo build -p matrix-sdk-ffi --release
# 编译时长约 6m53s（release 模式）

# 2. 重新生成 Swift 绑定（如 FFI 有变更）
uniffi-bindgen generate \
  bindings/matrix-sdk-ffi/src/matrix_sdk_ffi.udl \
  --language swift \
  --out-dir ../social-app-ios/Generated/

# 3. Xcode 构建（需将 Generated/ 加入项目）
cd ../social-app-ios
xcodebuild -project SocialApp.xcodeproj -scheme SocialApp build
```

### project.yml / Package.swift 补充项

```
# project.yml 中补充
sources:
  - path: Generated/
    type: group
    compilerFlags:
      - -I$(SRCROOT)/Generated/

# 或 SPM Package.swift 中添加
.target(
    name: "SocialApp",
    dependencies: ["matrix_sdk_ffi"],
    path: "Generated/"
)
```

---

## Swift → Rust FFI 调用链路示例

### 1. 创建 DM 房间（好友关系）

```
Swift (FriendService)                     Rust FFI (Generated)                  Rust Core
─────────────────────                    ─────────────────────                 ──────────
createDmViaHttp(userId:)                 
  → URLSession POST /createRoom          (当前 HTTP 绕过方案)
  
  未来替换为：
  try await client.createDm(userId:)     → createDm(userId: String)            → Client::create_dm(user_id)
                                             → Arc<Room>                          → CreateRoomParameters { is_direct: true }
```

### 2. 发送图片附件

```
Swift (MessageService)                   Rust FFI (Generated)                  Rust Core
─────────────────────                   ─────────────────────                 ──────────
sendAttachment(fileName:mime:data:caption:)
  ① try await client.uploadMedia(        → uploadMedia(mimeType: Data)         → Client::upload_media()
       mimeType: mime, data: data)          → mxc URI (String)
  ② 构造 JSON body:
     {"msgtype":"m.image","url":mxcUri,
      "body":fileName,"filename":fileName}
  ③ try await room.sendRaw(              → sendRaw(eventType: String,          → Room::send_raw()
       eventType: "m.room.message",          jsonBody: String)
       jsonBody: jsonString)
```

### 3. 修改密码

```
Swift (AccountSettingsService)           Rust FFI (Generated)                  Rust Core
────────────────────────────────        ─────────────────────                 ──────────
changePassword(new:old:)
  try await client.changePassword(       → changePassword(                     → Account::change_password(
    newPassword: new,                       newPassword: String,                  new_password, old_password,
    authData: authData)                     authData: AuthData?)                 auth_data)
```

### 4. Typing 通知发送/订阅

```
Swift                                    Rust FFI (Generated)                  Rust Core
─────                                    ─────────────────────                 ──────────
// 发送"正在输入..."
room.typingNotice(true)                  → typing_notice(bool)                 → Room::typing_notice(true)

// 订阅对方的 typing 状态
room.subscribeToTypingNotifications(     → subscribe_to_typing_notifications() → Room::subscribe_to_typing_notifications()
    listener: TypingListener)
```

---

## 更新记录

| 日期 | 变更 | 作者 |
|------|------|------|
| 2026-06-08 | 新增：Rust FFI 绑定现状、Generated/ 目录结构、编译命令流程、Swift→Rust 调用链路示例 | Agent |
