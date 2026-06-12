---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 962bf721db6534c0bb69c381149ce2ef_8020a7e965fc11f18b225254006c9bbf
    ReservedCode1: VCDUDaNbtBVgiY0PA6eCjflfg2eaTFK96tQWwWg1FPKcGyR/6SdoE/9IeT5vIdJztczSTixNEqfe5WeW4So7OHL5jbHPSV05Pb+bVNfpBT075HS5Pd3ARVclfu4ZuI8ook+v8q3B0DzJzxnc9DYhh1ZibYNeh7aGiJih58A5NKZLMgxK16A2MJv+C4I=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 962bf721db6534c0bb69c381149ce2ef_8020a7e965fc11f18b225254006c9bbf
    ReservedCode2: VCDUDaNbtBVgiY0PA6eCjflfg2eaTFK96tQWwWg1FPKcGyR/6SdoE/9IeT5vIdJztczSTixNEqfe5WeW4So7OHL5jbHPSV05Pb+bVNfpBT075HS5Pd3ARVclfu4ZuI8ook+v8q3B0DzJzxnc9DYhh1ZibYNeh7aGiJih58A5NKZLMgxK16A2MJv+C4I=
---

# LoginView 详细设计方案

> 基于 social-app-ios 现有代码模式分析得出，方案与项目实际架构对齐。

---

## 1. 现状诊断

### 当前状态
- `SocialApp.swift:88` 处标注 `// TODO: 连接真实 LoginView`
- `AuthGateView` 仅含一个 `TextField`（Homeserver URL）+ 一个无实际动作的登录按钮
- `AuthManager` 的 FFI 方法已全部实现（login/SSO/OAuth/QR/restoreSession），仅缺 UI 调用
- QRLoginView 已完整实现（247 行），可作为认证 UI 的参考模板

### 需要新建/改造
| 文件 | 操作 |
|------|------|
| `LoginView.swift` | **新建** |
| `LoginViewModel.swift` | **新建** |
| `AuthGateView.swift` | **改造** → 增加 NavigationLink 或替换占位 |

---

## 2. 颜色与风格对齐

基于现有项目的**零自定义颜色资产**现状，LoginView 配色方案如下：

| 用途 | 实现 |
|------|------|
| 页面背景 | `Color(.systemBackground)` |
| 卡片/输入框背景 | `Color(.systemGray6)` |
| 主文字 | `.foregroundColor(.primary)` |
| 次要文字 | `.foregroundColor(.secondary)` |
| 主按钮（登录/确认） | `.buttonStyle(.borderedProminent)` + `.tint(.blue)` |
| 次要按钮（SSO/OAuth） | `.buttonStyle(.bordered)` + `.tint(.accentColor)` |
| 错误文字 | `.foregroundColor(.red)` |
| 分隔线 | `Divider()` |
| 输入栏圆角 | `.cornerRadius(10)` → `RoundedBorderTextFieldStyle` |
| 主按钮圆角 | 默认（borderedProminent 自带） |

---

## 3. 布局方案

### 3.1 整体结构

```
LoginView
 └── ScrollView (.vertical)
      └── VStack (spacing: 24, padding: 24)
           ├── AppLogo 区域
           │    ├── Image(systemName: "message.fill") 或应用图标
           │    │   .font(.system(size: 64))
           │    │   .foregroundColor(.blue)
           │    └── Text("SocialApp")
           │       .font(.title.weight(.semibold))
           │
           ├── Homeserver 配置区域 (Section)
           │    └── TextField("Homeserver URL", text: $homeserverUrl)
           │       .textFieldStyle(.roundedBorder)
           │       .keyboardType(.URL)
           │       .autocapitalization(.none)
           │
           ├── 登录方式选择 Segmented Picker
           │    ├── Picker("", selection: $loginMode)
           │    │   .pickerStyle(.segmented)
           │    ├── 标签: "密码" | "SSO" | "OAuth"
           │    │
           │    ├── [case .password]  → 密码登录区域
           │    ├── [case .sso]       → SSO 登录区域
           │    └── [case .oauth]     → OAuth 登录区域
           │
           ├── 对应模式的输入区域 (@ViewBuilder)
           │
           ├── 主操作按钮
           │    ├── Button("登录") { Task { await viewModel.login() } }
           │    │   .buttonStyle(.borderedProminent)
           │    │   .disabled(!viewModel.canLogin || viewModel.isLoading)
           │    │   .frame(maxWidth: .infinity)
           │    │
           │    └── if isLoading → ProgressView()
           │
           ├── 错误信息条
           │    if let error = viewModel.errorMessage
           │    → Text(error).foregroundColor(.red).font(.caption)
           │
           ├── Divider() + "或" label
           │
           ├── 二维码登录入口
           │    └── NavigationLink { QRLoginView() } label: {
           │         Label("二维码登录", systemImage: "qrcode")
           │       }
           │       .buttonStyle(.bordered)
           │
           └── 底部提示
                └── Text("登录即表示同意服务条款")
                   .font(.caption2)
                   .foregroundColor(.secondary)
```

### 3.2 三种登录模式细节

#### 密码模式
```
VStack(spacing: 12) {
    TextField("用户名 / Matrix ID", text: $username)
        .textFieldStyle(.roundedBorder)
        .textContentType(.username)
        .autocapitalization(.none)
        .disableAutocorrection(true)

    SecureField("密码", text: $password)
        .textFieldStyle(.roundedBorder)
        .textContentType(.password)
}
```

