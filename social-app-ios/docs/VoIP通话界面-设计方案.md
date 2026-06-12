---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 962bf721db6534c0bb69c381149ce2ef_808d1cde65fc11f195cd525400d9a7a1
    ReservedCode1: FgyQxtRes5Hxk5SXJFG2e8GLz4XhBeAtQiSnpd4XqJ1KwISusbzOPX4P9ZVlXBp5Jg+tdgQ3UyctLDNcubKwqAisKTAeO+YVi3m6uuxjjsYZAfWgLctMAnXcBWesy6b0KNSEXITIfjjS8pQLzWCjAV6KVxrHKD+OrKOw4e7u4ny5g70w3DEhV0VyUTo=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 962bf721db6534c0bb69c381149ce2ef_808d1cde65fc11f195cd525400d9a7a1
    ReservedCode2: FgyQxtRes5Hxk5SXJFG2e8GLz4XhBeAtQiSnpd4XqJ1KwISusbzOPX4P9ZVlXBp5Jg+tdgQ3UyctLDNcubKwqAisKTAeO+YVi3m6uuxjjsYZAfWgLctMAnXcBWesy6b0KNSEXITIfjjS8pQLzWCjAV6KVxrHKD+OrKOw4e7u4ny5g70w3DEhV0VyUTo=
---

# VoIP 通话界面详细设计方案

> 基于 social-app-ios 现有 CallView.swift / IncomingCallView.swift / CallViewModel.swift 代码分析得出

---

## 1. 现状诊断

### 1.1 已实现的部分

| 文件 | 行数 | 状态 | 说明 |
|------|------|------|------|
| `CallView.swift` | 244 | **UI 完成 80%** | ZStack 全屏布局、Capsule 状态栏、ControlButton 三按钮、CallWebView 已集成 |
| `IncomingCallView.swift` | 176 | **UI 完成 85%** | LinearGradient 背景、AvatarView+渐变边框、振铃动画、接听/拒接按钮 |
| `CallViewModel.swift` | 305 | **逻辑 40%** | 状态枚举完整、类型定义完整、操作标记为 TODO、Mock 数据存在 |

### 1.2 待完成的核心问题

| 问题 | 影响 | 严重程度 |
|------|------|--------|
| CallViewModel 中 8 个方法全部为 `// TODO: Connect to Rust FFI` | 通话无法实际发起/接听/挂断 | 🔴 阻塞 |
| `callService` 为 nil | 无 FFI 桥接 | 🔴 阻塞 |
| IncomingCallView 的 `timeoutTimer` 为模拟 30 秒 | 来电超时非真实逻辑 | 🟡 中等 |
| `loadCallHistory()` 硬编码 3 条 Mock 记录 | 通话记录非真实数据 | 🟢 低 |
| 缺失功能：视频通话预览、通话中通知横幅、通话转接、多方通话 | 高级功能缺失 | 🟢 低 |
| `CallWebView` 加载 Element Call URL — 可能不可用 | WebView 方案替代原生 UI | 🟡 中等 |

### 1.3 现有 UI 设计精华（需保留）

**CallView 的优秀设计**：
- 全黑背景 + 顶部 Capsule 状态栏（`ultraThinMaterial`）— 符合 iOS 通话 UI 惯例
- 底部 `ControlButton` 组件设计精良：72pt 圆形 + 图标 + 标签文字
- `CallState` 枚举驱动状态切换（connecting/ringing/connected/ended/failed）

**IncomingCallView 的优秀设计**：
- LinearGradient 全屏背景（systemGray6 → systemBackground）— 柔和高级
- 头像渐变边框（`LinearGradient(colors: [.blue, .purple]`）— 项目现有模式（SpaceCard 同）
- 振铃动画（`scaleEffect` + `.repeatForever`）— 绿色/红色指示灯
- 接听/拒接按钮清晰分层（绿色接听在上，红色拒接在下）

---

## 2. CallView 完整方案

### 2.1 布局结构（保持现有 244 行基本架构）

