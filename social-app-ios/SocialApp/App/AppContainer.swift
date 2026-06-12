import Foundation

// MARK: - AppContainer
/// 依赖注入容器，管理所有 Service 单例和 ViewModel 工厂。
/// 使用 Service Locator 模式，解耦 Service 单例的直接引用。

@MainActor
final class AppContainer {
    static let shared = AppContainer()

    // MARK: - Services（懒加载单例）

    /// 社交动态服务
    lazy var socialFeedService: SocialFeedService = {
        SocialFeedService.shared
    }()

    /// 好友管理服务
    lazy var friendService: FriendService = {
        FriendService.shared
    }()

    /// 即时通讯服务
    lazy var messageService: MessageService = {
        MessageService.shared
    }()

    /// 空间管理服务
    lazy var spacesService: SpacesService = {
        SpacesService.shared
    }()

    /// 房间设置服务（房间昵称、头像等）
    lazy var roomSettingsService: RoomSettingsService = {
        RoomSettingsService.shared
    }()

    /// 消息线程服务
    lazy var threadService: ThreadService = {
        ThreadService.shared
    }()

    /// 投票问卷服务
    lazy var pollService: PollService = {
        PollService.shared
    }()

    /// 消息搜索服务
    lazy var messageSearchService: MessageSearchService = {
        MessageSearchService.shared
    }()

    /// 房间目录搜索服务
    lazy var roomDirectoryService: RoomDirectoryService = {
        RoomDirectoryService.shared
    }()

    /// 二维码登录服务
    lazy var qrLoginService: QRLoginService = {
        QRLoginService.shared
    }()

    /// 已读回执服务
    lazy var readReceiptService: ReadReceiptService = {
        ReadReceiptService.shared
    }()

    /// 回应/表情服务
    lazy var reactionService: ReactionService = {
        ReactionService.shared
    }()

    /// 实时位置共享服务
    lazy var liveLocationService: LiveLocationService = {
        LiveLocationService.shared
    }()

    /// 房间列表管理服务
    lazy var roomListService: RoomListService = {
        RoomListService.shared
    }()

    /// 聚合缓存服务
    lazy var aggregationCache: AggregationCache = {
        AggregationCache.shared
    }()

    /// 速率限制器
    lazy var rateLimiter: RateLimiter = {
        RateLimiter.shared
    }()

    /// 用户资料缓存（单例，容量由 Config.profileCacheCapacity 控制）
    lazy var profileCache: ProfileCache = {
        .shared
    }()

    /// 图片上传服务
    lazy var imageUploadService: ImageUploadService = {
        ImageUploadService.shared
    }()

    /// 多媒体处理器
    lazy var mediaProcessor: MediaProcessor = {
        MediaProcessor()
    }()

    /// Keychain 管理器
    lazy var keychainManager: KeychainManager = {
        KeychainManager.shared
    }()

    /// 认证生命周期管理器
    lazy var authManager: AuthManager = {
        AuthManager.shared
    }()

    // MARK: - ViewModel 工厂

    /// 创建 FeedViewModel（注入 socialFeedService）
    func makeFeedViewModel() -> FeedViewModel {
        FeedViewModel()
    }

    /// 创建 DiscoverViewModel
    func makeDiscoverViewModel() -> DiscoverViewModel {
        DiscoverViewModel()
    }

    /// 创建 ProfileViewModel
    func makeProfileViewModel() -> ProfileViewModel {
        ProfileViewModel()
    }

    /// 创建 MessageSearchViewModel（注入 messageSearchService）
    func makeMessageSearchViewModel() -> MessageSearchViewModel {
        MessageSearchViewModel()
    }

    /// 创建 RoomDirectoryViewModel（注入 roomDirectoryService）
    func makeRoomDirectoryViewModel() -> RoomDirectoryViewModel {
        RoomDirectoryViewModel()
    }

    /// 创建 QRLoginViewModel（注入 qrLoginService）
    func makeQRLoginViewModel() -> QRLoginViewModel {
        QRLoginViewModel()
    }

    /// 创建 LiveLocationViewModel（注入 liveLocationService）
    func makeLiveLocationViewModel() -> LiveLocationViewModel {
        LiveLocationViewModel()
    }

    /// 创建 RoomListViewModel（注入 roomListService）
    func makeRoomListViewModel() -> RoomListViewModel {
        RoomListViewModel()
    }

    /// 创建 ContactsViewModel
    func makeContactsViewModel() -> ContactsViewModel {
        ContactsViewModel()
    }

    /// 创建 AddFriendViewModel
    func makeAddFriendViewModel() -> AddFriendViewModel {
        AddFriendViewModel()
    }

    /// 创建 CallViewModel
    func makeCallViewModel() -> CallViewModel {
        CallViewModel()
    }

    /// 创建 ConversationViewModel（注入 messageService）
    func makeConversationViewModel() -> ConversationViewModel {
        ConversationViewModel()
    }

    /// 创建 SettingsViewModel
    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel()
    }

    // MARK: - 配置

    /// 应用配置
    lazy var appConfig: Config = {
        ConfigBuilder().build()
    }()

    /// 初始化所有服务
    func initialize() async {
        // 预加载 Keychain
        _ = keychainManager
        // 预加载配置
        _ = appConfig
        // 预加载认证管理器
        _ = authManager
    }
}