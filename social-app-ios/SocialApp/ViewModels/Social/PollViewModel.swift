import Foundation
import SwiftUI

// MARK: - PollOptionViewModel
/// 投票选项的可视化数据模型

struct PollOptionViewModel: Identifiable {
    let id: Int
    let text: String
    let voteCount: Int
    let isSelected: Bool
    let percentage: Double

    init(id: Int, text: String, voteCount: Int, isSelected: Bool, totalVotes: Int) {
        self.id = id
        self.text = text
        self.voteCount = voteCount
        self.isSelected = isSelected
        self.percentage = totalVotes > 0 ? (Double(voteCount) / Double(totalVotes)) * 100.0 : 0.0
    }
}

// MARK: - PollViewModel
/// 投票创建/投票/结束 ViewModel，对应 PollService。
/// 管理：当前投票选项、投票状态、倒计时、结果统计。

@MainActor
final class PollViewModel: ObservableObject {
    // MARK: - 发布状态

    @Published var roomId: String = ""
    @Published var poll: Poll?
    @Published var options: [PollOptionViewModel] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var timeRemaining: String?
    @Published var hasVoted: Bool = false
    @Published var isPollClosed: Bool = false

    // MARK: - Poll Creation State

    @Published var newQuestion: String = ""
    @Published var newOptions: [String] = ["", ""]
    @Published var allowsMultiple: Bool = false
    @Published var isAnonymous: Bool = true
    @Published var closesInHours: Int = 24
    @Published var isCreating: Bool = false

    // MARK: - 依赖

    private let pollService = PollService.shared
    private var timer: Timer?

    deinit {
        timer?.invalidate()
    }

    // MARK: - 加载投票

    func configure(roomId: String, pollId: String) {
        self.roomId = roomId
        loadPoll(pollId: pollId)
    }

    func loadPoll(pollId: String) {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        Task {
            do {
                let p = try await pollService.getPollDetail(pollId: pollId)
                await MainActor.run {
                    self.poll = p
                    self.updateOptions(from: p)
                    self.hasVoted = p.hasVoted
                    self.isPollClosed = p.isClosed
                    self.startCountdown(ifNeeded: p)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "加载投票失败: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 创建投票

    func createPoll() async throws -> Poll? {
        guard !newQuestion.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "请输入投票问题"
            return nil
        }
        let validOptions = newOptions
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard validOptions.count >= 2 else {
            errorMessage = "至少需要 2 个选项"
            return nil
        }

        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            let kind: PollKind = isAnonymous ? .undisclosed : .disclosed
            let poll = try await pollService.createPoll(
                roomId: roomId,
                question: newQuestion,
                answers: validOptions,
                maxSelections: UInt8(allowsMultiple ? validOptions.count : 1),
                kind: kind
            )

            await MainActor.run {
                self.poll = poll
                self.updateOptions(from: poll)
                self.resetCreationForm()
            }
            return poll
        } catch {
            await MainActor.run {
                self.errorMessage = "创建投票失败: \(error.localizedDescription)"
            }
            return nil
        }
    }

    // MARK: - 投票

    func castVote(optionIds: Set<Int>) async {
        guard let poll = poll, !poll.isClosed else { return }

        do {
            let success = try await pollService.castVote(pollId: poll.id, optionIds: optionIds)
            if success {
                await MainActor.run {
                    self.hasVoted = true
                }
                loadPoll(pollId: poll.id)
            }
        } catch {
            errorMessage = "投票失败: \(error.localizedDescription)"
        }
    }

    func retractVote() async {
        guard let poll = poll else { return }

        do {
            try await pollService.retractVote(pollId: poll.id)
            await MainActor.run {
                self.hasVoted = false
            }
            loadPoll(pollId: poll.id)
        } catch {
            errorMessage = "取消投票失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 结束投票

    func closePoll() async {
        guard let poll = poll else { return }

        do {
            try await pollService.closePoll(pollId: poll.id)
            await MainActor.run {
                self.isPollClosed = true
            }
            loadPoll(pollId: poll.id)
        } catch {
            errorMessage = "结束投票失败: \(error.localizedDescription)"
        }
    }

    func deletePoll() {
        guard let poll = poll else { return }
        pollService.deletePoll(pollId: poll.id)
        self.poll = nil
        self.options = []
    }

    // MARK: - 创建表单操作

    func addOption() {
        newOptions.append("")
    }

    func removeOption(at index: Int) {
        guard newOptions.count > 2 else { return }
        newOptions.remove(at: index)
    }

    func resetCreationForm() {
        newQuestion = ""
        newOptions = ["", ""]
        allowsMultiple = false
        isAnonymous = true
        closesInHours = 24
    }

    // MARK: - 辅助

    private func updateOptions(from poll: Poll) {
        let totalVotes = poll.totalVotes
        options = poll.options.map { opt in
            PollOptionViewModel(
                id: opt.id,
                text: opt.text,
                voteCount: opt.voteCount,
                isSelected: poll.myVote.contains(opt.id),
                totalVotes: totalVotes
            )
        }
    }

    private func startCountdown(ifNeeded poll: Poll) {
        timer?.invalidate()

        guard let closesAt = poll.closesAt, !poll.isClosed else {
            timeRemaining = nil
            return
        }

        let updateRemaining = { [weak self] in
            guard let self else { return }
            let remaining = closesAt.timeIntervalSince(Date())
            if remaining <= 0 {
                self.timeRemaining = "已结束"
                self.isPollClosed = true
                self.timer?.invalidate()
            } else {
                let hours = Int(remaining) / 3600
                let minutes = (Int(remaining) % 3600) / 60
                self.timeRemaining = "\(hours)小时\(minutes)分钟"
            }
        }

        updateRemaining()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            updateRemaining()
        }
    }

    // MARK: - 统计

    var totalVoteCount: Int {
        poll?.totalVotes ?? options.reduce(0) { $0 + $1.voteCount }
    }

    var leadingOption: PollOptionViewModel? {
        options.max(by: { $0.voteCount < $1.voteCount })
    }
}