import Foundation

// MARK: - ProfileCache
/// Swift 侧本地用户资料缓存，带 TTL 和 LRU 淘汰，减少对 Homeserver 的重复查询。

final class ProfileCache: @unchecked Sendable {
    static let shared = ProfileCache()

    private var storage: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []
    private let capacity: Int
    private let ttl: TimeInterval
    private let lock = NSLock()

    /// 从 Config 读取容量，TTL 默认 3600s；房间缓存容量同用户缓存，TTL 默认 1 小时
    init(capacity: Int? = nil, ttl: TimeInterval = 3600, roomTtl: TimeInterval = 3600) {
        self.capacity = capacity ?? Int(Config.load().profileCacheCapacity)
        self.ttl = ttl
        self.roomCapacity = capacity ?? Int(Config.load().profileCacheCapacity)
        self.roomTtl = roomTtl
    }

    /// 获取缓存的 Profile。若过期返回 nil 并自动失效。
    func get(userId: String) -> UserProfile? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = storage[userId] else { return nil }
        if Date().timeIntervalSince(entry.cachedAt) > ttl {
            storage.removeValue(forKey: userId)
            accessOrder.removeAll { $0 == userId }
            return nil
        }
        // LRU: 移到最后
        accessOrder.removeAll { $0 == userId }
        accessOrder.append(userId)
        return entry.profile
    }

    /// 设置缓存的 Profile
    func set(userId: String, profile: UserProfile) {
        lock.lock(); defer { lock.unlock() }
        // 已存在则更新
        if storage[userId] != nil {
            accessOrder.removeAll { $0 == userId }
        }
        storage[userId] = CacheEntry(profile: profile, cachedAt: Date())
        accessOrder.append(userId)
        // LRU 淘汰
        while accessOrder.count > capacity {
            let oldest = accessOrder.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    /// 使单个条目失效
    func invalidate(userId: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: userId)
        accessOrder.removeAll { $0 == userId }
    }

    /// 批量失效
    func invalidateBatch(userIds: [String]) {
        lock.lock(); defer { lock.unlock() }
        for userId in userIds {
            storage.removeValue(forKey: userId)
        }
        accessOrder.removeAll { userIds.contains($0) }
    }

    /// 全量清空
    func clear() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
        accessOrder.removeAll()
    }

    /// 清理过期条目（用户缓存 + 房间缓存）
    func cleanup() {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        // 清理用户缓存过期条目
        let expired = storage.filter { now.timeIntervalSince($0.value.cachedAt) > ttl }
        for (userId, _) in expired {
            storage.removeValue(forKey: userId)
        }
        accessOrder.removeAll { expired.keys.contains($0) }

        // 清理房间缓存过期条目
        roomLock.lock()
        defer { roomLock.unlock() }
        let expiredRooms = roomStorage.filter { now.timeIntervalSince($0.value.cachedAt) > roomTtl }
        for (roomId, _) in expiredRooms {
            roomStorage.removeValue(forKey: roomId)
        }
        roomAccessOrder.removeAll { expiredRooms.keys.contains($0) }
    }

    /// 统计信息
    var size: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }

    // MARK: - RoomProfile 缓存

    private var roomStorage: [String: RoomCacheEntry] = [:]
    private var roomAccessOrder: [String] = []
    private let roomCapacity: Int
    private let roomTtl: TimeInterval
    private let roomLock = NSLock()

    /// RoomProfile 结构体，缓存房间头像与显示名
    struct RoomProfile: Sendable {
        let roomId: String
        let displayName: String
        let avatarUrl: URL?
    }

    private struct RoomCacheEntry {
        let profile: RoomProfile
        let cachedAt: Date
    }

    // MARK: - Room 缓存方法

    /// 获取房间缓存，过期返回 nil 并自动清理
    func getRoom(roomId: String) -> RoomProfile? {
        roomLock.lock(); defer { roomLock.unlock() }
        guard let entry = roomStorage[roomId] else { return nil }
        if Date().timeIntervalSince(entry.cachedAt) > roomTtl {
            roomStorage.removeValue(forKey: roomId)
            roomAccessOrder.removeAll { $0 == roomId }
            return nil
        }
        roomAccessOrder.removeAll { $0 == roomId }
        roomAccessOrder.append(roomId)
        return entry.profile
    }

    /// 设置房间缓存
    func setRoom(roomId: String, profile: RoomProfile) {
        roomLock.lock(); defer { roomLock.unlock() }
        if roomStorage[roomId] != nil {
            roomAccessOrder.removeAll { $0 == roomId }
        }
        roomStorage[roomId] = RoomCacheEntry(profile: profile, cachedAt: Date())
        roomAccessOrder.append(roomId)
        while roomAccessOrder.count > roomCapacity {
            let oldest = roomAccessOrder.removeFirst()
            roomStorage.removeValue(forKey: oldest)
        }
    }

    /// 使单个房间缓存失效
    func invalidateRoom(roomId: String) {
        roomLock.lock(); defer { roomLock.unlock() }
        roomStorage.removeValue(forKey: roomId)
        roomAccessOrder.removeAll { $0 == roomId }
    }

    /// 全量清空房间缓存
    func clearRooms() {
        roomLock.lock(); defer { roomLock.unlock() }
        roomStorage.removeAll()
        roomAccessOrder.removeAll()
    }

    // MARK: - 搜索结果缓存（关键词 → 用户列表，TTL 5 分钟）

    private var searchStorage: [String: SearchCacheEntry] = [:]
    private var searchAccessOrder: [String] = []   // LRU 访问顺序
    private let searchCapacity: Int = 50            // 搜索缓存容量上限
    private let searchTtl: TimeInterval = 300
    private let searchLock = NSLock()

    private struct SearchCacheEntry {
        let results: [SearchedUser]
        let cachedAt: Date
    }

    /// 获取搜索缓存（关键词已做标准化，LRU 更新）
    func getSearch(keyword: String) -> [SearchedUser]? {
        searchLock.lock(); defer { searchLock.unlock() }
        let key = keyword.lowercased().trimmingCharacters(in: .whitespaces)
        guard let entry = searchStorage[key] else { return nil }
        if Date().timeIntervalSince(entry.cachedAt) > searchTtl {
            searchStorage.removeValue(forKey: key)
            searchAccessOrder.removeAll { $0 == key }
            return nil
        }
        // LRU: 移到末尾表示最近访问
        searchAccessOrder.removeAll { $0 == key }
        searchAccessOrder.append(key)
        return entry.results
    }

    /// 设置搜索缓存（LRU 淘汰，容量上限 searchCapacity）
    func setSearch(keyword: String, results: [SearchedUser]) {
        searchLock.lock(); defer { searchLock.unlock() }
        let key = keyword.lowercased().trimmingCharacters(in: .whitespaces)
        if searchStorage[key] != nil {
            searchAccessOrder.removeAll { $0 == key }
        }
        searchStorage[key] = SearchCacheEntry(results: results, cachedAt: Date())
        searchAccessOrder.append(key)
        // LRU 淘汰：超出容量时移除最久未访问的条目
        while searchAccessOrder.count > searchCapacity {
            let oldest = searchAccessOrder.removeFirst()
            searchStorage.removeValue(forKey: oldest)
        }
    }

    /// 清空搜索缓存
    func clearSearchCache() {
        searchLock.lock(); defer { searchLock.unlock() }
        searchStorage.removeAll()
        searchAccessOrder.removeAll()
    }

    private struct CacheEntry {
        let profile: UserProfile
        let cachedAt: Date
    }
}