import SwiftUI

@main
struct SocialApp: App {
    @StateObject private var authManager = AppContainer.shared.authManager
    @State private var isRestoring = true

    var body: some Scene {
        WindowGroup {
            Group {
                if isRestoring {
                    ProgressView("正在恢复会话...")
                } else if authManager.isAuthenticated {
                    mainTabView
                } else {
                    AuthGateView()
                        .environmentObject(authManager)
                }
            }
            .task {
                await attemptRestore()
            }
        }
    }

    // MARK: - Main Content

    private var mainTabView: some View {
        TabView {
            FeedView()
                .tabItem { Label("信息流", systemImage: "house") }
            DiscoverView()
                .tabItem { Label("发现", systemImage: "magnifyingglass") }
            ProfileView()
                .tabItem { Label("我的", systemImage: "person") }
        }
    }

    // MARK: - Restore

    private func attemptRestore() async {
        // 1. 尝试从 Keychain 读取上次的 homeserver URL
        let homeserverUrl: String = (try? KeychainManager.shared.readString(for: .homeserver)) ?? ""

        if homeserverUrl.isEmpty {
            isRestoring = false
            return
        }

        // 2. 尝试恢复会话
        do {
            try await authManager.restoreSession(homeserverUrl: homeserverUrl)
        } catch {
            // 恢复失败，走登录流程
        }
        isRestoring = false
    }
}

// MARK: - AuthGateView (Placeholder)

/// 未认证时的占位页面。后续替换为完整的 LoginView。
private struct AuthGateView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var homeserverInput: String = "https://matrix.example.com"

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("未登录")
                .font(.title2)
                .fontWeight(.semibold)

            Text("请先连接到 Matrix Homeserver")
                .foregroundColor(.secondary)

            TextField("Homeserver URL", text: $homeserverInput)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .frame(maxWidth: 320)

            Button("登录") {
                // TODO: 连接真实 LoginView（用户名/密码/SSO 等）
            }
            .buttonStyle(.borderedProminent)
            .disabled(homeserverInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
