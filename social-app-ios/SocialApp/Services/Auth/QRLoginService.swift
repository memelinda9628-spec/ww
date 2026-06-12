import Foundation

// MARK: - QRCodeData
/// 二维码登录数据，对应 Rust QrCodeData

struct QRCodeData: Sendable {
    let rendezvousUrl: String
    let intent: QRLoginIntent
    let homeserver: String
    let expiresAt: Date

    var isExpired: Bool { Date() > expiresAt }
}

// MARK: - QRLoginIntent
/// 二维码登录意图

enum QRLoginIntent: String, Sendable {
    case login
    case grantLogin
    case verifyDevice
}

// MARK: - QRLoginProgress
/// 二维码登录进度

enum QRLoginProgress: Sendable {
    case waitingForScan
    case scanned
    case confirmed
    case authenticated
    case failed(Error)
    case cancelled
}

// MARK: - QRLoginDisplayableCode
/// 可显示的设备验证码，对应 Rust DeviceCode

struct QRLoginDisplayableCode: Sendable {
    let userCode: String
    let verificationUri: String
    let expiresIn: TimeInterval
    let interval: TimeInterval
}

// MARK: - QRLoginService
/// 二维码登录服务，封装扫码登录与授权登录两种模式。
/// 对应 Rust FFI: LoginWithQrCodeHandler / GrantLoginWithQrCodeHandler

@MainActor
final class QRLoginService: ObservableObject {
    static let shared = QRLoginService()

    @Published private(set) var progress: QRLoginProgress = .waitingForScan
    @Published private(set) var displayableCode: QRLoginDisplayableCode?
    @Published private(set) var isSupported: Bool = true
    @Published private(set) var isActive: Bool = false

    private var cancelTask: (() -> Void)?

    
    /// Get the FFI Client from KeychainManager
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

private init() {
        checkSupport()
    }

    // MARK: - 能力检查

    /// 检查 Homeserver 是否支持 MSC4108 QR 码登录
    private func checkSupport() {
        guard let client = ffiClient else { isSupported = false; return }
        isSupported = client.isLoginWithQrCodeSupported()
    }

    // MARK: - 扫码登录模式（接收方）

