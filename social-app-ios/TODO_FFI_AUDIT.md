---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 962bf721db6534c0bb69c381149ce2ef_b0b318ae638d11f19fb15254006c9bbf
    ReservedCode1: yJq8sVMBGFvKYsawx73lY0OBBSI/64nM16KxLrPp1aEhkUFCSPFeG8rUuz52BWPkzj9O0OyPPsakHM6W0GcPV1lct5iHvig7ca/25zyENwAouVUb/LUfZ55ioW4NuXaU/wmrA14uMH1cXwblYXqtA/Irlryj1RnfkmUaWHScMLuhr4w7BnwHLAoAgDg=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 962bf721db6534c0bb69c381149ce2ef_b0b318ae638d11f19fb15254006c9bbf
    ReservedCode2: yJq8sVMBGFvKYsawx73lY0OBBSI/64nM16KxLrPp1aEhkUFCSPFeG8rUuz52BWPkzj9O0OyPPsakHM6W0GcPV1lct5iHvig7ca/25zyENwAouVUb/LUfZ55ioW4NuXaU/wmrA14uMH1cXwblYXqtA/Irlryj1RnfkmUaWHScMLuhr4w7BnwHLAoAgDg=
---

# TODO FFI 审计报告 (更新版)

> 生成日期: 2026-06-09
> 更新日期: 2026-06-09 (认证补全复查 + Call 注释审查 + 回复筛选确认 + 统计刷新 + 图片上传压缩复查 + 附件选择器/转发复查)
> 项目路径: `F:\linda0a\ww\social-app-ios`

---

## 一、扫描概况

| 指标 | 数值 |
|------|------|
| 含 TODO 的文件数 | 21 个 |
| TODO 总数 | 92 处 |
| Generated (自动生成) | 60 处 (忽略) |
| 业务源码 TODO | 32 处 |
| FFI 相关 TODO | 24 处 (分布于 14 个文件) |
| 非 FFI TODO | 5 处 |

---

## 二、当前状态汇总

| 状态 | 数量 | 说明 |
|------|------|------|
| **已完成接入** | 40 | 原 26 项 + 认证模块 10 项 (A1-A10) + MomentDetailView 回复筛选 (C1) + QRLoginService 反向流程 |
| **Rust 侧全链路缺失** | 2 | Call/VoipCall 类型在 Rust 核心层 + FFI 绑定层均不存在，Swift 侧已添加详细注释标记 |
| **真实缺口 (FFI 未暴露)** | 0 | 所有可接入的 FFI 方法均已接入 |
| **非 FFI** | 5 | 应用层功能/UI TODO，不涉及 FFI 绑定 |

---

## 三、已完成接入项 (40 项，全部交叉验证通过)

### 3.1 Thread 模块 (4 项)

| # | 文件 | 接入内容 | FFI 签名 | completion_date |
|---|------|----------|----------|-----------------|
| 1 | `ThreadService.swift` | `room.threadListService().items()` | `threadListService() -> ThreadListService` / `items() -> [ThreadListItem]` | 2026-06-08 |
| 2 | `ThreadService.swift` | `tls.paginate()` | `ThreadListService.paginate() async throws` | 2026-06-08 |
| 3 | `ThreadViewModel.swift` | `loadThreads()`: tls.items() | `items() -> [ThreadListItem]`，`ProfileDetails.ready` 提取显示名/头像 | 2026-06-08 |
| 4 | `ThreadViewModel.swift` | `paginate()`: tls.paginate() + 去重合并 | `paginate() async throws` | 2026-06-08 |

### 3.2 Room 操作模块 (5 项)