```
CallView
 └── GeometryReader { proxy in
      ZStack {
          // 1. 全黑背景
          Color.black.ignoresSafeArea()

          // 2. 竖屏布局
          if proxy.size.width < proxy.size.height {
              VStack(spacing: 0) {
                  // 顶部状态栏（Capsule）
                  CallStatusBar(state: callState, duration: duration)
                      .padding(.top, proxy.safeAreaInsets.top + 20)

                  Spacer()

                  // 中间信息区 — **新增：视频/语音类型区分**
                  CallCenterView(state: callState, callType: callType)
                      // 语音：显示 AvatarView + 姓名 + 时长
                      // 视频：显示摄像头画面（占位）+ 小窗自身画面

                  Spacer()

                  // 底部控制按钮组
                  CallControlPanel(state: callState, actions: actions)
                      .padding(.bottom, proxy.safeAreaInsets.bottom + 30)
              }

          } else {
              // 横屏布局 — **新增**
              HStack(spacing: 0) {
                  CallCenterView(state: callState, callType: callType)
                      .frame(maxWidth: .infinity)
                  VStack {
                      Spacer()
                      CallControlPanel(state: callState, actions: actions)
                          .padding(.bottom, proxy.safeAreaInsets.bottom + 30)
                  }
              }
          }
      }
      .animation(.easeInOut(duration: 0.3), value: callState)
 }
```

### 2.2 新增子组件设计

#### CallStatusBar（从现有代码内联提取为独立组件）

```
Capsule()
    .fill(.ultraThinMaterial)
    .frame(width: 120, height: 36)
    .overlay {
        HStack(spacing: 6) {
            if state == .connected {
                Image(systemName: "phone.fill")
                    .font(.caption)
                Text(formattedDuration)
                    .font(.caption)
                    .monospacedDigit()
            } else {
                Image(systemName: stateIcon)
                Text(stateLabel)
                    .font(.caption)
            }
        }
        .foregroundColor(.white)
    }
```

#### CallCenterView — **新建**

```
// 语音通话模式
VStack(spacing: 20) {
    AvatarView(name: participantName, url: avatarUrl, size: 100)
    Text(participantName)
        .font(.title.weight(.semibold))
        .foregroundColor(.white)
    if callState == .connected {
        Text(formattedDuration)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.5))
            .monospacedDigit()
    }
}

// 视频通话模式
ZStack {
    // 远端画面（占位：系统蓝色 + 对方头像）
    RoundedRectangle(cornerRadius: 0)
        .fill(Color(.systemGray6))
        .overlay {
            AvatarView(name: participantName, url: avatarUrl, size: 100)
        }

    // 自身画面小窗（右下角）
    VStack {
        Spacer()
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray4))
                .frame(width: 100, height: 140)
                .overlay {
                    Image(systemName: "video.slash.fill")
                        .foregroundColor(.white)
                }
                .padding(16)
        }
    }
}
```

#### CallControlPanel（从现有底部控制区提取）

```
HStack(spacing: 40) {
    // 静音按钮
    ControlButton(
        icon: isMuted ? "mic.slash.fill" : "mic.fill",
        label: "静音",
        foregroundColor: .white,
        backgroundColor: isMuted ? .white.opacity(0.3) : .white.opacity(0.15),
        action: { toggleMute() }
    )

    // 挂断按钮（红色）
    ControlButton(
        icon: "phone.down.fill",
        label: "挂断",
        foregroundColor: .white,
        backgroundColor: .red,
        action: { hangUp() }
    )

    // 扬声器按钮
    ControlButton(
        icon: isSpeakerOn ? "speaker.wave.2.fill" : "speaker.wave.1.fill",
        label: "扬声器",
        foregroundColor: .white,
        backgroundColor: isSpeakerOn ? .white.opacity(0.3) : .white.opacity(0.15),
        action: { toggleSpeaker() }
    )
}
```

### 2.3 ControlButton 组件规范（提取并统一）

```swift
// 当前位于 CallView.swift 内联，应提取为 Views/Components/ControlButton.swift
struct ControlButton: View {
    let icon: String
    let label: String
    let foregroundColor: Color
    let backgroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: 64, height: 64)
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundColor(foregroundColor)
                }
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
}
```

---

## 3. IncomingCallView 完整方案