    /// 以扫码登录模式开始：扫描他人展示的二维码。
    /// 流程：1) 构造 OAuthConfiguration → 2) 创建 LoginWithQrCodeHandler → 3) 调用 handler.scan()
    /// FFI: `Client.newLoginWithQrCodeHandler(oauthConfiguration:)` + `LoginWithQrCodeHandler.scan(qrCodeData:progressListener:)`
    func startScanLogin(
        qrCodeData: String,
        oauthConfig: OAuthConfiguration
    ) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }

        // 将扫描到的字符串转回 FFI QrCodeData
        let data = try QrCodeData.fromBytes(bytes: Data(qrCodeData.utf8))

        let handler = client.newLoginWithQrCodeHandler(oauthConfiguration: oauthConfig)
        isActive = true
        progress = .scanned

        try await handler.scan(
            qrCodeData: data,
            progressListener: QrLoginProgressListenerImpl { [weak self] state in
                Task { @MainActor in
                    self?.handleScanProgress(state)
                }
            }
        )
    }

    /// 解析扫描到的二维码数据
    /// - Parameter rawData: 扫描到的原始字符串
    /// - Returns: 解析后的 QRCodeData
    /// TODO: homeserver/expires 当前为占位值，待 FFI 暴露 MSC4108 解析 API 后替换
    func parseQRCode(_ rawData: String) throws -> QRCodeData {
        guard rawData.hasPrefix("matrix://") || rawData.hasPrefix("https://") else {
            throw SocialFeedError.invalidUrl(rawData)
        }
        let homeserver = ffiClient?.homeserver() ?? "matrix.org"
        return QRCodeData(
            rendezvousUrl: rawData,
            intent: .login,
            homeserver: homeserver,
            expiresAt: Date().addingTimeInterval(120)
        )
    }

    // MARK: - 授权登录模式（展示方）

    /// 以授权登录模式开始：生成本设备二维码供他人扫描。
    /// FFI: `Client.newGrantLoginWithQrCodeHandler()` + `GrantLoginWithQrCodeHandler.generate(progressListener:)`
    func startGrantLogin() async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let handler = client.newGrantLoginWithQrCodeHandler()
        isActive = true
        progress = .waitingForScan

        try await handler.generate(
            progressListener: GrantGeneratedQrLoginProgressListenerImpl { [weak self] state in
                Task { @MainActor in
                    self?.handleGrantProgress(state)
                }
            }
        )
    }

    // MARK: - 操作

    /// 生成 QR 码供另一设备扫码登录（服务端生成模式）
    /// FFI: `Client.newLoginWithQrCodeHandler(oauthConfiguration:)` + `LoginWithQrCodeHandler.generate(progressListener:)`
    func startQrCodeGeneration(oauthConfig: OAuthConfiguration) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let handler = client.newLoginWithQrCodeHandler(oauthConfiguration: oauthConfig)
        isActive = true
        progress = .waitingForScan

        try await handler.generate(
            progressListener: GeneratedQrLoginProgressListenerImpl { [weak self] state in
                Task { @MainActor in
                    self?.handleGenerateProgress(state)
                }
            }
        )
    }

    /// 二次授权时扫码确认（已登录设备扫描新设备 QR 码）
    /// FFI: `Client.newGrantLoginWithQrCodeHandler()` + `GrantLoginWithQrCodeHandler.scan(qrCodeData:progressListener:)`
    func startGrantScan(qrCodeData: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let data = try QrCodeData.fromBytes(bytes: Data(qrCodeData.utf8))
        let handler = client.newGrantLoginWithQrCodeHandler()
        isActive = true
        progress = .scanned

        try await handler.scan(
            qrCodeData: data,
            progressListener: GrantQrLoginProgressListenerImpl { [weak self] state in
                Task { @MainActor in
                    self?.handleGrantScanProgress(state)
                }
            }
        )
    }

    /// 取消二维码登录流程
    func cancel() {
        cancelTask?()
        progress = .cancelled
        isActive = false
        displayableCode = nil
    }

    /// 确认登录
    func confirm() async throws {
        progress = .confirmed
    }

    // MARK: - 进度回调处理

    /// 处理扫码模式（LoginWithQrCodeHandler.scan）进度，FFI: `QrLoginProgress`
    private func handleScanProgress(_ state: QrLoginProgress) {
        switch state {
        case .starting:
            progress = .waitingForScan
        case .establishingSecureChannel(let checkCode, let checkCodeString):
            // checkCode 和 checkCodeString 可展示给用户确认
            _ = (checkCode, checkCodeString)
            progress = .scanned
        case .waitingForToken(let userCode):
            _ = userCode
        case .syncingSecrets:
            break
        case .done:
            progress = .authenticated
            isActive = false
        }
    }

    /// 处理授权模式（GrantLoginWithQrCodeHandler.generate）进度，FFI: `GrantGeneratedQrLoginProgress`
    private func handleGrantProgress(_ state: GrantGeneratedQrLoginProgress) {
        switch state {
        case .starting:
            progress = .waitingForScan
        case .qrReady(let qrCode):
            // qrCode.toBytes() 可渲染为二维码图片供他人扫描
            _ = qrCode
            progress = .waitingForScan
        case .qrScanned(let checkCodeSender):
            _ = checkCodeSender
            progress = .scanned
        case .waitingForAuth(let verificationUri):
            _ = verificationUri
        case .syncingSecrets:
            break
        case .done:
            progress = .authenticated
            isActive = false
        }
    }

    /// 处理 QR 码生成模式（LoginWithQrCodeHandler.generate）进度，FFI: `GeneratedQrLoginProgress`
    private func handleGenerateProgress(_ state: GeneratedQrLoginProgress) {
        switch state {
        case .starting:
            progress = .waitingForScan
        case .qrReady(let qrCode):
            // qrCode.toBytes() 可渲染为 QR 码图片供另一设备扫描
            _ = qrCode
            progress = .waitingForScan
        case .qrScanned(let checkCodeSender):
            _ = checkCodeSender
            progress = .scanned
        case .waitingForToken(let userCode):
            _ = userCode
        case .syncingSecrets:
            break
        case .done:
            progress = .authenticated
            isActive = false
        }
    }

    /// 处理二次授权扫码模式（GrantLoginWithQrCodeHandler.scan）进度，FFI: `GrantQrLoginProgress`
    private func handleGrantScanProgress(_ state: GrantQrLoginProgress) {
        switch state {
        case .starting:
            progress = .waitingForScan
        case .establishingSecureChannel(let checkCode, let checkCodeString):
            _ = (checkCode, checkCodeString)
            progress = .scanned
        case .waitingForAuth(let verificationUri):
            _ = verificationUri
        case .syncingSecrets:
            break
        case .done:
            progress = .authenticated
            isActive = false
        }
    }

}

// MARK: - FFI Progress Listener Implementations

/// FFI: `QrLoginProgressListener` — 扫码模式进度监听
private final class QrLoginProgressListenerImpl: QrLoginProgressListener, @unchecked Sendable {
    let onUpdate: (QrLoginProgress) -> Void
    init(onUpdate: @escaping (QrLoginProgress) -> Void) { self.onUpdate = onUpdate }
    func onUpdate(state: QrLoginProgress) { onUpdate(state) }
}

/// FFI: `GrantGeneratedQrLoginProgressListener` — 授权生成模式进度监听
private final class GrantGeneratedQrLoginProgressListenerImpl: GrantGeneratedQrLoginProgressListener, @unchecked Sendable {
    let onUpdate: (GrantGeneratedQrLoginProgress) -> Void
    init(onUpdate: @escaping (GrantGeneratedQrLoginProgress) -> Void) { self.onUpdate = onUpdate }
    func onUpdate(state: GrantGeneratedQrLoginProgress) { onUpdate(state) }
}

/// FFI: `GeneratedQrLoginProgressListener` — QR 码生成模式进度监听
private final class GeneratedQrLoginProgressListenerImpl: GeneratedQrLoginProgressListener, @unchecked Sendable {
    let onUpdate: (GeneratedQrLoginProgress) -> Void
    init(onUpdate: @escaping (GeneratedQrLoginProgress) -> Void) { self.onUpdate = onUpdate }
    func onUpdate(state: GeneratedQrLoginProgress) { onUpdate(state) }
}

/// FFI: `GrantQrLoginProgressListener` — 二次授权扫码模式进度监听
private final class GrantQrLoginProgressListenerImpl: GrantQrLoginProgressListener, @unchecked Sendable {
    let onUpdate: (GrantQrLoginProgress) -> Void
    init(onUpdate: @escaping (GrantQrLoginProgress) -> Void) { self.onUpdate = onUpdate }
    func onUpdate(state: GrantQrLoginProgress) { onUpdate(state) }
}