| # | 文件 | 接入内容 | FFI 签名 | completion_date |
|---|------|----------|----------|-----------------|
| 5 | `RoomListViewModel.swift` | `leaveRoom()`: room.leave() | `Room.leave() async throws` | 2026-06-08 |
| 6 | `FriendRequestView.swift` | 拒绝邀请: room.leave() | `Room.leave() async throws` | 2026-06-08 |
| 7 | `RoomListViewModel.swift` | `markAsRead()`: sendReadReceipt + latestEventId | `sendReadReceipt(eventId:receiptType:)` + `latestEventId() -> String?` | 2026-06-08 |
| 8 | `ThreadViewModel.swift` | setThreadSubscription/subscribe/unsubscribe | `setThreadSubscription(threadRootEventId:subscribed:) async throws` | 2026-06-08 |
| 9 | `CallViewModel.swift` | declineCall + 属性 | `declineCall(rtcNotificationEventId:) async throws`；rtcNotificationEventId / callRoomId | 2026-06-08 |

### 3.3 消息交互模块 (3 项)

| # | 文件 | 接入内容 | FFI 签名 | completion_date |
|---|------|----------|----------|-----------------|
| 10 | `CallViewModel.swift` | rtcNotificationEventId / callRoomId 属性 | 供上游 RTC 通知填入 eventId / roomId | 2026-06-08 |
| 11 | `IncomingCallView.swift` | 使用 CallViewModel 属性 | 通过 CallViewModel 间接调用 declineCall | 2026-06-08 |
| 12 | `TypingIndicator.swift` | TypingNotificationListener 适配器 + subscribe | `TypingNotificationsListener` 协议 + `subscribeToTypingNotifications(listener:) -> TaskHandle` | 2026-06-08 |

### 3.4 Social 模块 (2 项)

| # | 文件 | 接入内容 | FFI 签名 | completion_date |
|---|------|----------|----------|-----------------|
| 13 | `MomentDetailView.swift` | 委托 SocialFeedService.comment() | 通过 SocialFeedService 间接调用 sendRaw | 2026-06-08 |
| 14 | `SocialFeedService.swift` | comment()/forward()/updateProfile 使用 sendRaw | `sendRaw(eventType:content:) async throws` | 2026-06-08 |

### 3.5 RoomListViewModel 追加 (3 项)

| # | 文件 | 接入内容 | FFI 签名 | completion_date |
|---|------|----------|----------|-----------------|
| 15 | `RoomListViewModel.swift` | `toggleFavourite()`: isFavourite 取反 | `RoomListItem.setIsFavourite(isFavourite:tagOrder:)` | 2026-06-08 |
| 16 | `RoomListViewModel.swift` | `toggleMute()`: .mute / .allMessages 互切 | `Client.setRoomNotificationMode(roomId:mode:)` | 2026-06-08 |
| 17 | `RoomListViewModel.swift` | `setLowPriority()`: isLowPriority 取反 | `RoomListItem.setIsLowPriority(isLowPriority:tagOrder:)` | 2026-06-08 |

### 3.6 ChatDetailView 编辑消息 (1 项)

| # | 文件 | 接入内容 | FFI 签名 | completion_date |
|---|------|----------|----------|-----------------|
| 18 | `ChatDetailView.swift` | 编辑已发送消息 | `messageEventContentFromMarkdown(md:)` + `Timeline.edit(eventOrTransactionId:newContent:)` | 2026-06-08 |

### 3.7 Spaces 模块 (7 项)

| # | 文件 | 接入内容 | FFI 签名 | completion_date |
|---|------|----------|----------|-----------------|
| 19 | `SpacesService.swift` | `inviteToSpace()` | `Room.inviteUserById(userId:)` + `RoomPowerLevels.canOwnUserInvite()` | 2026-06-08 |
| 20 | `SpacesService.swift` | `kickFromSpace()` | `Room.kickUser(userId:reason:)` + `RoomPowerLevels.canOwnUserKick()` | 2026-06-08 |
| 21 | `SpacesService.swift` | `listMembers()` | `Room.members()` + `RoomMembersIterator.nextChunk(chunkSize:)` | 2026-06-08 |
| 22 | `SpacesService.swift` | `memberCounts()` | `Room.joinedMembersCount()` / `Room.invitedMembersCount()` | 2026-06-08 |
| 23 | `SpacesService.swift` | `currentUserRole()` | `Room.ownUserId()` + `RoomMember.suggestedRoleForPowerLevel` | 2026-06-08 |
| 24 | `SpacesService.swift` | `joinSpace()` | `Room.join() async throws` | 2026-06-08 |
| 25 | `SpacesService.swift` | `leaveSpace()` | `Room.leave() async throws` | 2026-06-08 |