#### SSO 模式
```
VStack(spacing: 12) {
    Text("使用单点登录服务")
        .font(.subheadline)
        .foregroundColor(.secondary)

    if viewModel.ssoProviders.isEmpty {
        ProgressView()
    } else {
        ForEach(viewModel.ssoProviders) { provider in
            Button {
                Task { await viewModel.ssoLogin(provider: provider) }
            } label: {
                HStack {
                    Text(provider.name)
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }

    // 手动输入 SSO URL
    Divider()
    TextField("自定义 Identity Provider URL", text: $customSsoUrl)
        .textFieldStyle(.roundedBorder)
        .autocapitalization(.none)
}
```

#### OAuth 模式
```
VStack(spacing: 12) {
    Text("通过 OAuth 2.0 授权登录")
        .font(.subheadline)
        .foregroundColor(.secondary)

    TextField("OAuth Issuer URL", text: $oauthIssuerUrl)
        .textFieldStyle(.roundedBorder)
        .keyboardType(.URL)

    TextField("Client ID", text: $oauthClientId)
        .textFieldStyle(.roundedBorder)

    SecureField("Redirect URI", text: $oauthRedirectUri)
        .textFieldStyle(.roundedBorder)
}
```

---

## 4. LoginViewModel 设计

```swift
@MainActor
final class LoginViewModel: ObservableObject {
    // MARK: - 输入
    @Published var homeserverUrl: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var loginMode: LoginMode = .password

    // MARK: - SSO
    @Published var ssoProviders: [SsoProviderInfo] = []
    @Published var customSsoUrl: String = ""

    // MARK: - OAuth
    @Published var oauthIssuerUrl: String = ""
    @Published var oauthClientId: String = ""
    @Published var oauthRedirectUri: String = ""

    // MARK: - 状态
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - 计算属性
    var canLogin: Bool {
        guard !homeserverUrl.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch loginMode {
        case .password:
            return !username.trimmingCharacters(in: .whitespaces).isEmpty
                && !password.isEmpty
        case .sso:
            return !customSsoUrl.isEmpty || !ssoProviders.isEmpty
        case .oauth:
            return !oauthIssuerUrl.isEmpty && !oauthClientId.isEmpty
        }
    }

    // MARK: - 依赖（通过 AppContainer 获取 AuthManager）
    private var authManager: AuthManager {
        AppContainer.shared.authManager
    }

    // MARK: - 方法
    func loadSsoProviders() async {
        do {
            ssoProviders = try await authManager.getSsoProviders(homeserverUrl: homeserverUrl)
        } catch {
            errorMessage = "无法加载 SSO 提供商: \(error.localizedDescription)"
        }
    }

    func login() async {
        guard canLogin else { return }
        isLoading = true
        errorMessage = nil
        do {
            switch loginMode {
            case .password:
                try await authManager.login(
                    homeserverUrl: homeserverUrl,
                    username: username,
                    password: password
                )
            case .sso:
                let url = customSsoUrl.isEmpty ? ssoProviders.first?.url ?? "" : customSsoUrl
                try await authManager.ssoLogin(homeserverUrl: homeserverUrl, providerUrl: url)
            case .oauth:
                try await authManager.oauthLogin(
                    homeserverUrl: homeserverUrl,
                    issuerUrl: oauthIssuerUrl,
                    clientId: oauthClientId,
                    redirectUri: oauthRedirectUri
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 辅助类型
enum LoginMode: String, CaseIterable {
    case password = "密码"
    case sso = "SSO"
    case oauth = "OAuth"
}

struct SsoProviderInfo: Identifiable {
    let id: String
    let name: String
    let url: String
}
```

---

## 5. AuthGateView 改造方案

**现有**（仅 Homeserver 输入 + 无动作按钮）→ **改造为**：

```swift
struct AuthGateView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showLoginView = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "message.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                Text("SocialApp")
                    .font(.title.weight(.semibold))

                TextField("Homeserver URL", text: $homeserverUrl)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Button("登录") {
                    showLoginView = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationDestination(isPresented: $showLoginView) {
                LoginView(homeserverUrl: homeserverUrl)
            }
        }
    }
}
```

---

## 6. 与现有代码的对齐清单

| 对齐项 | 现有模式 | LoginView 对齐方式 |
|--------|---------|------------------|
| 状态管理 | `@StateObject + ViewModel + @Published` | LoginViewModel 同模式 |
| 导航 | `NavigationStack` + `.navigationDestination` | 同模式 |
| 模态表单 | `NavigationStack` + `.toolbar` 取消/确认 | 无模态，直接 push |
| 按钮风格 | `.buttonStyle(.borderedProminent)` | 同 |
| 输入框 | `.textFieldStyle(.roundedBorder)` | 同（QRLoginView 已用） |
| 错误展示 | `Text(error).foregroundColor(.red)` | 同 |
| 加载状态 | `ProgressView()` | 同 |
| 间距 | VStack spacing: 24 | 同 |
| 下载方法注入 | AppContainer.shared.authManager | 同上 |
| 分段选择 | `.pickerStyle(.segmented)` | 同（QRLoginView 已用） |

---

## 7. 文件清单

```
SocialApp/
  Views/
    Auth/
      LoginView.swift          ← 新建
      AuthGateView.swift       ← 改造
  ViewModels/
    LoginViewModel.swift       ← 新建
```
*（内容由AI生成，仅供参考）*
