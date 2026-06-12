---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 962bf721db6534c0bb69c381149ce2ef_7f472f9065fc11f18b225254006c9bbf
    ReservedCode1: N49Yw0g3R28Slu1Sak4FEp3y13CQCa4+GKkJJFLs0LSDibp3YvQPo+QxQeT7dCsVRzP8bOtZUxpW1xmmtDZKQdbarmTaFwj37Ndx81R9sU0YvQ7gzPpLmxHTRhFVYcN7viWBbn3nEi3U3hj5njmIwSLq9nEnfGQesgoRAp6qnkeWP0n45Qfk30AkBIM=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 962bf721db6534c0bb69c381149ce2ef_7f472f9065fc11f18b225254006c9bbf
    ReservedCode2: N49Yw0g3R28Slu1Sak4FEp3y13CQCa4+GKkJJFLs0LSDibp3YvQPo+QxQeT7dCsVRzP8bOtZUxpW1xmmtDZKQdbarmTaFwj37Ndx81R9sU0YvQ7gzPpLmxHTRhFVYcN7viWBbn3nEi3U3hj5njmIwSLq9nEnfGQesgoRAp6qnkeWP0n45Qfk30AkBIM=
---

# social-app-ios 设计系统总结报告

> 评估日期：2026-06-12 | 评估方法：以实际 Swift 源代码为准，不依赖文档

---

## 1. 项目概览

| 维度 | 数值 |
|------|------|
| iOS 最低版本 | 17.0 |
| Swift 版本 | 5.9 |
| 手写 Swift 文件 | ~107 |
| UI 视图文件 | ~30+ |
| ViewModel 文件 | ~25 |
| 公共组件 | 10 个 |
| 自定义颜色资产 | **0**（无 Assets.xcassets 颜色） |
| 自定义字体 | **0**（Resources/Fonts 为空目录） |
| 设计系统/主题文件 | **无** |

---

## 2. 导航架构说明

### 2.1 入口与路由

```
SocialApp (App 入口)
 ├── isRestoring → ProgressView
 ├── !authManager.isAuthenticated → AuthGateView (占位)
 └── authManager.isAuthenticated → TabView
      ├── Tab 1: FeedView (NavigationStack)
      ├── Tab 2: DiscoverView (NavigationStack)
      └── Tab 3: ProfileView (NavigationStack)
```

### 2.2 导航模式

- **顶层导航**：`TabView` + 3 个 Tab
- **二级导航**：
  - `NavigationStack`：FeedView、DiscoverView、ProfileView、SpacesView
  - `NavigationView`（旧版 API）：SettingsView、QRLoginView、ChatListView、FilterSheet、EditProfileSheet、RoomDirectoryView
- **模态展示**：`.sheet`（PostSheet、CommentSheet、ForwardSheet、EditProfileSheet、FilterSheet、CreateSpaceSheet、IncomingCallView 等）
- **页面跳转**：`NavigationLink` 直接 push
- **Alert**：`.alert` / `.confirmationDialog`
- 无 Coordinator / Router 模式，无集中式路由定义文件

### 2.3 认证流程

```
SocialApp.attemptRestore()
  → KeychainManager 读取 homeserver URL
  → AuthManager.restoreSession()
  → 成功 → mainTabView
  → 失败 → AuthGateView (占位)

AuthGateView 当前状态：
  - 仅有 Homeserver URL 输入框 + "登录"按钮
  - 按钮无实际动作（// TODO: 连接真实 LoginView）
  - 无用户名/密码/SSO/OAuth 表单
```

---

## 3. 颜色体系

### 3.1 现状：零自定义颜色资产

`SocialApp/Resources/` 下仅有 3 个空子目录（Fonts、Localizations、Plists），**不存在** `.xcassets` 文件或任何颜色定义。项目中无任何 `Asset Catalog`、`Color Set` 或自定义颜色常量。

### 3.2 实际使用的色值（从代码中提取）

#### 主题/强调色
| 用途 | 代码写法 | 效果 |
|------|---------|------|
| 主色调 | `Color.blue` | 系统蓝色 |
| 强调色 | `Color.accentColor` | 随系统 accent |
| 发送按钮/链接 | `Color.blue` | 系统蓝色 |

