# Directory Structure Audit

> **审计日期**: 2026-06-08  
> **审计范围**: `F:\linda0a\ww\social-app-ios`  
> **参考基准**: ARCHITECTURE_OPTIMIZATION.md 定义的优化方案

---

## 一、顶层目录结构

```
F:\linda0a\ww\social-app-ios\
├── .gitignore
├── Package.swift
├── project.yml
├── README.md
├── docs/                          ← 文档集中目录
│   ├── APP_DESIGN.md
│   ├── ARCHITECTURE_OPTIMIZATION.md
│   ├── EXECUTION_REPORT.md
│   ├── GAP_ANALYSIS.md
│   └── directory-structure.md     ← 本文件
├── Generated/                     ← 自动生成代码 (3 文件)
│   ├── matrix_sdk_ffi.swift
│   ├── matrix_sdk_ffiFFI.h
│   └── matrix_sdk_ffiFFI.modulemap
├── SocialApp/                     ← 主工程代码 (101 文件)
│   ├── App/                       (2 文件: AppContainer.swift, SocialApp.swift)
│   ├── Core/                      (4 子域, 6 文件)
│   ├── Models/                    (3 文件)
│   ├── Resources/                 (3 子域, 空目录待填充)
│   ├── Services/                  (7 子域, 25 文件)
│   ├── ViewModels/                (11 子域, 24 文件)
│   └── Views/                     (12 子域, 41 文件)
├── UITests/                       (空目录)
└── UnitTests/                     (空目录)
```

---

## 二、五大核心领域逐项明细

### 2.1 Services — 7 个子领域 (25 文件)

| 子领域 | 文件数 | 文件清单 |
|--------|--------|---------|
| Auth | 2 | AccountSettingsService.swift, QRLoginService.swift |
| Social | 2 | FriendService.swift, SocialFeedService.swift |
| Messaging | 6 | MessageService.swift, MessageSearchService.swift, ReactionService.swift, ReadReceiptService.swift, ThreadService.swift, RateLimiter.swift |
| Spaces | 3 | SpacesService.swift, RoomListService.swift, RoomDirectoryService.swift |
| Location | 2 | LiveLocationService.swift, LocationShareService.swift |
| Settings | 4 | NotificationSettingsService.swift, PrivacySettingsService.swift, SecuritySettingsService.swift, StorageSettingsService.swift |
| Infrastructure | 6 | AggregationCache.swift, ImageUploadService.swift, KeychainManager.swift, MediaProcessor.swift, PollService.swift, ProfileCache.swift |

### 2.2 ViewModels — 11 个子领域 (24 文件)

| 子领域 | 文件数 | 文件清单 |
|--------|--------|---------|
| Auth | 2 | AccountSettingsViewModel.swift, QRLoginViewModel.swift |
| Chat | 4 | CallViewModel.swift, ConversationViewModel.swift, MessageSearchViewModel.swift, ThreadViewModel.swift |
| Contacts | 1 | ContactsViewModel.swift |
| Discover | 1 | DiscoverViewModel.swift |
| Feed | 2 | FeedViewModel.swift, SpaceFeedViewModel.swift |
| Location | 2 | LiveLocationViewModel.swift, LocationShareViewModel.swift |
| Profile | 1 | ProfileViewModel.swift |
| Rooms | 2 | RoomDirectoryViewModel.swift, RoomListViewModel.swift |
| Settings | 5 | NotificationSettingsViewModel.swift, PrivacySettingsViewModel.swift, SecuritySettingsViewModel.swift, SettingsViewModel.swift, StorageSettingsViewModel.swift |
| Social | 3 | AddFriendViewModel.swift, PollViewModel.swift, ReactionViewModel.swift |
| Spaces | 1 | SpacesViewModel.swift |

> ViewModels(11) 镜像 Views(12)，不含 Components 是正确的 — 可复用 UI 组件不需要独立 ViewModel。

### 2.3 Views — 12 个子领域 (41 文件)