### 3.1 布局结构（保持现有 176 行架构 + 增强）

```
IncomingCallView
 └── GeometryReader { proxy in
      ZStack {
          // 背景渐变（保持现有）
          LinearGradient(
              colors: [Color(.systemGray6), Color(.systemBackground)],
              startPoint: .top, endPoint: .bottom
          ).ignoresSafeArea()

          VStack(spacing: 40) {
              Spacer()

              // 来电标签（保持现有）
              Text("Incoming Call")
                  .font(.subheadline.weight(.medium))
                  .foregroundColor(.secondary)
                  .textCase(.uppercase)
                  .tracking(2)

              // 头像 + 渐变边框（保持现有 — 与 SpaceCard 模式一致）
              Circle()
                  .stroke(LinearGradient(...), lineWidth: 3)
                  .frame(width: 106, height: 106)
                  .overlay {
                      AvatarView(name: callerName, url: avatarUrl, size: 100)
                  }

              // 来电者姓名（保持现有）
              Text(callerName)
                  .font(.title.weight(.semibold))

              // 通话类型 + 状态 — **增强**
              VStack(spacing: 4) {
                  if callType == .video {
                      Label("视频通话", systemImage: "video.fill")
                          .font(.subheadline)
                          .foregroundColor(.secondary)
                  } else {
                      Label("语音通话", systemImage: "phone.fill")
                          .font(.subheadline)
                          .foregroundColor(.secondary)
                  }

                  // 振铃动画指示器（保持现有圆点脉冲）
                  HStack(spacing: 6) {
                      Circle()
                          .fill(Color.green)
                          .frame(width: 8, height: 8)
                          .scaleEffect(isRinging ? 1.5 : 1.0)
                          .opacity(isRinging ? 0.5 : 1.0)
                          .animation(
                              .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                              value: isRinging
                          )
                      Text("正在响铃...")
                          .font(.caption)
                          .foregroundColor(.secondary)
                  }
                  .padding(.top, 8)
              }

              Spacer()

              // 操作按钮组 — **保持现有设计，增加视频接听按钮**
              HStack(spacing: 60) {
                  // 拒接按钮
                  VStack(spacing: 8) {
                      Button { declineCall() } label: {
                          ZStack {
                              Circle()
                                  .fill(Color.red)
                                  .frame(width: 68, height: 68)
                              Image(systemName: "phone.down.fill")
                                  .font(.system(size: 28))
                                  .foregroundColor(.white)
                          }
                      }
                      .buttonStyle(.plain)
                      Text("拒接")
                          .font(.caption2)
                          .foregroundColor(.secondary)
                  }

                  // 接听按钮 + **新增视频接听**
                  VStack(spacing: 8) {
                      Button { acceptCall() } label: {
                          ZStack {
                              Circle()
                                  .fill(Color.green)
                                  .frame(width: 68, height: 68)
                              Image(systemName: callType == .video ? "video.fill" : "phone.fill")
                                  .font(.system(size: 28))
                                  .foregroundColor(.white)
                          }
                      }
                      .buttonStyle(.plain)
                      Text(callType == .video ? "视频接听" : "接听")
                          .font(.caption2)
                          .foregroundColor(.secondary)
                  }
              }

              // 提示文字（保持现有）
              Text(messageToShow)
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .multilineTextAlignment(.center)
                  .padding(.horizontal, 40)
                  .padding(.top, 8)

              Spacer()
                  .frame(height: proxy.safeAreaInsets.bottom + 30)
          }
      }
 }
 .onAppear {
     isRinging = true
     startTimeoutTimer()
 }
 .onDisappear {
     isRinging = false
     stopTimeoutTimer()
 }
```

### 3.2 振铃动画增强

保持现有的绿色/红色圆点脉冲动画。该方案简洁有效，与 iOS 通话 UI 风格一致，无需更改。

---

## 4. CallViewModel 改造优先级

### P0 — 阻塞项（需 FFI 就绪）