#### 语义色
| 用途 | 代码写法 | 使用场景 |
|------|---------|---------|
| 成功/接听 | `Color.green` | IncomingCallView 接听按钮、QR 登录成功 |
| 错误/拒接/删除 | `Color.red` | 挂断按钮、拒接按钮、删除操作 |
| 警告 | `Color.orange` | QR 扫码状态、错误提示 |
| 紫色装饰 | `Color.purple` | SpaceCard 渐变、IncomingCallView 头像边框 |
| 粉色 | `Color.pink` | AvatarView 备用色 |
| 青色 | `Color.teal` | AvatarView 备用色 |
| 薄荷 | `Color.mint` | AvatarView 备用色 |

#### 文字色
| 用途 | 代码写法 |
|------|---------|
| 主文字 | `.foregroundColor(.primary)` |
| 次要文字 | `.foregroundColor(.secondary)` |
| 白色文字（深色背景） | `.foregroundColor(.white)` |
| 半透明白色 | `.foregroundColor(.white.opacity(0.7))` |

#### 背景色
| 用途 | 代码写法 |
|------|---------|
| 页面背景 | `Color(.systemBackground)` |
| 浅灰背景 | `Color(.systemGray5)` |
| 更浅灰背景 | `Color(.systemGray6)` |
| 黑色背景（通话） | `Color.black` |
| 半透明白色按钮 | `Color.white.opacity(0.15)` / `0.3` |
| 半透明蓝色高亮 | `Color.blue.opacity(0.08)` / `0.1` / `0.2` |
| 半透明红色标记 | `Color.red.opacity(0.1)` |
| 灰色卡片背景 | `Color.gray.opacity(0.08)` |

#### Material 效果
| 用途 | 代码写法 |
|------|---------|
| 通话状态栏背景 | `.ultraThinMaterial` |
| 底部操作栏背景 | `.regularMaterial` |

#### 渐变
| 用途 | 代码 |
|------|------|
| 来电界面背景 | `LinearGradient(colors: [Color(.systemGray6), Color(.systemBackground)], ...)` |
| 来电头像边框 | `LinearGradient(colors: [.blue, .purple], ...)` |
| 空间卡片渐变 | `LinearGradient(colors: [.blue.opacity(0.7), .purple.opacity(0.7)], ...)` |

### 3.3 结论

项目**完全依赖 SwiftUI 系统颜色**，无任何品牌色或设计规范定义。若需统一视觉风格，需新建 `Assets.xcassets` 并定义 Color Set。

---

## 4. 字体规范

### 4.1 现状：零自定义字体

`Resources/Fonts` 为空目录，无自定义字体注册。全部使用 SwiftUI 系统字体。

### 4.2 实际使用的字体规格（从代码中提取）

| 语义层级 | 代码写法 | 使用场景 |
|---------|---------|---------|
| 大标题 | `.font(.largeTitle)` | ReactionView 快捷回应表情 |
| 标题 | `.font(.title)` / `.font(.title2)` / `.font(.title3)` | IncomingCallView 姓名、ProfileView 昵称、SpaceCard 空间名 |
| 标题加粗 | `.font(.title2.weight(.semibold))` | ProfileView 用户名 |
| 标题加粗 | `.font(.title3.bold())` | QRLoginView 进度标题 |
| 大号图标字 | `.font(.system(size: 64))` / `48` / `40` | 空状态图标 |
| 标题 | `.font(.headline)` | 对话列表、ReactionView section 头 |
| 副标题 | `.font(.subheadline)` | 多处以次要信息展示 |
| 副标题加粗 | `.font(.subheadline.bold())` | LiveLocationView 用户 ID |
| 副标题等宽 | `.font(.subheadline.monospaced())` | QRLoginView URL 显示 |
| 正文 | `.font(.body)` | MomentCard 正文、ChatDetailView 消息正文 |
| 正文加粗 | `.font(.body.bold())` | FilterSheet 按钮 |
| 脚注 | `.font(.footnote)` | MomentCard 互动按钮、SettingsView |
| 说明文字 | `.font(.caption)` | 多处辅助信息 |
| 更小说明 | `.font(.caption2)` | MomentCard 时间、ChatDetailView 回复预览 |
| 等宽说明 | `.font(.caption.monospaced())` | 历史记录 GeoURI |
| 自定义大小 | `.font(.system(size: 28))` | IncomingCallView 按钮图标 |

### 4.3 字重使用

- `.bold()`：按钮标签、姓名、标题
- `.weight(.semibold)`：重要文字、作者名
- `.weight(.medium)`：AvatarView fallback 文字
- 默认 weight：正文、说明文字

### 4.4 结论

无 Typography/TextStyle 抽象层。字体使用为分散的 `.font()` 修饰符，建议定义 `Font+Extension` 或 `TextStyle` 枚举统一管理。