| 子领域 | 文件数 | 文件清单 |
|--------|--------|---------|
| Auth | 2 | AccountSettingsView.swift, QRLoginView.swift |
| Chat | 6 | CallView.swift, ChatDetailView.swift, ChatListView.swift, IncomingCallView.swift, MessageSearchView.swift, ThreadView.swift |
| Contacts | 3 | AddFriendView.swift, ContactsView.swift, FriendRequestView.swift |
| Discover | 1 | DiscoverView.swift |
| Feed | 5 | CommentSheet.swift, FeedView.swift, ForwardSheet.swift, MomentCard.swift, PostSheet.swift |
| Location | 2 | LiveLocationView.swift, LocationShareView.swift |
| Profile | 4 | EditProfileSheet.swift, FollowingListView.swift, MyMomentsView.swift, ProfileView.swift |
| Rooms | 2 | RoomDirectoryView.swift, RoomListView.swift |
| Settings | 5 | NotificationSettingsView.swift, PrivacySettingsView.swift, SecuritySettingsView.swift, SettingsView.swift, StorageSettingsView.swift |
| Social | 2 | PollView.swift, ReactionView.swift |
| Spaces | 1 | SpacesView.swift |
| Components | 8 | AsyncImageGrid.swift, AvatarView.swift, FilterSheet.swift, MediaPicker.swift, MediaSettingsView.swift, MomentDetailView.swift, ReadReceiptView.swift, TypingIndicator.swift |

### 2.4 Models — 仅纯数据模型 (3 文件)

| 文件 | 字段 | 说明 |
|------|------|------|
| Friend.swift | — | 好友数据模型 |
| Moment.swift | 10 字段 | 含 forwardCount, eventId |
| UserProfile.swift | 10 字段 | 含 feedRoomId, followerCount |

### 2.5 Core — 4 个子领域 (6 文件)

| 子领域 | 文件数 | 文件清单 |
|--------|--------|---------|
| Configuration | 1 | Config.swift |
| Types | 1 | AppTypes.swift |
| Errors | 1 | SocialFeedError.swift |
| Utilities | 3 | ImageUtils.swift, TextUtils.swift, Validators.swift |

---

## 三、扁平化改进项验证

| # | 验证项 | 结果 | 详情 |
|---|--------|------|------|
| 1 | Services 按领域拆分 | ✅ | 7 子领域全部就位: Auth / Social / Messaging / Spaces / Location / Settings / Infrastructure |
| 2 | ViewModels 按领域拆分 | ✅ | 11 子领域全部就位，镜像 Views 分组 (不含 Components) |
| 3 | Views 分组补全 | ✅ | 12 分组全部就位: Auth / Chat / Contacts / Discover / Feed / Location / Profile / Rooms / Settings / Social / Spaces / Components |
| 4 | 非 Model 文件迁入 Core | ✅ | Models 仅含 3 个纯数据模型; Configuration / Types / Errors / Utilities 均在 Core 下 |
| 5 | Resources 目录就位 | ✅ | Fonts / Localizations / Plists 三级目录已创建 (待填充资源文件) |
| 6 | 根目录文档归入 docs | ✅ | 5 份 .md 文档均在 docs/ 下; 根目录仅剩工程配置文件 + README.md |

---

## 四、统计总览

| 领域 | 子域数 | 文件数 |
|------|--------|--------|
| App | — | 2 |
| Core | 4 | 6 |
| Models | — | 3 |
| Resources | 3 | 0 |
| Services | 7 | 25 |
| ViewModels | 11 | 24 |
| Views | 12 | 41 |
| **SocialApp 合计** | | **101** |

| 顶层 | 文件数 |
|------|--------|
| docs | 5 |
| Generated | 3 |
| SocialApp | 101 |
| UITests | 0 |
| UnitTests | 0 |
| 根目录散文件 | 4 |
| **总计** | **113** |

---

## 五、结论

架构优化方案已全面落地。五大扁平化改进项全部验证通过：

- Services / ViewModels 按领域拆分完毕，层级清晰
- Views 分组完整覆盖，含 Components 可复用组件
- Core 集中管理所有非 Model 工具类文件
- Resources 目录结构就位
- 文档集中至 docs/ 目录

当前目录结构已从早期扁平化状态重构为多层、分域的专业工程结构。