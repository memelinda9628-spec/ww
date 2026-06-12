import Foundation

// MARK: - Config
/// SocialFeed 配置项，对应 Rust 的 Config struct（7 个字段）。
/// 支持 UserDefaults 持久化和从 Rust FFI 恢复状态。

struct Config: Sendable, Codable {
    /// 每页动态数量
    var pageSize: UInt64
    /// 缓存 TTL（秒）
    var cacheTtlSeconds: UInt64
    /// ProfileCache 上限
    var profileCacheCapacity: UInt64
    /// MomentCache 上限
    var momentCacheCapacity: UInt64
    /// 转发深度限制
    var maxForwardDepth: UInt64
    /// 是否自动提取 Markdown 图片
    var autoExtractImages: Bool
    /// 是否启用离线缓存
    var enableOfflineCache: Bool

    // MARK: - UserDefaults 持久化

    private static let defaultsKey = "social_feed_config"

    static func load() -> Config {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return .defaultConfig
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// 默认配置
    static let defaultConfig = Config(
        pageSize: 20,
        cacheTtlSeconds: 3600,
        profileCacheCapacity: 500,
        momentCacheCapacity: 2000,
        maxForwardDepth: 3,
        autoExtractImages: true,
        enableOfflineCache: false
    )
}

// MARK: - ConfigBuilder
/// 构建器模式，对应 Rust 的 ConfigBuilder

struct ConfigBuilder {
    private var config: Config

    init(from existing: Config = .defaultConfig) {
        self.config = existing
    }

    func pageSize(_ value: UInt64) -> ConfigBuilder {
        var b = self; b.config.pageSize = value; return b
    }

    func cacheTtl(_ seconds: UInt64) -> ConfigBuilder {
        var b = self; b.config.cacheTtlSeconds = seconds; return b
    }

    func profileCacheCapacity(_ value: UInt64) -> ConfigBuilder {
        var b = self; b.config.profileCacheCapacity = value; return b
    }

    func momentCacheCapacity(_ value: UInt64) -> ConfigBuilder {
        var b = self; b.config.momentCacheCapacity = value; return b
    }

    func maxForwardDepth(_ value: UInt64) -> ConfigBuilder {
        var b = self; b.config.maxForwardDepth = value; return b
    }

    func autoExtractImages(_ value: Bool) -> ConfigBuilder {
        var b = self; b.config.autoExtractImages = value; return b
    }

    func enableOfflineCache(_ value: Bool) -> ConfigBuilder {
        var b = self; b.config.enableOfflineCache = value; return b
    }

    func build() -> Config { config }
}