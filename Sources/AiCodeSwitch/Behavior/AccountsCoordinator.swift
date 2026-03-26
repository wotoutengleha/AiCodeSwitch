import Foundation

actor AccountsCoordinator {
    static let expiredMarker = "codexswitcher.expired"

    private enum UsageRefreshPolicy {
        static let minimumRefreshIntervalSeconds: Int64 = 25

        static func shouldRefresh(_ snapshot: UsageSnapshot?, now: Int64, force: Bool) -> Bool {
            guard !force else { return true }
            guard let snapshot else { return true }
            return now - snapshot.fetchedAt >= minimumRefreshIntervalSeconds
        }
    }

    private let storeRepository: AccountsStoreRepository
    private let authRepository: AuthRepository
    private let usageService: UsageService
    private let accountConsumptionService: AccountConsumptionService
    private let chatGPTOAuthLoginService: ChatGPTOAuthLoginServiceProtocol
    private let codexCLIService: CodexCLIServiceProtocol
    private let openClawSwitchService: OpenClawSwitchServiceProtocol
    private let accountVault: AccountVault
    private let settingsCoordinator: SettingsCoordinator
    private let dateProvider: DateProviding

    init(
        storeRepository: AccountsStoreRepository,
        authRepository: AuthRepository,
        usageService: UsageService,
        accountConsumptionService: AccountConsumptionService,
        chatGPTOAuthLoginService: ChatGPTOAuthLoginServiceProtocol,
        codexCLIService: CodexCLIServiceProtocol,
        openClawSwitchService: OpenClawSwitchServiceProtocol = NoopOpenClawSwitchService(),
        accountVault: AccountVault,
        settingsCoordinator: SettingsCoordinator,
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.storeRepository = storeRepository
        self.authRepository = authRepository
        self.usageService = usageService
        self.accountConsumptionService = accountConsumptionService
        self.chatGPTOAuthLoginService = chatGPTOAuthLoginService
        self.codexCLIService = codexCLIService
        self.openClawSwitchService = openClawSwitchService
        self.accountVault = accountVault
        self.settingsCoordinator = settingsCoordinator
        self.dateProvider = dateProvider
    }

    func listAccounts() async throws -> [AccountSummary] {
        var store = try storeRepository.loadStore()
        let didChange = try await reconcileCurrentAuthIntoStore(&store)
        if didChange {
            try storeRepository.saveStore(store)
        }
        return orderedSummaries(from: store)
    }

    func currentAccountTokenCostState(now: Date = Date()) async -> CurrentAccountTokenCostState {
        do {
            var store = try storeRepository.loadStore()
            let didChange = try await reconcileCurrentAuthIntoStore(&store)
            if didChange {
                try storeRepository.saveStore(store)
            }

            guard let currentAccountID = authRepository.currentAuthAccountID() ?? store.currentSelection?.accountID else {
                return .idle
            }

            let authJSON: JSONValue
            if let currentAuth = try authRepository.readCurrentAuthOptional(),
               let extracted = try? authRepository.extractAuth(from: currentAuth),
               extracted.accountID == currentAccountID {
                authJSON = currentAuth
            } else {
                authJSON = try accountVault.loadAuth(for: currentAccountID)
            }

            var resolvedAuthJSON = authJSON
            var apiKey = normalizedValue(resolvedAuthJSON["OPENAI_API_KEY"]?.stringValue)

            if apiKey == nil,
               let refreshedTokens = try await chatGPTOAuthLoginService.refreshTokensIfPossible(from: resolvedAuthJSON),
               let refreshedAPIKey = normalizedValue(refreshedTokens.apiKey) {
                let refreshedAuth = try authRepository.makeChatGPTAuth(from: refreshedTokens)
                try accountVault.save(authJSON: refreshedAuth, for: currentAccountID)

                if let currentAuth = try authRepository.readCurrentAuthOptional(),
                   let extracted = try? authRepository.extractAuth(from: currentAuth),
                   extracted.accountID == currentAccountID {
                    try authRepository.writeCurrentAuth(refreshedAuth)
                }

                resolvedAuthJSON = refreshedAuth
                apiKey = refreshedAPIKey
            }

            if let apiKey {
                do {
                    let summary = try await accountConsumptionService.fetchSummary(apiKey: apiKey, now: now)
                    return .available(summary)
                } catch {
                    if let localFallback = await accountConsumptionService.fetchLocalSummary(now: now) {
                        return .available(localFallback)
                    }
                    if isAuthFailure(error) {
                        return .unavailable
                    }
                    return .failed(error.localizedDescription)
                }
            }

            if let localFallback = await accountConsumptionService.fetchLocalSummary(now: now) {
                return .available(localFallback)
            }
            return .unavailable
        } catch {
            if let localFallback = await accountConsumptionService.fetchLocalSummary(now: now) {
                return .available(localFallback)
            }
            if isAuthFailure(error) {
                return .unavailable
            }
            return .failed(error.localizedDescription)
        }
    }

    func currentAccountLocalTokenCostState(now: Date = Date()) async -> CurrentAccountTokenCostState {
        if let localFallback = await accountConsumptionService.fetchLocalSummary(now: now) {
            return .available(localFallback)
        }

        do {
            var store = try storeRepository.loadStore()
            let didChange = try await reconcileCurrentAuthIntoStore(&store)
            if didChange {
                try storeRepository.saveStore(store)
            }

            guard authRepository.currentAuthAccountID() ?? store.currentSelection?.accountID != nil else {
                return .idle
            }
            return .unavailable
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func addAccountViaLogin() async throws -> AccountSummary {
        let tokens = try await chatGPTOAuthLoginService.signInWithChatGPT(timeoutSeconds: 10 * 60)
        let authJSON = try authRepository.makeChatGPTAuth(from: tokens)
        return try await importAccount(authJSON: authJSON, makeCurrent: false, preservingLocalID: nil)
    }

    @discardableResult
    func repairAccount(id: String) async throws -> AccountSummary {
        let store = try storeRepository.loadStore()
        guard let existing = store.accounts.first(where: { $0.id == id }) else {
            throw AppError.invalidData("Account not found.")
        }

        let tokens = try await chatGPTOAuthLoginService.signInWithChatGPT(timeoutSeconds: 10 * 60)
        let authJSON = try authRepository.makeChatGPTAuth(from: tokens)
        let repaired = try await importAccount(authJSON: authJSON, makeCurrent: false, preservingLocalID: existing.id)

        if repaired.accountID != existing.accountID {
            try? accountVault.removeAuth(for: existing.accountID)
        }
        return repaired
    }

    func switchAccountAndApplySettings(id: String, workspacePath: String? = nil) async throws -> SwitchAccountExecutionResult {
        let store = try storeRepository.loadStore()
        guard let account = store.accounts.first(where: { $0.id == id }) else {
            throw AppError.invalidData("Account not found.")
        }

        let authJSON = try accountVault.loadAuth(for: account.accountID)
        try authRepository.writeCurrentAuth(authJSON)

        var nextStore = store
        nextStore.currentSelection = CurrentAccountSelection(
            accountID: account.accountID,
            selectedAt: dateProvider.unixMillisecondsNow(),
            sourceDeviceID: "macos-local"
        )
        try storeRepository.saveStore(nextStore)

        let settings = try await settingsCoordinator.currentSettings()
        var result = SwitchAccountExecutionResult.idle
        if settings.launchCodexAfterSwitch {
            result.usedFallbackCLI = try codexCLIService.launchApp(workspacePath: workspacePath)
        }
        if settings.syncOpenClawOnSwitch {
            let openClawResult = await openClawSwitchService.syncCodexAccount(
                email: account.email,
                accountID: account.accountID
            )
            result.openClawSynced = openClawResult.synced
            result.openClawSyncWarning = openClawResult.warning
            result.openClawSyncError = openClawResult.error
        }
        return result
    }

    func refreshAllUsage(
        force: Bool,
        onPartialUpdate: @escaping @Sendable ([AccountSummary]) async -> Void
    ) async throws -> [AccountSummary] {
        var store = try storeRepository.loadStore()
        _ = try await reconcileCurrentAuthIntoStore(&store)

        let currentAccountID = authRepository.currentAuthAccountID() ?? store.currentSelection?.accountID
        let orderedAccounts = store.accounts.sorted { left, right in
            if left.accountID == currentAccountID { return true }
            if right.accountID == currentAccountID { return false }

            let leftSummary = AccountsStore(accounts: [left]).accountSummaries(currentAccountID: currentAccountID)[0]
            let rightSummary = AccountsStore(accounts: [right]).accountSummaries(currentAccountID: currentAccountID)[0]
            let leftScore = leftSummary.requiresReLogin ? -1 : AccountRanking.remainingScore(for: leftSummary)
            let rightScore = rightSummary.requiresReLogin ? -1 : AccountRanking.remainingScore(for: rightSummary)
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            return left.addedAt < right.addedAt
        }

        let now = dateProvider.unixSecondsNow()
        for account in orderedAccounts {
            guard let index = store.accounts.firstIndex(where: { $0.id == account.id }) else { continue }
            guard UsageRefreshPolicy.shouldRefresh(store.accounts[index].usage, now: now, force: force) else {
                continue
            }

            do {
                let authJSON = try accountVault.loadAuth(for: account.accountID)
                let extracted = try authRepository.extractAuth(from: authJSON)
                let usage = try await usageService.fetchUsage(
                    accessToken: extracted.accessToken,
                    accountID: extracted.accountID
                )
                store.accounts[index].usage = usage
                store.accounts[index].usageError = nil
                store.accounts[index].updatedAt = now
                store.accounts[index].email = extracted.email ?? store.accounts[index].email
                store.accounts[index].planType = extracted.planType ?? store.accounts[index].planType
                store.accounts[index].teamName = extracted.teamName ?? store.accounts[index].teamName
            } catch {
                store.accounts[index].updatedAt = now
                if isAuthFailure(error) {
                    store.accounts[index].usageError = Self.expiredMarker
                } else {
                    store.accounts[index].usageError = error.localizedDescription
                }
            }

            try storeRepository.saveStore(store)
            await onPartialUpdate(orderedSummaries(from: store))
        }

        return orderedSummaries(from: store)
    }

    func deleteAccount(id: String) throws {
        var store = try storeRepository.loadStore()
        guard let account = store.accounts.first(where: { $0.id == id }) else { return }
        store.accounts.removeAll { $0.id == id }
        if store.currentSelection?.accountID == account.accountID {
            store.currentSelection = nil
        }
        try storeRepository.saveStore(store)
        try? accountVault.removeAuth(for: account.accountID)
    }

    func updateTeamAlias(id: String, alias: String?) throws -> AccountSummary {
        var store = try storeRepository.loadStore()
        guard let index = store.accounts.firstIndex(where: { $0.id == id }) else {
            throw AppError.invalidData("Account not found.")
        }

        store.accounts[index].teamAlias = normalizedValue(alias)
        store.accounts[index].updatedAt = dateProvider.unixSecondsNow()
        try storeRepository.saveStore(store)
        return orderedSummaries(from: store).first(where: { $0.id == id })!
    }

    private func importAccount(
        authJSON: JSONValue,
        makeCurrent: Bool,
        preservingLocalID: String?
    ) async throws -> AccountSummary {
        let extracted = try authRepository.extractAuth(from: authJSON)
        var usage: UsageSnapshot?
        var usageError: String?

        do {
            usage = try await usageService.fetchUsage(
                accessToken: extracted.accessToken,
                accountID: extracted.accountID
            )
        } catch {
            usageError = isAuthFailure(error) ? Self.expiredMarker : error.localizedDescription
        }

        var store = try storeRepository.loadStore()
        let now = dateProvider.unixSecondsNow()

        let localID = preservingLocalID
            ?? store.accounts.first(where: { $0.accountID == extracted.accountID })?.id
            ?? UUID().uuidString

        let placeholderAuth = JSONValue.null
        let label = extracted.email ?? "Codex \(String(extracted.accountID.prefix(8)))"
        let replacement = StoredAccount(
            id: localID,
            label: label,
            email: extracted.email,
            accountID: extracted.accountID,
            planType: extracted.planType,
            teamName: extracted.teamName,
            teamAlias: store.accounts.first(where: { $0.id == localID })?.teamAlias,
            authJSON: placeholderAuth,
            addedAt: store.accounts.first(where: { $0.id == localID })?.addedAt ?? now,
            updatedAt: now,
            usage: usage,
            usageError: usageError
        )

        if let index = store.accounts.firstIndex(where: { $0.id == localID || $0.accountID == extracted.accountID }) {
            store.accounts[index] = replacement
        } else {
            store.accounts.append(replacement)
        }

        if makeCurrent {
            store.currentSelection = CurrentAccountSelection(
                accountID: extracted.accountID,
                selectedAt: dateProvider.unixMillisecondsNow(),
                sourceDeviceID: "macos-local"
            )
            try authRepository.writeCurrentAuth(authJSON)
        }

        try accountVault.save(authJSON: authJSON, for: extracted.accountID)
        try storeRepository.saveStore(store)

        return orderedSummaries(from: store).first(where: { $0.id == localID })!
    }

    @discardableResult
    private func reconcileCurrentAuthIntoStore(_ store: inout AccountsStore) async throws -> Bool {
        guard let authJSON = try authRepository.readCurrentAuthOptional() else { return false }
        let extracted = try authRepository.extractAuth(from: authJSON)
        let now = dateProvider.unixSecondsNow()
        var didChange = false

        try accountVault.save(authJSON: authJSON, for: extracted.accountID)

        if let index = store.accounts.firstIndex(where: { $0.accountID == extracted.accountID }) {
            if store.accounts[index].email != extracted.email {
                store.accounts[index].email = extracted.email
                didChange = true
            }
            if store.accounts[index].planType != extracted.planType {
                store.accounts[index].planType = extracted.planType
                didChange = true
            }
            if normalizedValue(store.accounts[index].teamName) != normalizedValue(extracted.teamName) {
                store.accounts[index].teamName = normalizedValue(extracted.teamName)
                didChange = true
            }
            if store.accounts[index].label != (extracted.email ?? store.accounts[index].label) {
                store.accounts[index].label = extracted.email ?? store.accounts[index].label
                didChange = true
            }
            store.accounts[index].updatedAt = now
        } else {
            let placeholder = StoredAccount(
                id: UUID().uuidString,
                label: extracted.email ?? "Codex \(String(extracted.accountID.prefix(8)))",
                email: extracted.email,
                accountID: extracted.accountID,
                planType: extracted.planType,
                teamName: normalizedValue(extracted.teamName),
                teamAlias: nil,
                authJSON: .null,
                addedAt: now,
                updatedAt: now,
                usage: nil,
                usageError: nil
            )
            store.accounts.append(placeholder)
            didChange = true
        }

        if store.currentSelection?.accountID != extracted.accountID {
            store.currentSelection = CurrentAccountSelection(
                accountID: extracted.accountID,
                selectedAt: dateProvider.unixMillisecondsNow(),
                sourceDeviceID: "macos-local"
            )
            didChange = true
        }

        return didChange
    }

    private func orderedSummaries(from store: AccountsStore) -> [AccountSummary] {
        let currentAccountID = authRepository.currentAuthAccountID() ?? store.currentSelection?.accountID
        let summaries = store.accountSummaries(currentAccountID: currentAccountID)
        return AccountRanking.sortForDisplay(summaries).sorted { left, right in
            if left.isCurrent != right.isCurrent {
                return left.isCurrent
            }
            if left.requiresReLogin != right.requiresReLogin {
                return !left.requiresReLogin
            }

            let leftScore = AccountRanking.remainingScore(for: left)
            let rightScore = AccountRanking.remainingScore(for: right)
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            return left.addedAt < right.addedAt
        }
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isAuthFailure(_ error: Error) -> Bool {
        if let appError = error as? AppError, case .unauthorized = appError {
            return true
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("401") || message.contains("unauthorized") || message.contains("token")
    }
}

private struct NoopOpenClawSwitchService: OpenClawSwitchServiceProtocol {
    func syncCodexAccount(email: String?, accountID: String) async -> OpenClawSwitchExecutionResult {
        _ = email
        _ = accountID
        return .notRequested
    }
}

extension AccountSummary {
    var requiresReLogin: Bool {
        usageError == AccountsCoordinator.expiredMarker
    }
}