---

## 5. 间距/圆角规范

### 5.1 现状：无集中常量定义

所有间距和圆角值均为硬编码数字，无 `CGFloat` 常量或枚举。

### 5.2 实际使用的间距值

| 值 | 使用场景 |
|----|---------|
| 2 | VStack 标题间距、文本行间距、badge padding |
| 3 | HStack 点间距（TypingDotsView） |
| 4 | VStack 内间距、HStack 图标间距、cell padding |
| 6 | badge 水平 padding |
| 8 | HStack/VStack 常规间距、消息列表间距、AvatarView 间距、reaction padding |
| 10 | MomentCard VStack 间距、ReactionView section 间距 |
| 12 | ProfileView VStack 间距、消息列表水平 padding、输入栏 padding、ChatRoomRow spacing |
| 16 | 多处标准 padding、表单 section 间距、ReactionView 外间距、grid spacing |
| 20 | CallView 状态栏水平 padding |
| 24 | AuthGateView spacing、MomentCard 操作按钮间距、QRLoginView 内容间距 |
| 30 | CallView 底部控制 padding |
| 40 | IncomingCallView VStack spacing、ProfileView HStack spacing、CallView 底部按钮间距 |
| 60 | IncomingCallView 接听/拒接按钮间距 |

### 5.3 实际使用的圆角值

| 值 | 使用场景 |
|----|---------|
| 4 | LiveLocationView 地图标注、PollView 进度条 |
| 8 | AsyncImageGrid 图片、AvatarView（Circle 等效无限大）|
| 10 | ChatDetailView reaction 标签、ForwardSheet 搜索栏 |
| 12 | AsyncImageGrid 图片、LiveLocationView 地图、ReactionView 快捷按钮、SpaceCard 头像渐变 |
| 16 | ChatDetailView 消息气泡、RoomListView 卡片、SpaceCard 整卡、QRLoginView 授权码占位 |
| 20 | ChatDetailView 输入框、MomentDetailView |

### 5.4 裁剪形状

| 形状 | 使用场景 |
|------|---------|
| `Circle()` | 头像、通话按钮、来电按钮 |
| `Capsule()` | 通话状态栏、未读计数 badge、FriendRequestView 按钮 |
| `RoundedRectangle(cornerRadius:)` | 图片网格、reaction 按钮、空间卡片 |

---

## 6. 公共组件清单与使用模式

### 6.1 组件清单

| 组件名 | 文件 | Props | 使用场景 | 出现次数 |
|--------|------|-------|---------|---------|
| **AvatarView** | `Views/Components/AvatarView.swift` | `name`, `url?`, `size` | 头像（含 URL 异步加载 + 颜色 fallback） | 6+ |
| **MomentCard** | `Views/Feed/MomentCard.swift` | `moment`, `onLike`, `onComment`, `onForward` | 动态卡片 | 3+ |
| **ControlButton** | `Views/Chat/CallView.swift` (内联) | `icon`, `label`, `foregroundColor`, `backgroundColor`, `action` | 通话控制按钮 | 仅 CallView |
| **MessageBubbleView** | `Views/Chat/ChatDetailView.swift` (内联) | `message`, `onAction` | 聊天消息气泡 | 仅 ChatDetailView |
| **ChatRoomRow** | `Views/Chat/ChatListView.swift` (内联) | `room` | 聊天列表行 | 仅 ChatListView |
| **AsyncImageGrid** | `Views/Components/AsyncImageGrid.swift` | `urls` | 动态九宫格图片 | 2+ |
| **TypingIndicator** | `Views/Components/TypingIndicator.swift` | `typingUserIds` | 正在输入指示器 | 1 |
| **FilterSheet** | `Views/Components/FilterSheet.swift` | `isPresented`, `filter`, `onApply` | 高级过滤面板 | 1 |
| **ReadReceiptView** | `Views/Components/ReadReceiptView.swift` | — | 已读回执 | 1 |
| **MediaPicker** | `Views/Components/MediaPicker.swift` | — | 媒体选择器 | 1 |

### 6.2 组件提取现状

- **已独立成文件**：AvatarView、AsyncImageGrid、TypingIndicator、FilterSheet、ReadReceiptView、MediaPicker
- **内联在父文件中**：ControlButton（CallView.swift）、MessageBubbleView（ChatDetailView.swift）、ChatRoomRow（ChatListView.swift）
- **可提取但未提取**：SpaceCard（SpacesView.swift）、ForwardRoomPickerView（ChatDetailView.swift）

