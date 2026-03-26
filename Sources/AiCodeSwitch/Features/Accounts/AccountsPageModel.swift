import Foundation
import Combine

@MainActor
final class AccountsPageModel: ObservableObject {
    private let coordinator: AccountsCoordinator
    private let noticeScheduler = NoticeAutoDismissScheduler()
    private var hasLoaded = false
    private var autoRefreshTask: Task<Void, Never>?
    private var tokenCostRefreshTask: Task<Void, Never>?
    private var addAccountTask: Task<Void, Never>?
    private var activeAddAccountRequestID: UUID?
    private var configuredAutoRefreshIntervalMinutes: Int?

    @Published private(set) var accounts: [AccountSummary] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isAdding = false
    @Published private(set) var currentTokenCostState: CurrentAccountTokenCostState = .idle
    @Published var switchingAccountID: String?
    @Published var notice: NoticeMessage? {
        didSet {
            noticeScheduler.schedule(notice) { [weak self] in
                self?.notice = nil
            }
        }
    }

    init(coordinator: AccountsCoordinator) {
        self.coordinator = coordinator
    }

    deinit {
        autoRefreshTask?.cancel()
        tokenCostRefreshTask?.cancel()
        addAccountTask?.cancel()
    }

    var currentAccount: AccountSummary? {
        accounts.first(where: \.isCurrent)
    }

    var switchableAccounts: [AccountSummary] {
        accounts.filter { !$0.isCurrent }
    }

    var hasQuotaWarning: Bool {
        quotaWarningText != nil
    }

    var quotaWarningText: String? {
        guard let currentAccount else { return nil }

        if remainingPercent(for: currentAccount.usage?.fiveHour) <= 10 {
            return L10n.tr("switcher.warning.five_hour_low")
        }

        if remainingPercent(for: currentAccount.usage?.oneWeek) <= 15 {
            return L10n.tr("switcher.warning.week_low")
        }

        return nil
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            accounts = try await coordinator.listAccounts()
            await refreshCurrentTokenCost(showLoading: false)
            await refreshUsage(showNotice: false)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func refreshUsage(showNotice: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let latest = try await coordinator.refreshAllUsage(force: true) { [weak self] accounts in
                await MainActor.run {
                    self?.accounts = accounts
                }
            }
            accounts = latest
            await refreshCurrentTokenCost(showLoading: false)
            if showNotice {
                notice = NoticeMessage(style: .info, text: L10n.tr("switcher.notice.refreshed"))
            }
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func addAccountViaLogin() {
        guard !isAdding else {
            cancelAddAccount()
            return
        }

        let requestID = UUID()
        activeAddAccountRequestID = requestID
        isAdding = true
        addAccountTask?.cancel()
        addAccountTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                let imported = try await self.coordinator.addAccountViaLogin()
                let refreshedAccounts = try await self.coordinator.refreshAllUsage(force: true) { [weak self] accounts in
                    await MainActor.run {
                        guard let self, self.activeAddAccountRequestID == requestID else { return }
                        self.accounts = accounts
                    }
                }
                await MainActor.run {
                    guard self.activeAddAccountRequestID == requestID else { return }
                    self.accounts = refreshedAccounts
                }
                await self.finishAddAccountSuccess(requestID: requestID, importedLabel: imported.label)
            } catch {
                await self.finishAddAccountFailure(requestID: requestID, error: error)
            }
        }
    }

    func cancelAddAccount() {
        guard isAdding else { return }
        activeAddAccountRequestID = nil
        addAccountTask?.cancel()
        addAccountTask = nil
        isAdding = false
    }

    func performPrimaryAction(for account: AccountSummary) async {
        if account.requiresReLogin {
            await repairAccount(id: account.id)
        } else {
            await switchAccount(id: account.id)
        }
    }

