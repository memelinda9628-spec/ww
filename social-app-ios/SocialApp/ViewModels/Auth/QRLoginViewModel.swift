import Foundation
import SwiftUI

// MARK: - QRLoginViewModel
/// 二维码登录 ViewModel，对应 QRLoginService。
/// 管理 QR 码登录/授权流程的状态和 UI 交互。

@MainActor
final class QRLoginViewModel: ObservableObject {
    @Published var progress: QRLoginProgress = .waitingForScan
    @Published var displayableCode: QRLoginDisplayableCode?
    @Published var isSupported: Bool = true
    @Published var isActive: Bool = false
    @Published var mode: QRLoginMode = .scanLogin
    @Published var scannedCode: String = ""
    @Published var errorMessage: String?
    @Published var parsedData: QRCodeData?

    private let service = QRLoginService.shared

    // MARK: - 模式

    enum QRLoginMode: String, CaseIterable {
        case scanLogin = "扫码登录"
        case grantLogin = "授权登录"

        var description: String {
            switch self {
            case .scanLogin: return "扫描其他设备上显示的二维码以登录"
            case .grantLogin: return "在本设备上生成二维码，供其他设备扫描授权"
            }
        }
    }

    // MARK: - 扫码登录

    /// 解析扫描到的二维码并开始登录
    func startScanning(_ rawData: String) {
        scannedCode = rawData
        errorMessage = nil

        do {
            let data = try service.parseQRCode(rawData)
            parsedData = data
            progress = .scanned
            isActive = true

            if data.isExpired {
                errorMessage = "二维码已过期，请刷新后重试"
                progress = .failed(QRLoginError.expired)
                return
            }
        } catch {
            errorMessage = "无法识别该二维码，请确认是否为有效的 Matrix 登录码"
            progress = .failed(error)
        }
    }

    /// 确认登录
    func confirmLogin() async {
        do {
            progress = .confirmed
            try await service.startScanLogin(qrCodeData: scannedCode)
            progress = .authenticated
            isActive = false
        } catch {
            progress = .failed(error)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 授权登录

    /// 开始生成授权二维码
    func startGranting() async {
        errorMessage = nil

        do {
            try await service.startGrantLogin()
            progress = service.progress
            displayableCode = service.displayableCode
            isActive = service.isActive
        } catch {
            errorMessage = error.localizedDescription
            progress = .failed(error)
        }
    }

    // MARK: - 操作

    /// 取消
    func cancel() {
        service.cancel()
        resetLocalState()
    }

    /// 切换模式
    func setMode(_ newMode: QRLoginMode) {
        cancel()
        mode = newMode
    }

    /// 重试
    func retry() {
        cancel()
        errorMessage = nil
        scannedCode = ""
        parsedData = nil
        progress = .waitingForScan

        if mode == .grantLogin {
            Task { await startGranting() }
        }
    }

    // MARK: - 状态

    private func resetLocalState() {
        progress = .waitingForScan
        displayableCode = nil
        isActive = false
        scannedCode = ""
        parsedData = nil
        errorMessage = nil
    }

    var progressTitle: String {
        switch progress {
        case .waitingForScan: return "等待扫描"
        case .scanned: return "已扫描，确认登录？"
        case .confirmed: return "正在验证..."
        case .authenticated: return "登录成功"
        case .failed: return "登录失败"
        case .cancelled: return "已取消"
        }
    }

    var progressIcon: String {
        switch progress {
        case .waitingForScan: return "qrcode.viewfinder"
        case .scanned: return "checkmark.circle"
        case .confirmed: return "hourglass"
        case .authenticated: return "checkmark.shield"
        case .failed: return "xmark.shield"
        case .cancelled: return "xmark.circle"
        }
    }
}

// MARK: - QRLoginError

enum QRLoginError: LocalizedError {
    case expired
    case invalidQR
    case userCancelled
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .expired: return "二维码已过期"
        case .invalidQR: return "无效的二维码"
        case .userCancelled: return "用户取消登录"
        case .networkError(let msg): return "网络错误: \(msg)"
        }
    }
}