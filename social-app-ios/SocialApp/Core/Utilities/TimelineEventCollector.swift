import Foundation

// MARK: - TimelineEventCollector
// TimelineListener 实现，用于收集 Timeline 中的 EventTimelineItem。
//
// 背景：FFI 的 paginateBackwards(numEvents:) 仅返回 Bool（是否到达起点），
// 不返回事件列表。事件通过 TimelineListener.onUpdate(diff:) 回调到达，
// 需通过此收集器在 Swift 侧缓存事件，再做本地筛选或转换。
//
// 线程安全：onUpdate 可能从非主线程调用，内部使用 NSLock 保护 events 数组。
// 使用方式：
//   let collector = TimelineEventCollector()
//   let _ = await timeline.addListener(listener: collector)
//   let _ = try await timeline.paginateBackwards(numEvents: 50)
//   let events = collector.events  // 已收集的事件列表

final class TimelineEventCollector: TimelineListener, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [EventTimelineItem] = []

    /// 当前已收集的事件列表（线程安全）
    var events: [EventTimelineItem] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    func onUpdate(diff: [TimelineDiff]) {
        lock.lock()
        defer { lock.unlock() }
        for d in diff {
            switch d {
            case .append(let values):
                for item in values {
                    if let event = item.asEvent() {
                        _events.append(event)
                    }
                }
            case .reset(let values):
                _events = values.compactMap { $0.asEvent() }
            case .pushBack(let value):
                if let event = value.asEvent() {
                    _events.append(event)
                }
            case .pushFront(let value):
                if let event = value.asEvent() {
                    _events.insert(event, at: 0)
                }
            case .set(let index, let value):
                if let event = value.asEvent() {
                    let idx = Int(index)
                    if idx < _events.count {
                        _events[idx] = event
                    }
                }
            case .insert(let index, let value):
                if let event = value.asEvent() {
                    let idx = Int(index)
                    if idx <= _events.count {
                        _events.insert(event, at: idx)
                    }
                }
            case .remove(let index):
                let idx = Int(index)
                if idx < _events.count {
                    _events.remove(at: idx)
                }
            case .truncate(let length):
                let len = Int(length)
                if len < _events.count {
                    _events = Array(_events.prefix(len))
                }
            case .clear:
                _events.removeAll()
            case .popFront:
                if !_events.isEmpty {
                    _events.removeFirst()
                }
            case .popBack:
                if !_events.isEmpty {
                    _events.removeLast()
                }
            }
        }
    }
}
