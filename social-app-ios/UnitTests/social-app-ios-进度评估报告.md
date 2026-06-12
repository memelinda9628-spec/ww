---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 962bf721db6534c0bb69c381149ce2ef_c4b2aad2641311f196be5254006c9bbf
    ReservedCode1: kNmi7jwvOK+/AbIIgUre7Tyk/iJFRi8ZXQPyA2E9ZQ6BQOZaApIWJ7F6qea3GsM7I6K2ZNz4/NLCrBimIFgPVR65xCgV3EMBzd1WzbqHbY4YMlKzk+91IZ/9MmZQsuBIw71CuRMIK2EH51y+qEivE3R1ZEQSpk4KyAbiSR8Ba6z3VjXS7hIW77JuTR0=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 962bf721db6534c0bb69c381149ce2ef_c4b2aad2641311f196be5254006c9bbf
    ReservedCode2: kNmi7jwvOK+/AbIIgUre7Tyk/iJFRi8ZXQPyA2E9ZQ6BQOZaApIWJ7F6qea3GsM7I6K2ZNz4/NLCrBimIFgPVR65xCgV3EMBzd1WzbqHbY4YMlKzk+91IZ/9MmZQsuBIw71CuRMIK2EH51y+qEivE3R1ZEQSpk4KyAbiSR8Ba6z3VjXS7hIW77JuTR0=
---

# social-app-ios 项目完成进度评估报告

> **评估日期**：2026-06-09
> **评估方法**：以实际源文件内容为准，不依赖文档自述。交叉验证了代码、FFI 绑定、TODO 标记、Mock 数据以及 Rust SDK 能力边界。
> **数据基础**：107 个手写 Swift 源文件（约 13,200 行），6 个 auto-generated UniFFI 绑定文件（约 55,000 行）。

---

## 一、项目概览

| 维度 | 数值 |
|------|------|
| 手写 Swift 文件数 | 107 |
| 手写代码总行数 | ~13,200 |
| Auto-generated 文件（UniFFI） | 6 文件 / 55,462 行 |
| 子模块数 | App、Core(6)、Models(3)、Services(8个目录~25文件)、ViewModels(~25)、Views(~30+) |
| 代码 TODO 标记 | **仅 1 处**（SocialApp.swift:88，LoginView 占位） |
| 含 loadMockData 的服务 | 6 个 |
| 零覆盖的测试 | UITests/、UnitTests/ 均为空目录 |

---

## 二、模块完成度矩阵

### 2.1 认证模块

| 子项 | 状态 | 说明 |
|------|------|------|
| AuthManager（15 个方法） | **已完成** | 全部接入真实 FFI：login/SSO/OAuth/QR/restoreSession/homeserverLoginDetails 等 |
| QRLoginService | **已完成** | 扫码 + 授权双模式，全部接入 FFI |
| ClientBuilder（12 个选项） | **已完成** | passphrase/slidingSync/inMemoryStore 等 |
| KeychainManager | **已完成** | 安全存储 + Client 生命周期管理 |
| **LoginView（登录界面）** | **未开始** | `SocialApp.swift:88` 处 `// TODO: 连接真实 LoginView`，AuthGateView 仅有 Homeserver URL 输入框，登录按钮无实际动作 |

> **认证模块总体进度：约 85%**（后端完成，前端缺失 LoginView）

### 2.2 社交动态 (Social Feed)

| 子项 | 状态 | 说明 |
|------|------|------|
| SocialFeedService（全部方法） | **已完成** | 全部替换为真实 FFI：createProfile/fetchMyProfile/postMoment/timeline/like/comment/follow/unfollow/forward/search |
| FeedViewModel + FeedView | **已完成** | 信息流列表 + 下拉刷新 |
| MomentCard / PostSheet / CommentSheet / ForwardSheet | **已完成** | 动态卡片 + 发布/评论/转发弹窗 |
| DiscoverView + DiscoverViewModel | **已完成** | 搜索/过滤/排序 |
| ProfileView + EditProfileSheet + MyMomentsView | **已完成** | 个人主页 + 编辑 + 动态列表 |
| MomentDetailView + 回复筛选 | **已完成** | Swift 本地过滤替代方案 |
| ImageUploadService + 压缩 | **已完成** | CGImageSource 等比缩放 + uploadMedia FFI |
| AggregationCache / ProfileCache / RateLimiter | **已完成** | LRU+TTL 缓存 + 令牌桶限流 |
| SocialFeedError（22 variants） | **已完成** | 完整错误枚举 |

> **社交动态模块总体进度：约 95%**（核心功能完备，PaginationOptions 预存问题待修复）

### 2.3 好友与即时通讯

