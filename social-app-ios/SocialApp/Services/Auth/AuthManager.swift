import Foundation

// MARK: - AuthManager

/// 认证生命周期管理器：构建 Client、登录、恢复会话、登出。
///
/// 架构约束：
/// - Singleton + @MainActor，与所有 Service 同层。
/// - 通过 ClientBuilder.setSessionDelegate(KeychainManager.shared) 委托
///   KeychainManager 实现透明的 Session 持久化/恢复。
/// - build() 成功后将 Client 注入 KeychainManager.shared.ffiClient，
///   供下游所有 Service 通过 `KeychainManager.shared.ffiClient` 访问。

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isAuthenticated: Bool = false

    private init() {}

    // MARK: - Paths

    private static var dataPath: String {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        return (docs as NSString).appendingPathComponent("matrix_sdk")
    }

    private static var cachePath: String {
        let caches = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
        return (caches as NSString).appendingPathComponent("matrix_sdk")
    }

    // MARK: - Build

    /// 构建 Client 并注入 KeychainManager.ffiClient。
    /// - Parameters:
    ///   - homeserverUrl: 目标 homeserver URL，如 "https://matrix.example.com"
    ///   - serverName: 服务器名称（与 homeserverUrl 二选一），FFI: `ClientBuilder.serverName(serverName:)`
    ///   - serverNameOrUrl: 服务器名或 homeserver URL（自动解析），FFI: `ClientBuilder.serverNameOrHomeserverUrl(serverNameOrUrl:)`
    ///   - username: 预填用户名（登录前降低延迟），FFI: `ClientBuilder.username(username:)`
    ///   - userAgent: 自定义 User-Agent，FFI: `ClientBuilder.userAgent(userAgent:)`
    ///   - disableAutomaticTokenRefresh: 禁用自动 token 刷新，FFI: `ClientBuilder.disableAutomaticTokenRefresh()`
    ///   - autoEnableCrossSigning: 自动启用交叉签名，FFI: `ClientBuilder.autoEnableCrossSigning(autoEnableCrossSigning:)`
    ///   - memoryConstrained: 低内存模式，FFI: `ClientBuilder.systemIsMemoryConstrained()`
    ///   - passphrase: SQLite 存储加密口令，FFI: `SqliteStoreBuilder.passphrase(passphrase:)`
    ///   - slidingSyncVersionBuilder: 滑动同步版本配置，FFI: `ClientBuilder.slidingSyncVersionBuilder(versionBuilder:)`
    ///   - crossProcessLockConfig: 跨进程锁配置，FFI: `ClientBuilder.crossProcessLockConfig(crossProcessLockConfig:)`
    ///   - useInMemoryStore: 使用内存存储（不落盘），FFI: `ClientBuilder.inMemoryStore()`
    /// - Returns: 构建完成的 FFI Client 实例
    @discardableResult
    func buildClient(
        homeserverUrl: String,
        serverName: String? = nil,
        serverNameOrUrl: String? = nil,
        username: String? = nil,
        userAgent: String? = nil,
        disableAutomaticTokenRefresh: Bool = false,
        autoEnableCrossSigning: Bool? = nil,
        memoryConstrained: Bool = false,
        passphrase: String? = nil,
        slidingSyncVersionBuilder: SlidingSyncVersionBuilder? = nil,
        crossProcessLockConfig: CrossProcessLockConfig? = nil,
        useInMemoryStore: Bool = false
    ) async throws -> Client {
        var store = SqliteStoreBuilder(dataPath: Self.dataPath, cachePath: Self.cachePath)

        var builder = ClientBuilder()
            .homeserverUrl(url: homeserverUrl)
            .sessionPaths(dataPath: Self.dataPath, cachePath: Self.cachePath)
            .sqliteStore(config: store)

        if let serverName {
            builder = builder.serverName(serverName: serverName)
        }
        if let serverNameOrUrl {
            builder = builder.serverNameOrHomeserverUrl(serverNameOrUrl: serverNameOrUrl)
        }
        if let username {
            builder = builder.username(username: username)
        }
        if let userAgent {
            builder = builder.userAgent(userAgent: userAgent)
        }
        if disableAutomaticTokenRefresh {
            builder = builder.disableAutomaticTokenRefresh()
        }
        if let autoEnableCrossSigning {
            builder = builder.autoEnableCrossSigning(autoEnableCrossSigning: autoEnableCrossSigning)
        }
        if memoryConstrained {
            builder = builder.systemIsMemoryConstrained()
        }
        if let passphrase {
            store = store.passphrase(passphrase: passphrase)
        }
        if let slidingSyncVersionBuilder {
            builder = builder.slidingSyncVersionBuilder(versionBuilder: slidingSyncVersionBuilder)
        }
        if let crossProcessLockConfig {
            builder = builder.crossProcessLockConfig(crossProcessLockConfig: crossProcessLockConfig)
        }
        if useInMemoryStore {
            builder = builder.inMemoryStore()
        }

        builder = builder.setSessionDelegate(sessionDelegate: KeychainManager.shared)

        let client = try await builder.build()
        KeychainManager.shared.ffiClient = client
        isAuthenticated = true
        return client
    }

    // MARK: - Login

    /// 用户名+密码登录。要求先调用 buildClient(homeserverUrl:) 构建 Client。
    func login(username: String, password: String, initialDeviceName: String? = "SocialApp iOS") async throws {
        guard let client = KeychainManager.shared.ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }
        try await client.login(
            username: username,
            password: password,
            initialDeviceName: initialDeviceName,
            deviceId: nil
        )
        isAuthenticated = true
        // Rust SDK 内部会在登录成功后回调 saveSessionInKeychain 持久化 Session
    }

    /// 邮箱+密码登录，FFI: `Client.loginWithEmail(email:password:initialDeviceName:deviceId:)`
    func loginWithEmail(
        email: String,
        password: String,
        initialDeviceName: String? = "SocialApp iOS"
    ) async throws {
        guard let client = KeychainManager.shared.ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }
        try await client.loginWithEmail(
            email: email,
            password: password,
            initialDeviceName: initialDeviceName,
            deviceId: nil
        )
        isAuthenticated = true
    }

    /// JWT 自定义登录，FFI: `Client.customLoginWithJwt(jwt:initialDeviceName:deviceId:)`
    func customLoginWithJwt(jwt: String, initialDeviceName: String? = "SocialApp iOS") async throws {
        guard let client = KeychainManager.shared.ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }
        try await client.customLoginWithJwt(
            jwt: jwt,
            initialDeviceName: initialDeviceName,
            deviceId: nil
        )
        isAuthenticated = true
    }

    /// 启动 SSO 登录流程，FFI: `Client.startSsoLogin(redirectUrl:idpId:)`
    /// - Returns: SsoHandler，调用方可通过 handler.url() 获取 SSO 页面 URL
    func startSsoLogin(redirectUrl: String, idpId: String? = nil) async throws -> SsoHandler {
        guard let client = KeychainManager.shared.ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }
        return try await client.startSsoLogin(redirectUrl: redirectUrl, idpId: idpId)
    }

    /// 完成 SSO 登录（在 WebView 回调中调用），FFI: `SsoHandler.finish(callbackUrl:)`
    func finishSsoLogin(handler: SsoHandler, callbackUrl: String) async throws {
        try await handler.finish(callbackUrl: callbackUrl)
    }

    /// 获取 OAuth 授权 URL，FFI: `Client.urlForOauth(oauthConfiguration:prompt:loginHint:deviceId:additionalScopes:)`
    func urlForOauth(
        config: OAuthConfiguration,
        prompt: OAuthPrompt? = nil,
        loginHint: String? = nil
    ) async throws -> OAuthAuthorizationData {
        guard let client = KeychainManager.shared.ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }
        return try await client.urlForOauth(
            oauthConfiguration: config,
            prompt: prompt,
            loginHint: loginHint,
            deviceId: nil,
            additionalScopes: nil
        )
    }

    /// OAuth 回调登录，FFI: `Client.loginWithOauthCallback(callbackUrl:)`
    func loginWithOauthCallback(callbackUrl: String) async throws {
        guard let client = KeychainManager.shared.ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }
        try await client.loginWithOauthCallback(callbackUrl: callbackUrl)
        isAuthenticated = true
    }

    /// 中止 OAuth 授权流程，FFI: `Client.abortOauthAuth(authorizationData:)`
    func abortOauthAuth(authorizationData: OAuthAuthorizationData) async {
        guard let client = KeychainManager.shared.ffiClient else { return }
        await client.abortOauthAuth(authorizationData: authorizationData)
    }

    /// 获取当前 Session，FFI: `Client.session()`
    func getSession() throws -> Session {
        guard let client = KeychainManager.shared.ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }
        return try client.session()
    }

    /// 显式恢复 Session（已构建 Client 后），FFI: `Client.restoreSession(session:)`
    func restoreSession(session: Session) async throws {
        guard let client = KeychainManager.shared.ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }
        try await client.restoreSession(session: session)
        isAuthenticated = true
    }

    /// 显式恢复 Session + 自定义房间加载策略，FFI: `Client.restoreSessionWith(session:roomLoadSettings:)`
    func restoreSessionWith(session: Session, roomLoadSettings: RoomLoadSettings) async throws {
        guard let client = KeychainManager.shared.ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }
        try await client.restoreSessionWith(session: session, roomLoadSettings: roomLoadSettings)
        isAuthenticated = true
    }

    /// 获取 Homeserver 登录方式详情，FFI: `Client.homeserverLoginDetails()`
    func homeserverLoginDetails() async -> HomeserverLoginDetails? {
        guard let client = KeychainManager.shared.ffiClient else { return nil }
        return await client.homeserverLoginDetails()
    }

    // MARK: - Restore

    /// 尝试从 SQLite + Keychain 恢复上次会话。
    /// - Parameters:
    ///   - homeserverUrl: 上次登录的 homeserver URL。若 Keychain 中无记录，需调用方通过 UI 收集后传入。
    ///   - 其余参数：与 `buildClient` 相同的可选配置项，用于自定义恢复后的客户端行为。
    /// - Returns: 恢复成功返回 Client，失败抛出错误由调用方进入登录流程
    @discardableResult
    func restoreSession(
        homeserverUrl: String,
        serverName: String? = nil,
        serverNameOrUrl: String? = nil,
        username: String? = nil,
        userAgent: String? = nil,
        disableAutomaticTokenRefresh: Bool = false,
        autoEnableCrossSigning: Bool? = nil,
        memoryConstrained: Bool = false,
        passphrase: String? = nil,
        slidingSyncVersionBuilder: SlidingSyncVersionBuilder? = nil,
        crossProcessLockConfig: CrossProcessLockConfig? = nil,
        useInMemoryStore: Bool = false
    ) async throws -> Client {
        var store = SqliteStoreBuilder(dataPath: Self.dataPath, cachePath: Self.cachePath)

        var builder = ClientBuilder()
            .homeserverUrl(url: homeserverUrl)
            .sessionPaths(dataPath: Self.dataPath, cachePath: Self.cachePath)
            .sqliteStore(config: store)

        if let serverName {
            builder = builder.serverName(serverName: serverName)
        }
        if let serverNameOrUrl {
            builder = builder.serverNameOrHomeserverUrl(serverNameOrUrl: serverNameOrUrl)
        }
        if let username {
            builder = builder.username(username: username)
        }
        if let userAgent {
            builder = builder.userAgent(userAgent: userAgent)
        }
        if disableAutomaticTokenRefresh {
            builder = builder.disableAutomaticTokenRefresh()
        }
        if let autoEnableCrossSigning {
            builder = builder.autoEnableCrossSigning(autoEnableCrossSigning: autoEnableCrossSigning)
        }
        if memoryConstrained {
            builder = builder.systemIsMemoryConstrained()
        }
        if let passphrase {
            store = store.passphrase(passphrase: passphrase)
        }
        if let slidingSyncVersionBuilder {
            builder = builder.slidingSyncVersionBuilder(versionBuilder: slidingSyncVersionBuilder)
        }
        if let crossProcessLockConfig {
            builder = builder.crossProcessLockConfig(crossProcessLockConfig: crossProcessLockConfig)
        }
        if useInMemoryStore {
            builder = builder.inMemoryStore()
        }

        builder = builder.setSessionDelegate(sessionDelegate: KeychainManager.shared)

        let client = try await builder.build()
        KeychainManager.shared.ffiClient = client

        // Rust SDK build() 时自动通过 Delegate 恢复 Session；
        // homeserver() 返回空串或登录态校验失败视为未认证
        let hs = client.homeserver()
        isAuthenticated = !hs.isEmpty
        return client
    }

    // MARK: - Logout

    func logout() async throws {
        if let client = KeychainManager.shared.ffiClient {
            try await client.logout()
        }
        KeychainManager.shared.ffiClient = nil
        try? KeychainManager.shared.clearSession()
        isAuthenticated = false
    }
}