### 6.3 Button Style 使用

| Style | 使用场景 |
|-------|---------|
| `.buttonStyle(.borderedProminent)` | AuthGateView 登录、QRLoginView 确认 |
| `.buttonStyle(.bordered)` | LiveLocationView 开始共享、SpacesView 重试 |
| `.buttonStyle(.plain)` | MomentCard 点赞/评论/转发、ReactionView 切换、ChatRoomRow |
| 无显式 style | IncomingCallView 接听/拒接（直接 Circle 背景） |

---

## 7. 状态管理模式

### 7.1 模式总览

| 模式 | 使用场景 | 典型代码 |
|------|---------|---------|
| `@StateObject + ViewModel` | **主导模式**，几乎所有 View | `@StateObject private var vm = XXXViewModel()` |
| `@State` | 本地 UI 状态（输入文本、开关、sheet 控制） | `@State private var text = ""` |
| `@EnvironmentObject` | 仅在 AuthGateView 中注入 `AuthManager` | `.environmentObject(authManager)` |
| `@Environment(\.dismiss)` | Sheet 关闭 | `@Environment(\.dismiss) private var dismiss` |
| `@FocusState` | 输入焦点管理 | `@FocusState private var isInputFocused` |
| `@Binding` | 父子组件双向绑定 | `@Binding var isPresented: Bool` |
| `@ObservedObject` | 子组件观察父 ViewModel（ChangePasswordView、SpaceDetailView） | `@ObservedObject var viewModel: SettingsViewModel` |
| `@Published` | ViewModel 中暴露可观察属性 | `@Published var callState: CallState = .idle` |

### 7.2 依赖注入

- `AppContainer`（Service Locator 模式）管理所有 Service 单例
- ViewModel 通过 `AppContainer.shared.makeXXXViewModel()` 工厂创建
- 实际代码中，部分 View 直接 `@StateObject private var vm = XXXViewModel()` 自创建
- AuthManager 通过 `.environmentObject` 注入子视图

### 7.3 Task 异步模式

```swift
.task { await viewModel.fetchTimeline() }
.task { await viewModel.loadMessages() }
```

---

## 8. 现有 View 模式总结

### 8.1 列表/Feed 模式
- `List` + `.listStyle(.plain)` + `.listRowSeparator(.hidden)` 为 Feed 标准组合
- 配合 `.refreshable` 实现下拉刷新
- `ForEach` 遍历数据源

### 8.2 表单/设置模式
- `Form` + `Section` 为标准设置页模式
- 使用 `Toggle`、`Picker`、`Button`、`TextField`、`SecureField` 等
- SettingsView 是最大最完整的 Form 示例（296 行，6 个 Section）

### 8.3 Sheet 模态模式
- 统一使用 `NavigationStack` + `.toolbar` 取消/确认按钮
- `navigationBarTitleDisplayMode(.inline)`

### 8.4 空状态模式
- QRLoginView：条件分支 `@ViewBuilder`
- LiveLocationView：`emptyActiveState` 独立 computed property
- SpacesView：`ContentUnavailableView`（iOS 17+ API）

### 8.5 布局结构偏好
- VStack 为绝对主力容器
- HStack 用于水平排列（卡片头部、按钮行、输入栏）
- ZStack 用于叠加（通话界面、来电界面）
- GeometryReader 仅在 CallView 和 IncomingCallView 中使用（安全区域适配）
- LazyVStack 用于长消息列表（ChatDetailView）
- LazyVGrid 用于 ReactionView 和 SpacesView

---

## 9. 结论：缺失的设计基础设施

按优先级排列：

1. **无 Assets.xcassets 颜色定义** — 建议创建含 Primary/Secondary/Accent/Success/Error/Background/Surface 的 Color Set
2. **无字体规范文件** — 建议创建 `Font+App.swift` 或 `TextStyle` 枚举
3. **无间距/圆角常量** — 建议创建 `Spacing` / `CornerRadius` 枚举
4. **Button Style 未统一** — 部分用 `.borderedProminent`，部分手动 Circle 背景
5. **ControlButton、MessageBubbleView、ChatRoomRow 应独立提取** 到 Components 目录
6. **NavigationView 与 NavigationStack 混用** — 应统一到 NavigationStack (iOS 16+)
7. **无 AAAMock 数据管理** — 部分 ViewModel 直接硬编码 mock 数据（CallViewModel.loadCallHistory）
*（内容由AI生成，仅供参考）*