| 子项 | 状态 | 说明 |
|------|------|------|
| FriendService.fetchFriends | **已完成** | 接入 `client.getDmRooms()` |
| FriendService.searchFriends | **已完成** | 接入 `client.searchUsers()` |
| MessageService.fetchMessages | **已完成** | 接入 Timeline + paginateBackwards |
| MessageService.sendMessage | **已完成** | 接入 `room.sendRaw()` |
| MessageService.sendReaction | **已完成** | 接入 `room.timeline().toggleReaction()` |
| MessageService.sendAttachment | **已完成** | `uploadMedia` → mxc URI → `sendRaw` |
| MessageService.markAsRead | **已完成** | 接入 `room.timeline().markAsRead()` |
| ConversationViewModel + ChatListView + ChatDetailView | **已完成** | 会话列表 + 聊天详情 |
| ContactsView + AddFriendView + FriendRequestView | **已完成** | 联系人 + 添加好友 + 好友请求 |
| AvatarView / TypingIndicator | **已完成** | 头像组件 + typing 通知 |
| **Mock 数据残留** | **部分** | MessageService/FriendService 的 `loadMockData()` 为开发演示用硬编码数据，提供给 View 层渲染示例 |
| MediaPicker | **已完成** | PHPicker SwiftUI 桥接 |

> **好友与即时通讯总体进度：约 85%**（后端 FFI 调用完备，前端界面完整，但 loadMockData 需在生产中移除）

### 2.4 Spaces / Threads / Polls

| 子项 | 状态 | 说明 |
|------|------|------|
| SpacesService.fetchSpaces | **已完成** | `spaceService.topLevelJoinedSpaces()` |
| SpacesService.fetchChildRooms | **已完成** | `spaceRoomList` + `paginate` |
| SpacesService.joinSpace / leaveSpace | **已完成** | `room.join()` / `spaceService.leaveSpace()` |
| SpacesService.invite / kick / listMembers | **已完成** | 权限检查 + FFI 调用 |
| **SpacesService.createSpace** | **Mock** | 注释标注 mock 实现，Rust `createSpace` FFI 未暴露 |
| ThreadService.fetchThreads | **已完成** | `room.threadListService().items()` |
| ThreadService.fetchReplies / sendReply | **Mock** | 本地数组操作，未接入 Timeline reply 关系 |
| ThreadService.paginate / subscribe | **已完成** | 接入真实 FFI |
| PollService.createPoll | **已完成** | `room.timeline().createPoll()` |
| PollService.fetchPolls / castVote / closePoll | **Mock** | fetchPolls 为 Task.sleep stub，castVote/closePoll 缺乏 pollStartId |
| SpacesView / ThreadView / PollView | **已完成** | 前端 UI 完整 |

> **Spaces/Threads/Polls 总体进度：约 70%**（核心 FFI 已接入，但 createSpace 为 mock，Thread replies 和 Poll 投票为本地状态模拟）

### 2.5 设置与偏好

| 子项 | 状态 | 说明 |
|------|------|------|
| AccountSettingsService（20 方法） | **已完成** | 全部接入 FFI |
| SecuritySettingsService（18 方法） | **已完成** | E2EE 备份/恢复/验证全部 FFI |
| NotificationSettingsService（16 方法） | **已完成** | Push rules + Pusher + 房间通知 |
| PrivacySettingsService（6 方法） | **已完成** | 忽略用户管理 |
| StorageSettingsService（11 方法） | **已完成** | 缓存清理/空间查询/优化 |
| SettingsViewModel + SettingsView | **已完成** | 设置主视图 |
| Account/Security/Notification/Privacy/Storage 各子 View | **已完成** | 完整设置页 |
| **exportData / checkForUpdates / reportProblem** | **Stub** | `SettingsViewModel` 中三个方法为 `// TODO` 空实现 |

> **设置与偏好总体进度：约 90%**（后端全部 FFI 接入，UI 完整，仅 3 个边缘功能未实现）

### 2.6 VoIP 通话

| 子项 | 状态 | 说明 |
|------|------|------|
| CallViewModel | **占位** | `callService = nil`，顶部 30 行注释说明 Rust 侧全链路缺失 |
| CallView | **占位** | WKWebView 外壳已搭建，但 mute/unmute/speaker/hangup 均为 TODO |
| IncomingCallView | **占位** | 接听/拒接按钮已绘制，但 `declineCall` 实际未完成集成 |

> **VoIP 通话模块：约 15%**（仅有 UI 骨架和 WKWebView 容器。根源在 Rust `matrix-rust-sdk` 核心层不包含 WebRTC 引擎，VoIP 依赖 Element Call Widget 体系，Swift 侧需等待 Rust FFI 补全 `CallService`/`VoipCall` 类型。当前 Rust 侧仅暴露被动级 API：`hasActiveRoomCall` / `declineCall` / `activeRoomCallParticipants`）

### 2.7 补充功能模块