### 3.8 Client 注入通道 (1 项)

| # | 文件 | 接入内容 | FFI 签名 | completion_date |
|---|------|----------|----------|-----------------|
| 26 | `KeychainManager.swift` / `AuthManager.swift` / `SocialApp.swift` | Client 生命周期管理：`ClientSessionDelegate` ↔ iOS Keychain | `ClientBuilder.setSessionDelegate()` + `ClientSessionDelegate` | 2026-06-08 |

### 3.9 认证方法补全 — AuthManager.swift (8 项)

> 所有方法已通过 `matrix_sdk_ffi.swift` 逐签名交叉验证，17 个方法/实现参数类型、返回类型、async/throws 修饰均一致。

| # | 方法 | FFI 调用 | completion_date |
|---|------|----------|-----------------|
| 27 | `loginWithEmail(email:password:initialDeviceName:)` | `client.loginWithEmail(email:password:initialDeviceName:deviceId:)` | 2026-06-09 |
| 28 | `customLoginWithJwt(jwt:initialDeviceName:)` | `client.customLoginWithJwt(jwt:initialDeviceName:deviceId:)` | 2026-06-09 |
| 29 | `startSsoLogin(redirectUrl:idpId:)` → `SsoHandler` | `client.startSsoLogin(redirectUrl:idpId:)` | 2026-06-09 |
| 30 | `finishSsoLogin(handler:callbackUrl:)` | `handler.finish(callbackUrl:)` | 2026-06-09 |
| 31 | `urlForOauth(config:prompt:loginHint:)` | `client.urlForOauth(oauthConfiguration:prompt:loginHint:deviceId:additionalScopes:)` | 2026-06-09 |
| 32 | `loginWithOauthCallback(callbackUrl:)` | `client.loginWithOauthCallback(callbackUrl:)` | 2026-06-09 |
| 33 | `abortOauthAuth(authorizationData:)` | `client.abortOauthAuth(authorizationData:)` (async 非 throws) | 2026-06-09 |
| 34 | `getSession()` / `restoreSession(session:)` / `restoreSessionWith(session:roomLoadSettings:)` / `homeserverLoginDetails()` | 对应 FFI 方法逐一验证 | 2026-06-09 |

### 3.10 ClientBuilder 全量选项 (1 项)

| # | 参数 | FFI 来源 | completion_date |
|---|------|----------|-----------------|
| 35 | `passphrase` / `slidingSyncVersionBuilder` / `crossProcessLockConfig` / `useInMemoryStore` | `SqliteStoreBuilder.passphrase()` / `ClientBuilder.slidingSyncVersionBuilder()` / `ClientBuilder.crossProcessLockConfig()` / `ClientBuilder.inMemoryStore()` | 2026-06-09 |

### 3.11 QRLoginService 补全 (4 项)

| # | 方法 | FFI 流程 | completion_date |
|---|------|----------|-----------------|
| 36 | `startScanLogin(qrCodeData:oauthConfig:)` | `newLoginWithQrCodeHandler()` → `handler.scan(qrCodeData:progressListener:)` | 2026-06-09 |
| 37 | `startGrantLogin()` | `newGrantLoginWithQrCodeHandler()` → `handler.generate(progressListener:)` | 2026-06-09 |
| 38 | `startQrCodeGeneration(oauthConfig:)` | `newLoginWithQrCodeHandler()` → `handler.generate(progressListener:)` (服务端生成 QR) | 2026-06-09 |
| 39 | `startGrantScan(qrCodeData:)` | `newGrantLoginWithQrCodeHandler()` → `handler.scan(qrCodeData:progressListener:)` (已登录设备扫描) | 2026-06-09 |

### 3.12 MomentDetailView 回复筛选 (1 项)