    func deleteAccount(id: String) async {
        do {
            try await coordinator.deleteAccount(id: id)
            accounts = try await coordinator.listAccounts()
            notice = NoticeMessage(style: .info, text: L10n.tr("accounts.notice.account_deleted"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func switchAccount(id: String) async {
        switchingAccountID = id
        defer { switchingAccountID = nil }

        do {
            let result = try await coordinator.switchAccountAndApplySettings(id: id)
            accounts = try await coordinator.listAccounts()
            await refreshCurrentTokenCost(showLoading: true)
            if let error = result.openClawSyncError {
                notice = NoticeMessage(style: .error, text: L10n.tr("switcher.notice.switched_openclaw_error", error))
            } else if let warning = result.openClawSyncWarning {
                notice = NoticeMessage(style: .info, text: L10n.tr("switcher.notice.switched_openclaw_warning", warning))
            } else if result.openClawSynced {
                notice = NoticeMessage(style: .success, text: L10n.tr("switcher.notice.switched_openclaw_synced"))
            } else {
                notice = NoticeMessage(style: .success, text: L10n.tr("switcher.notice.switched"))
            }
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func repairAccount(id: String) async {
        switchingAccountID = id
        defer { switchingAccountID = nil }

        do {
            let repaired = try await coordinator.repairAccount(id: id)
            accounts = try await coordinator.refreshAllUsage(force: true) { [weak self] accounts in
                await MainActor.run {
                    self?.accounts = accounts
                }
            }
            await refreshCurrentTokenCost(showLoading: false)
            notice = NoticeMessage(style: .success, text: L10n.tr("switcher.notice.repaired", repaired.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func reauthorizeCurrentAccount() async {
        guard let currentAccount else { return }
        await repairAccount(id: currentAccount.id)
    }

    func configureAutoRefresh(intervalMinutes: Int) {
        let normalizedInterval = AppSettings.normalizedAutoRefreshInterval(intervalMinutes)
        guard configuredAutoRefreshIntervalMinutes != normalizedInterval || autoRefreshTask == nil else { return }

        configuredAutoRefreshIntervalMinutes = normalizedInterval
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let sleepNanoseconds = UInt64(normalizedInterval) * 60 * 1_000_000_000
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
                guard !Task.isCancelled else { break }
                guard let self else { break }
                guard self.hasLoaded else { continue }
                await self.refreshUsage(showNotice: false)
            }
        }
    }

    private func refreshCurrentTokenCost(showLoading: Bool) async {
        guard let currentAccount else {
            tokenCostRefreshTask?.cancel()
            currentTokenCostState = .idle
            return
        }

        let accountID = currentAccount.id
        tokenCostRefreshTask?.cancel()

        let localState = await coordinator.currentAccountLocalTokenCostState()
        if case .available = localState {
            currentTokenCostState = localState
        } else if showLoading || {
            if case .idle = currentTokenCostState { return true }
            return false
        }() {
            currentTokenCostState = .loading
        }

        tokenCostRefreshTask = Task { [weak self] in
            guard let self else { return }
            let resolvedState = await coordinator.currentAccountTokenCostState()
            guard !Task.isCancelled else { return }
            guard self.currentAccount?.id == accountID else { return }
            self.currentTokenCostState = resolvedState
        }
    }

    private func remainingPercent(for window: UsageWindow?) -> Double {
        guard let used = window?.usedPercent else { return 100 }
        return max(0, 100 - used)
    }

    private func finishAddAccountSuccess(requestID: UUID, importedLabel: String) async {
        guard activeAddAccountRequestID == requestID else { return }
        activeAddAccountRequestID = nil
        addAccountTask = nil
        isAdding = false
        await refreshCurrentTokenCost(showLoading: false)
        notice = NoticeMessage(style: .success, text: L10n.tr("switcher.notice.added", importedLabel))
    }

    private func finishAddAccountFailure(requestID: UUID, error: Error) async {
        guard activeAddAccountRequestID == requestID else { return }
        activeAddAccountRequestID = nil
        addAccountTask = nil
        isAdding = false

        if let appError = error as? AppError,
           case .io(let message) = appError,
           message == L10n.tr("error.oauth.request_cancelled") {
            return
        }

        if error is CancellationError {
            return
        }

        notice = NoticeMessage(style: .error, text: error.localizedDescription)
    }
}