| 子项 | 状态 | 说明 |
|------|------|------|
| MessageSearchService + View | **已完成** | `room.searchMessages` / `client.searchMessages` |
| RoomDirectoryService + View | **已完成** | `client.roomDirectorySearch()` |
| RoomListService + RoomListView | **已完成** | `roomListService.allRooms()` |
| LocationShareService + View | **已完成** | 原生 MapKit 替代 WebView |
| QRLoginView + ViewModel | **已完成** | 扫码 + 授权双 UI |

> **补充模块总体进度：约 90%**

---

## 三、Mock 数据现状

6 个 Service 文件中仍保留 `loadMockData()`，包含硬编码的演示数据：

| 文件 | Mock 数据用途 | 生产影响 |
|------|-------------|---------|
| `MessageService.swift` | 3 个聊天会话 + 示例消息 | 低：核心 FFI 方法完整，mock 仅填充初始数据 |
| `FriendService.swift` | 无 mock 数据本身（仅 loadMockData 在 init） | 极低 |
| `PollService.swift` | 无内容 mock（fetchPolls 为 stub） | 中：fetchPolls/castVote/closePoll 需接入 FFI |
| `ThreadService.swift` | 2 个 Thread + 3 个 Reply 示例 | 中：fetchReplies/sendReply 为本地操作 |
| `SpacesService.swift` | 3 个 Space 示例 | 低：核心方法已接入 FFI |
| `RoomListService.swift` | 房间列表示例 | 低：refreshRooms 已接入 FFI |

这些 Mock 数据是 `private init()` 中调用的，用于在未登录/无 Matrix 服务端时提供 UI 演示。生产环境下需替换为从 FFI 获取的真实数据。

---

## 四、测试覆盖

- **UnitTests/**：空目录，0 个测试文件
- **UITests/**：空目录，0 个测试文件

> **测试覆盖率：0%**

---

## 五、整体进度评估

| 模块 | 进度 | 权重 | 加权 |
|------|------|------|------|
| 认证 (Auth) | 85% | 15% | 12.75 |
| 社交动态 (Social Feed) | 95% | 20% | 19.0 |
| 好友与即时通讯 | 85% | 20% | 17.0 |
| Spaces / Threads / Polls | 70% | 15% | 10.5 |
| 设置与偏好 | 90% | 10% | 9.0 |
| VoIP 通话 | 15% | 10% | 1.5 |
| 补充模块 (搜索/房间目录/位置等) | 90% | 5% | 4.5 |
| 测试 | 0% | 5% | 0.0 |
| **整体加权进度** | | **100%** | **~74%** |

---

## 六、阻塞项与关键缺口

### 立即阻塞（Rust 侧）

1. **VoIP/CallService 全链路缺失**：Rust `matrix-rust-sdk` 不含 WebRTC 引擎，`CallService`/`VoipCall` 类型在 Rust 核心层 + FFI 层均不存在。仅被动级 API 可用。预计工作量：Rust 侧 2-3 周 + Swift 侧 1-2 周。

### 高优先级（Swift 侧）

2. **LoginView 未实现**：`SocialApp.swift` 中 `AuthGateView` 仅有 Homeserver URL 输入框，无用户名/密码/SSO 登录表单。`AuthManager` 后端已完备，纯 UI 工作。预计工作量：1-2 天。
3. **SpacesService.createSpace 为 Mock**：Rust `createSpace` FFI 未暴露。预计需 Rust 侧新增 FFI 绑定后 Swift 接入，总工作量约 1-2 天。
4. **PollService fetchPolls/castVote/closePoll 为 Stub**：缺少 `pollStartId` 获取能力。需从 Timeline 事件流中提取 poll start event ID。预计工作量：1-2 天。

### 中优先级

5. **Thread replies 为本地模拟**：`fetchReplies`/`sendReply` 不走真实 Timeline reply 关系，需接入 `m.in_reply_to` 事件链。
6. **Settings 边缘功能**：`exportData`/`checkForUpdates`/`reportProblem` 为 TODO 空 stub。
7. **测试完全缺失**：建议优先为 SocialFeedService 和 AuthManager 添加单元测试。

### 低优先级

8. **PaginationOptions 预存问题**：PollService（L256）、MessageService（L97）、SocialFeedService（L117/L157）使用不存在的 API 模式。
9. **移除 loadMockData**：发布前需移除 6 个 Service 中的 loadMockData() 调用。

---

## 七、总结

项目已完成约 **74%**。核心架构（DI 容器、UniFFI FFI 桥接、Module 划分）、社交动态全链路、认证后端、好友/通讯核心流、设置管理均已实现并接入真实 Rust FFI 绑定。主要缺口集中在：VoIP 通话（完全不可用）、LoginView 登录界面（后端完备但无前端）、Spaces 创建/Poll 投票/Thread 回复的剩余 mock 实现，以及完全缺失的测试覆盖。
*（内容由AI生成，仅供参考）*