| # | 文件 | 接入内容 | 方案 | completion_date |
|---|------|----------|------|-----------------|
| 40 | `SocialFeedService.swift` / `MomentDetailView.swift` / `Timeline+ReplyFiltering.swift` | `loadComments(feedRoomId:eventId:)` 加载评论 | Swift 侧本地过滤：`TimelineEventCollector`(NSLock) + `Timeline+ReplyFiltering.replies(to:)` | 2026-06-09 |

### 3.13 社交动态带图 (2 项)

| # | 文件 | 接入内容 | FFI 签名 | completion_date |
|---|------|----------|----------|-----------------|
| 41 | `ImageUploadService.swift` | `compressImage(at:)` — CGImageSource 等比缩放 + JPEG 重编码 | CGImageSource / CGImageDestination (系统 ImageIO 框架) | 2026-06-09 |
| 42 | `SocialFeedService.swift` | `postMoment(text:imageURLs:)` 接入 `ImageUploadService.uploadImages()` 并在 content JSON 嵌入 MXC URI 列表 | `client.uploadMedia(mimeType:data:)` → MXC URI → `room.sendRaw()` | 2026-06-09 |

---

## 四、Rust 侧全链路缺失 (2 项，Swift 侧已添加注释标记)

| # | 文件 | 缺失内容 | Swift 侧处理 |
|---|------|----------|-------------|
| B3 | `CallView.swift` | Call mute/unmute/speaker/hangup | 顶部 4 行说明注释 + 3 处按钮 `// TODO: Rust FFI 补全后接入真实通话控制` |
| B4 | `CallViewModel.swift` | CallService 整体接入 + VoipCall 实例 | 顶部 30 行 Rust FFI 状态说明注释 + 7 个方法 `// TODO: Rust FFI 补全后接入 → [FFI方法名]` |

**缺失的类型与 API**：`CallService` / `ElementCall` / `VoipCall` / 发起通话 / 接听 / 挂断 / 静音 / 扬声器 / WebRTC 引擎。仅 `Room.declineCall` / `VirtualElementCallWidget` 等被动级能力可用。

---

## 五、复查中修复的预存问题

### 问题 1: `sendRaw` 参数名错误
**文件**: `SocialFeedService.swift` — FFI 参数名为 `content`，修复前误用 `contentJson`。

### 问题 2: RoomListViewModel.markAsRead 使用不存在的 API
**文件**: `RoomListViewModel.swift:74` — 修复前用不存在的 `PaginationOptions`，修复后用 `latestEventId()`。

---

## 六、预存问题 

| 文件 | 行号 | 说明 |
|------|------|------|
| `PollService.swift` | 256 | 用不存在的 `PaginationOptions` 模式 |
| `MessageService.swift` | 97 | 消息分页加载用不存在的 API |
| `SocialFeedService.swift` | 117, 157 | Feed 分页加载用不存在的 API |

> 正确模式: `timeline.addListener(TimelineListener)` → `timeline.paginateBackwards(numEvents: N)` → 事件通过 `onUpdate(diff:)` 回调到达。

---

## 七、非 FFI TODO (5 项)

| # | 文件 | TODO 内容 |
|---|------|-----------|
| D4-6 | `SettingsViewModel.swift` | 导出用户数据 / 应用更新 / 问题反馈 |

---

## 八、统计变化

| 指标 | 更新前 | 更新后 | 变化 |
|------|--------|--------|------|
| 已完成接入 | 40 | 42 | **+2** |
| 真实缺口 (FFI 未暴露) | 0 | 0 | — |
| Rust 侧全链路缺失 | 2 | 2 | — |
| 需确认 | 0 | 0 | — |
| 预存问题 (待修复) | 3 | 3 | — |
| 非 FFI | 7 | 5 | -2 |

**+2 明细**: ImageUploadService 压缩实现 (`compressImage`) 1 项 + SocialFeedService 带图动态接入 (`postMoment` imageURLs → MXC URI) 1 项。

> A11 (ClientSessionDelegate) 和 A12 (logout) 在上一轮已计入 #26 和基础 AuthManager，不重复计数。

---

*报告结束*
*（内容由AI生成，仅供参考）*
