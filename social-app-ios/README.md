# Social App iOS

基于 Matrix 协议的社交应用 iOS 客户端，通过 [UniFFI](https://github.com/mozilla/uniffi-rs) 桥接 [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk)（v0.18.0）。

## 仓库结构

```
ww/                                  # 仓库根目录
├── .github/workflows/ios.yml        # GitHub Actions iOS CI
├── .gitignore
├── .gitmodules                       # matrix-rust-sdk 作为 Git submodule
├── FFI_CrossReference_Report.md      # FFI 绑定交叉比对报告 (2026-06-13)
├── matrix-rust-sdk/                  # Git submodule — Rust 工作空间
│   ├── crates/                       # matrix-sdk / matrix-sdk-base / crypto / ui / …
│   ├── bindings/matrix-sdk-ffi/      # UniFFI 导出层 (25 源文件, 105 导出注解)
│   ├── examples/                     # Rust 示例程序
│   ├── testing/                      # 集成测试与测试工具
│   ├── Cargo.toml                    # 工作空间配置 (rust-version 1.93)
│   └── …
└── social-app-ios/                   # iOS 客户端工程
    ├── Package.swift                  # SPM 依赖声明
    ├── project.yml                    # XcodeGen 工程描述
    ├── SocialApp/                     # 主应用源码 (113 个 Swift 文件)
    ├── MatrixFFI/                     # C 桥接层 (6 模块 × 3 文件 = 18 文件)
    ├── docs/                          # 设计文档 (9 份)
    ├── UnitTests/
    ├── UITests/
    └── README.md
```

## 工程结构

```
social-app-ios/
├── SocialApp/                  # 主应用源码 (113 个 Swift 文件)
│   ├── App/                    # @main 入口 + DI 容器
│   ├── Core/                   # 核心基础模块
│   │   ├── Configuration/      # Config.swift
│   │   ├── Errors/             # SocialFeedError.swift
│   │   ├── Types/              # AppTypes.swift
│   │   └── Utilities/          # ImageUtils / TextUtils / Validators / Timeline+ReplyFiltering / TimelineEventCollector
│   ├── Models/                 # Moment / Friend / UserProfile
│   ├── Services/               # 27 个业务服务 (7 个子模块)
│   │   ├── Auth/               # 认证：QRLogin / AccountSettings / AuthManager
│   │   ├── Infrastructure/     # 基础设施：Cache / ImageUpload / Keychain / Media / Poll / ProfileCache
│   │   ├── Location/           # 位置：LiveLocation / LocationShare
│   │   ├── Messaging/          # 消息：Message / MessageSearch / RateLimiter / Reaction / ReadReceipt / Thread
│   │   ├── Settings/           # 设置：Notification / Privacy / Security / Storage
│   │   ├── Social/             # 社交：Friend / SocialFeed
│   │   └── Spaces/             # 空间：RoomDirectory / RoomList / Spaces
│   ├── ViewModels/             # 25 个 ViewModel (11 个子模块)
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
│   ├── Views/                  # SwiftUI 视图 (42 个, 12 个子模块)
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
│   └── Generated/              # UniFFI 生成的 Swift 桥接层 (6 个文件)
│       ├── matrix_sdk.swift (2,530 行)       — OAuth 相关类型
│       ├── matrix_sdk_base.swift (920 行)     — 基础类型
│       ├── matrix_sdk_common.swift (735 行)   — 通用类型
│       ├── matrix_sdk_crypto.swift (1,853 行) — 加密类型
│       ├── matrix_sdk_ffi.swift (55,163 行)   — 主绑定 (402 struct / 130 enum / 55 protocol)
│       └── matrix_sdk_ui.swift (1,236 行)     — UI 层类型
├── MatrixFFI/                  # C 桥接层 (SPM targets)
│   ├── matrix_sdk/             # stub.c + FFI.h + module.modulemap
│   ├── matrix_sdk_base/        # stub.c + FFI.h + module.modulemap
│   ├── matrix_sdk_common/      # stub.c + FFI.h + module.modulemap
│   ├── matrix_sdk_crypto/      # stub.c + FFI.h + module.modulemap
│   ├── matrix_sdk_ffi/         # stub.c + FFI.h + module.modulemap
│   └── matrix_sdk_ui/          # stub.c + FFI.h + module.modulemap
├── UnitTests/
├── UITests/
├── docs/                       # 设计文档 (9 份)
│   ├── APP_DESIGN.md
│   ├── ARCHITECTURE_OPTIMIZATION.md
│   ├── compilation-fix-qrcodedata.md
│   ├── EXECUTION_REPORT.md
│   ├── FFI_Architecture_Analysis.md
│   ├── FFI_Audit_Report.md
│   ├── GAP_ANALYSIS.md
│   ├── LoginView-设计方案.md
│   ├── social-app-ios-设计系统报告.md
│   └── VoIP通话界面-设计方案.md
├── project.yml                 # XcodeGen 工程描述 (iOS 17.0, Swift 5.9)
├── Package.swift               # SPM 依赖声明 (6 个 FFI targets)
└── TODO_FFI_AUDIT.md           # FFI 接入审计报告 (2026-06-09)
```

## 架构

```
Views/           ← SwiftUI 视图，只通过 @StateObject / @EnvironmentObject 持有 ViewModel
ViewModels/      ← @MainActor ObservableObject，翻译 Service → View 友好接口
Services/        ← 业务逻辑，按功能域分层（Auth / Messaging / Social / Settings / Spaces / Location / Infrastructure）
Core/            ← 基础类型、配置、错误定义、工具类
Models/          ← 纯数据模型：Moment / UserProfile / Friend
Generated/       ← UniFFI 自动生成的 Swift 桥接 (6 个 SDK 模块, 共 ~62,000 行)
MatrixFFI/       ← C 桥接层，编译时链接 Rust 动态库
```

## 技术栈

- **语言**: Swift 5.9+
- **UI 框架**: SwiftUI + MVVM
- **工程生成**: XcodeGen (project.yml)
- **依赖管理**: Swift Package Manager (Package.swift)
- **FFI 桥接**: UniFFI 0.31.0 → 自动生成 Swift 绑定
- **Rust SDK**: matrix-rust-sdk v0.18.0 (rust-version 1.93)，作为 Git submodule 管理
- **测试**: XCTest (UnitTests + UITests)

## 当前状态

### FFI 接入

- ✅ **42 项已完成接入**：Threads、Room 操作、消息交互、Social 模块、Spaces（成员管理/权限）、认证（OAuth/SSO/JWT/QR/Email 全链路）、ClientSessionDelegate ↔ Keychain、图片压缩上传、社交动态带图
- ✅ FFI 交叉比对通过：Swift 绑定与 Rust 导出方法签名完全一致，核心模块匹配率 99%+
- ⚠️ Rust 侧全链路缺失 2 项：Call/VoipCall 通话控制（Rust 核心层 + FFI 绑定层均不存在），Swift 侧已添加详细注释标记
- ⚠️ Generated Swift 文件时效性风险：C 桥接层 `stub.c` 已更新 (2026-06-13)，但 Swift 绑定文件停留于 2026-06-08，需重新运行 UniFFI bindgen 同步
- ⚠️ 预存问题 3 项：PollService / MessageService / SocialFeedService 中存在使用不存在的 `PaginationOptions` 等 API 模式，需修复为正确的 `paginateBackwards` + `TimelineListener` 模式

### 架构与代码

- ✅ 架构整理完成：Core / Models / Services / ViewModels / Views 分层清晰
- ✅ Services 层按功能域拆分为 7 个子模块，职责明确
- ✅ Views 层 Components 子模块汇集 8 个可复用组件
- ✅ SocialFeedService 完整实现了 social-feed 的业务逻辑（发帖、评论、转发、动态带图）
- ✅ Core/Utilities 新增 Timeline+ReplyFiltering / TimelineEventCollector 本地过滤方案
- ⚠️ 3 项非 FFI 应用层功能 TODO：导出用户数据、应用更新、问题反馈

## 构建说明

### 前置条件

- macOS + Xcode 16+
- Rust 1.93+（用于编译 matrix-rust-sdk）
- UniFFI 0.31.0（用于重新生成 Swift 绑定）

### 重新生成 FFI 绑定

```bash
# 在 matrix-rust-sdk 目录下
cd ../matrix-rust-sdk
cargo build --release -p matrix-sdk-ffi --features uniffi

# 运行 UniFFI bindgen 生成 Swift 文件
uniffi-bindgen generate bindings/matrix-sdk-ffi/src/api.udl \
    --language swift \
    --out-dir ../social-app-ios/SocialApp/Generated/
```

### 编译与运行

```bash
# SPM 构建
cd social-app-ios
swift build

# 或通过 XcodeGen 生成 .xcodeproj 后 Xcode 打开
xcodegen generate
open SocialApp.xcodeproj
```

## CI/CD

- **配置文件**: `.github/workflows/ios.yml`
- **触发条件**: push / pull_request 到 main 分支
- **运行环境**: `macos-latest` + Xcode
- **步骤**: checkout (含 submodules) → `swift build --verbose` → `swift test --verbose`

## 相关文档

| 文档 | 说明 |
|------|------|
| `../FFI_CrossReference_Report.md` | Rust ↔ Swift FFI 绑定交叉比对报告 (2026-06-13) |
| `TODO_FFI_AUDIT.md` | FFI 接入审计报告，含 42 项已完成 + 2 项缺失 + 3 项预存问题 |
| `docs/ARCHITECTURE_OPTIMIZATION.md` | 架构优化方案 |
| `docs/GAP_ANALYSIS.md` | Rust ↔ Swift 功能缺口分析 |
| `docs/FFI_Architecture_Analysis.md` | FFI 架构分析 |
| `docs/FFI_Audit_Report.md` | FFI 审计报告 |
| `docs/EXECUTION_REPORT.md` | 执行报告 |
| `docs/APP_DESIGN.md` | 应用设计文档 |
| `docs/compilation-fix-qrcodedata.md` | QrCodeData 编译修复说明 |
| `docs/LoginView-设计方案.md` | 登录页设计方案 |
| `docs/social-app-ios-设计系统报告.md` | 设计系统报告 |
| `docs/VoIP通话界面-设计方案.md` | VoIP 通话界面方案 |
