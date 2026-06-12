# Social App iOS

基于 Matrix 协议的社交应用 iOS 客户端，通过 UniFFI 桥接 matrix-rust-sdk。

## 工程结构

```
social-app-ios/
├── SocialApp/                  # 主应用源码 (101 个 Swift 文件)
│   ├── App/                    # @main 入口 + DI 容器
│   ├── Core/                   # 核心基础模块
│   │   ├── Configuration/      # Config.swift
│   │   ├── Errors/             # SocialFeedError.swift
│   │   ├── Types/              # AppTypes.swift
│   │   └── Utilities/          # ImageUtils / TextUtils / Validators
│   ├── Models/                 # Moment / Friend / UserProfile
│   ├── Services/               # 25 个业务服务 (7 个子模块)
│   │   ├── Auth/               # 认证：QRLogin / AccountSettings
│   │   ├── Infrastructure/     # 基础设施：Cache / ImageUpload / Keychain / Media / Poll / ProfileCache
│   │   ├── Location/           # 位置：LiveLocation / LocationShare
│   │   ├── Messaging/          # 消息：Message / MessageSearch / RateLimiter / Reaction / ReadReceipt / Thread
│   │   ├── Settings/           # 设置：Notification / Privacy / Security / Storage
│   │   ├── Social/             # 社交：Friend / SocialFeed
│   │   └── Spaces/             # 空间：RoomDirectory / RoomList / Spaces
│   ├── ViewModels/             # 24 个 ViewModel (11 个子模块)
│   │   ├── Auth/               # AccountSettings / QRLogin
│   │   ├── Chat/               # Call / Conversation / MessageSearch / Thread
│   │   ├── Contacts/           # Contacts
│   │   ├── Discover/           # Discover
│   │   ├── Feed/               # Feed / SpaceFeed
│   │   ├── Location/           # LiveLocation / LocationShare
│   │   ├── Profile/            # Profile
│   │   ├── Rooms/              # RoomDirectory / RoomList
│   │   ├── Settings/           # 5 个 Settings VM
│   │   ├── Social/             # AddFriend / Poll / Reaction
│   │   └── Spaces/             # Spaces
│   ├── Views/                  # SwiftUI 视图 (41 个, 12 个子模块)
│   │   ├── Auth/               # AccountSettings / QRLogin
│   │   ├── Chat/               # Call / ChatDetail / ChatList / IncomingCall / MessageSearch / Thread
│   │   ├── Components/         # 可复用组件：AsyncImageGrid / Avatar / FilterSheet / MediaPicker / MediaSettings / MomentDetail / ReadReceipt / TypingIndicator
│   │   ├── Contacts/           # AddFriend / Contacts / FriendRequest
│   │   ├── Discover/           # Discover
│   │   ├── Feed/               # CommentSheet / Feed / ForwardSheet / MomentCard / PostSheet
│   │   ├── Location/           # LiveLocation / LocationShare
│   │   ├── Profile/            # EditProfile / FollowingList / MyMoments / Profile
│   │   ├── Rooms/              # RoomDirectory / RoomList
│   │   ├── Settings/           # 5 个 Settings View
│   │   ├── Social/             # Poll / Reaction
│   │   └── Spaces/             # Spaces
│   ├── Resources/              # Fonts / Localizations / Plists
│   └── Generated/              # UniFFI 生成的 FFI 桥接层 (18 个文件)
│       ├── matrix_sdk.swift / .h / .modulemap
│       ├── matrix_sdk_base.swift / .h / .modulemap
│       ├── matrix_sdk_common.swift / .h / .modulemap
│       ├── matrix_sdk_crypto.swift / .h / .modulemap
│       ├── matrix_sdk_ffi.swift / .h / .modulemap
│       └── matrix_sdk_ui.swift / .h / .modulemap
├── UnitTests/
├── UITests/
├── docs/                       # 设计文档
│   ├── APP_DESIGN.md
│   ├── ARCHITECTURE_OPTIMIZATION.md
│   ├── compilation-fix-qrcodedata.md
│   ├── EXECUTION_REPORT.md
│   └── GAP_ANALYSIS.md
├── project.yml                 # XcodeGen 工程描述
├── Package.swift               # SPM 依赖声明
└── README.md
```

## 架构

```
Views/           ← SwiftUI 视图，只通过 @StateObject / @EnvironmentObject 持有 ViewModel
ViewModels/      ← @MainActor ObservableObject，翻译 Service → View 友好接口
Services/        ← 业务逻辑，按功能域分层（Auth / Messaging / Social / Settings / Spaces / Location / Infrastructure）
Core/            ← 基础类型、配置、错误定义、工具类
Models/          ← 纯数据模型：Moment / UserProfile / Friend
SocialApp/Generated/       ← UniFFI 自动生成的 Swift 桥接绑定（6 个 SDK 模块）
```

## 技术栈

- Swift 5.9+
- SwiftUI + MVVM
- XcodeGen (project.yml)
- SPM (Package.swift)
- matrix-rust-sdk (via UniFFI)

## 当前状态

- ✅ 架构整理完成：Core / Models / Services / ViewModels / Views 分层清晰
- ✅ Services 层按功能域拆分为 7 个子模块，职责明确
- ✅ Views 层 Components 子模块汇集 8 个可复用组件
- ✅ SocialFeedService 完整实现了 social-feed 的业务逻辑
- ✅ GitHub Actions CI 已配置（macOS runner, swift build + test）
- ✅ Generated/ UniFFI 绑定已正确归入 SPM target 编译范围
- ⚠️ Services 层当前使用 Mock 数据，待接入 UniFFI 生成的 FFI bindings

## CI/CD

- GitHub Actions 工作流：`.github/workflows/ios.yml`
- 每次 push main 自动触发 `swift build` + `swift test`
- 运行环境：`macos-latest` + Xcode

## 相关文档

- `docs/ARCHITECTURE_OPTIMIZATION.md` — 架构优化方案
- `docs/GAP_ANALYSIS.md` — Rust ↔ Swift 功能缺口分析
- `docs/EXECUTION_REPORT.md` — 执行报告
- `docs/APP_DESIGN.md` — 应用设计文档
- `docs/compilation-fix-qrcodedata.md` — QrCodeData 编译修复说明
