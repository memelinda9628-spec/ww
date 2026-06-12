# Social App iOS — 界面与功能方案

## 1. 信息架构

`
TabBar
├── 信息流 (Feed)          # 首页，聚合关注者的动态
├── 发现 (Discover)        # 搜索用户 / 搜索动态
└── 我的 (Profile)         # 个人主页 + 设置
`

## 2. 页面清单与功能

### 2.1 信息流 (FeedTab)

| 页面 | 路由 | Rust 接口 | 功能 |
|------|------|-----------|------|
| 动态流 | FeedView | eed.timeline() | 拉取当前用户已加入 Room 的时间线聚合，按时间倒序 |
| 下拉刷新 | — | eed.timeline() | 重新拉取最新动态 |
| 发布动态 | PostSheet | eed.post_moment(text, image_urls) | 文字 + 多图，图片由调用方用 SDK 上传后传入 mxc URI |
| 动态卡片 | MomentCard | — | 展示头像、昵称、正文、图片网格、点赞/评论/转发数 |
| 点赞 | — | eed.like(moment_id) | 切换点赞状态 |
| 评论 | CommentSheet | eed.comment(moment_id, text) | 弹出评论输入框 |
| 转发 | ForwardSheet | eed.forward(room_id, moment, text) | 带引用原文的转发，附言可选 |
| 动态详情 | MomentDetailView | — | 完整动态内容 + 评论列表 |

### 2.2 发现 (DiscoverTab)

| 页面 | 路由 | Rust 接口 | 功能 |
|------|------|-----------|------|
| 搜索页 | SearchView | SearchEngine::search() | 关键词搜索已拉取的动态（客户端过滤） |
| 过滤面板 | FilterSheet | SearchFilter builder | 按作者/时间/点赞数/图片筛选 |
| 排序切换 | SortPicker | SearchEngine::sort() | 按热度/时间/点赞数/评论数排序 |
| 用户搜索 | UserSearchView | —（待实现） | 按 Matrix ID 查找用户 |

### 2.3 我的 (ProfileTab)

| 页面 | 路由 | Rust 接口 | 功能 |
|------|------|-----------|------|
| 个人主页 | ProfileView | eed.get_my_profile() | 显示头像、昵称、bio、location、动态数 |
| 编辑资料 | EditProfileSheet | eed.update_bio() / update_location() / set_avatar() | 修改头像（SDK 上传 + set_avatar）、bio、location |
| 我的动态 | MyMomentsView | 过滤 uthor_id == my_id | 自己发布过的动态列表 |
| 关注列表 | FollowingListView | eed.get_following() | 已关注用户的 Room ID 列表 |
| 关注 / 取关 | — | eed.follow() / eed.unfollow() | 从用户主页发起 |

## 3. 核心交互流程图

### 3.1 发布动态

`
[拍照/选图] → [SDK upload 获取 mxc URI] → [post_moment(text, &[uri])] → [刷新 Feed]
`

### 3.2 点赞

`
[点击 ❤️] → [feed.like(event_id)] → [本地更新 like_count +1]
`

### 3.3 关注用户

`
[进入对方主页] → [点击 关注] → [feed.follow(user_id, room_id)] → [join Room]
`

## 4. 数据流

`
┌─────────────┐     FFI (UniFFI/C-ABI)     ┌──────────────────┐
│  SwiftUI    │ ◄─────────────────────────► │  Rust social-feed │
│  MVVM 层    │                             │  (matrix-rust-sdk) │
└─────────────┘                             └──────────────────┘
      │                                              │
      │ @MainActor actor                            │
      │ SocialFeedService                            │ Matrix Homeserver
      │   .timeline()                                │
      │   .postMoment()                              │
      │   .like()                                    │
      │   .comment()                                 │
      │   ...                                        │
`

## 5. 技术选型

| 层 | 技术 |
|----|------|
| 声明式 UI | SwiftUI |
| 架构模式 | MVVM（@Observable / @Published） |
| 异步 | Swift Concurrency（sync/await） |
| 图片加载 | AsyncImage / Kingfisher |
| FFI 桥接 | UniFFI 生成 Swift bindings |
| 路由 | NavigationStack + NavigationPath |
| 依赖注入 | 手动注入 / Swinject |
| 测试 | XCTest + ViewInspector |

## 6. 文件规划

`
SocialApp/
├── App/
│   ├── SocialApp.swift              # @main 入口，TabView
│   └── AppContainer.swift           # 依赖注入容器
├── Views/
│   ├── Feed/
│   │   ├── FeedView.swift           # 信息流主页
│   │   ├── MomentCard.swift         # 动态卡片组件
│   │   ├── PostSheet.swift          # 发布动态弹窗
│   │   ├── CommentSheet.swift       # 评论输入弹窗
│   │   └── ForwardSheet.swift       # 转发弹窗
│   ├── Discover/
│   │   ├── DiscoverView.swift       # 发现页
│   │   └── FilterSheet.swift        # 过滤面板
│   ├── Profile/
│   │   ├── ProfileView.swift        # 个人主页
│   │   ├── EditProfileSheet.swift   # 编辑资料
│   │   ├── MyMomentsView.swift      # 我的动态
│   │   └── FollowingListView.swift  # 关注列表
│   └── Common/
│       ├── AsyncImageGrid.swift     # 图片网格
│       └── AvatarView.swift         # 头像组件
├── ViewModels/
│   ├── FeedViewModel.swift
│   ├── DiscoverViewModel.swift
│   └── ProfileViewModel.swift
├── Services/
│   ├── SocialFeedService.swift      # Rust FFI 桥接
│   └── ImageUploadService.swift     # SDK 图片上传封装
├── Models/
│   ├── Moment.swift                 # Moment 的 Swift 镜像
│   └── UserProfile.swift            # UserProfile 的 Swift 镜像
└── Resources/
    └── Assets.xcassets
`