| 方法 | 当前状态 | 目标 |
|------|---------|------|
| `startCall(roomId:callType:)` | `// TODO` | 接入 `CallService.placeCall()` |
| `acceptCall()` | `// TODO` + mock 状态切换 | 接入 `CallService.answer()` |
| `declineCall()` | `// TODO` + mock 状态切换 | 接入 `CallService.decline()` |
| `hangUp()` | `// TODO` + mock 状态切换 | 接入 `CallService.hangUp()` |
| `toggleMute()` | `// TODO` + mock 本地切换 | 接入 `CallService.setMuted()` |
| `toggleSpeaker()` | `// TODO` | 接入 AVAudioSession 路由 |
| `toggleVideo()` | `// TODO` | 接入 `CallService.setVideoEnabled()` |

### P1 — 重要项

| 功能 | 当前状态 | 目标 |
|------|---------|------|
| 通话超时 | 模拟 30 秒 | 从 FFI 事件订阅真实振铃超时 |
| 来电通知 | 无 | 通过 `CallService.onIncomingCall` 回调触发 IncomingCallView |
| 通话记录 | Mock 3 条 | 接入 `CallService.getCallHistory()` |
| `callService` 初始化 | `nil` | `AppContainer` 中创建并注入 |

### P2 — 增强项

| 功能 | 说明 |
|------|------|
| 视频通话预览 | 摄像头本地预览 |
| 通话中通知横幅 | 后台通话保持绿色横幅 |
| 通话转接 | 多方通话扩展 |

---

## 5. 状态流定义

```
                    ┌─────────────────────┐
                    │       .idle         │
                    └──────┬──────────────┘
                           │ startCall() / IncomingCall
                    ┌──────▼──────────────┐
                    │    .connecting      │ ← outgoing
                    │    .ringing         │ ← incoming
                    └──────┬──────────────┘
                           │ accepted / answered
                    ┌──────▼──────────────┐
                    │    .connected       │
                    └──────┬──────────────┘
                           │ hangUp() / remote hangUp
                    ┌──────▼──────────────┐
                    │    .ended           │
                    └─────────────────────┘

                    异常路径:
                    .connecting → .failed
                    .ringing → .failed (timeout)
```

---

## 6. 与项目现有模式的对齐

| 对齐项 | 现有模式 | VoIP 方案对齐 |
|--------|---------|-------------|
| 全屏布局 | ZStack + GeometryReader | CallView 已用，保持 |
| 背景 | LinearGradient / Color.black | IncomingCallView 渐变，CallView 黑色 |
| 头像 | AvatarView（Circle 100pt） | IncomingCallView 已用 |
| 头像渐变边框 | `SpaceCard` 中的蓝紫渐变 | IncomingCallView 已用 |
| 动画 | scaleEffect + repeatForever | IncomingCallView 振铃动画 |
| Button style | `.buttonStyle(.plain)` + 自定义 Circle | 通话按钮一致 |
| 材质效果 | `.ultraThinMaterial` | CallView 状态栏 |
| 状态管理 | `@StateObject + ViewModel + @Published` | 已用 |
| 环境检测 | `@Environment(\.scenePhase)` | 可用于检测应用前后台 |

---

## 7. 组件提取建议

从当前 `CallView.swift` 和 `IncomingCallView.swift` 中提取以下可复用组件到 `Views/Components/`：

| 组件 | 来源 | 目标文件 |
|------|------|---------|
| `ControlButton` | CallView.swift (内联) | `Views/Components/ControlButton.swift` |
| `CallStatusBar` | CallView.swift (内联 Capsule) | `Views/Components/CallStatusBar.swift` |
| `CallControlPanel` | CallView.swift (底部按钮组) | `Views/Chat/CallControlPanel.swift` |
| `IncomingCallActionButtons` | IncomingCallView.swift (接听/拒接按钮组) | `Views/Chat/IncomingCallActionButtons.swift` |

---

## 8. 文件清单

```
SocialApp/
  Views/
    Chat/
      CallView.swift                      ← 改造（提取子组件）
      IncomingCallView.swift              ← 改造（增强类型区分）
    Components/
      ControlButton.swift                 ← 新建（从 CallView 提取）
      CallStatusBar.swift                 ← 新建
  ViewModels/
    CallViewModel.swift                   ← 改造（接入 FFI）
```
*（内容由AI生成，仅供参考）*
