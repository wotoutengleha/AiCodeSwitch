import XCTest
@testable import AiCodeSwitch

final class AccountsCoordinatorTests: XCTestCase {
    func testListAccountsAutoImportsCurrentAuthIntoStore() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = InMemoryAccountsStoreRepository(store: AccountsStore())
        let authRepository = StubAuthRepository(
            currentAuth: .object(["account_id": .string("account-1")]),
            currentAccountID: "account-1",
            extractedByAccountID: [
                "account-1": ExtractedAuth(
                    accountID: "account-1",
                    accessToken: "token-1",
                    email: "current@example.com",
                    planType: "team",
                    teamName: "workspace-a"
                )
            ]
        )
        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: authRepository,
            usageService: RecordingUsageService(resultByAccountID: [:]),
            accountConsumptionService: StubAccountConsumptionService(),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            accountVault: InMemoryAccountVault(),
            settingsCoordinator: SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: StubLaunchAtStartupService()
            ),
            dateProvider: FixedDateProvider(now: now)
        )

        let accounts = try await coordinator.listAccounts()
        let store = try storeRepository.loadStore()

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.email, "current@example.com")
        XCTAssertEqual(accounts.first?.teamName, "workspace-a")
        XCTAssertTrue(accounts.first?.isCurrent == true)
        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.currentSelection?.accountID, "account-1")
    }

    func testRefreshAllUsageHonorsThrottleUnlessForced() async throws {
        let now: Int64 = 1_763_216_000
        let existingUsage = UsageSnapshot(
            fetchedAt: now,
            planType: "pro",
            fiveHour: UsageWindow(usedPercent: 30, windowSeconds: 18_000, resetAt: now + 600),
            oneWeek: UsageWindow(usedPercent: 25, windowSeconds: 604_800, resetAt: now + 86_400),
            credits: nil
        )
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Primary",
                        email: "primary@example.com",
                        accountID: "account-1",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .null,
                        addedAt: now,
                        updatedAt: now,
                        usage: existingUsage,
                        usageError: nil
                    )
                ],
                currentSelection: CurrentAccountSelection(
                    accountID: "account-1",
                    selectedAt: now * 1_000,
                    sourceDeviceID: "macos-local"
                ),
                settings: .defaultValue
            )
        )
        let usageService = RecordingUsageService(
            resultByAccountID: [
                "account-1": UsageSnapshot(
                    fetchedAt: now + 1,
                    planType: "pro",
                    fiveHour: UsageWindow(usedPercent: 10, windowSeconds: 18_000, resetAt: now + 1200),
                    oneWeek: UsageWindow(usedPercent: 20, windowSeconds: 604_800, resetAt: now + 172_800),
                    credits: nil
                )
            ]
        )
        let authRepository = StubAuthRepository(
            currentAuth: nil,
            currentAccountID: "account-1",
            extractedByAccountID: [
                "account-1": ExtractedAuth(
                    accountID: "account-1",
                    accessToken: "token-1",
                    email: "primary@example.com",
                    planType: "pro",
                    teamName: nil
                )
            ]
        )
        let vault = InMemoryAccountVault()
        try vault.save(authJSON: .object(["account_id": .string("account-1")]), for: "account-1")
        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: authRepository,
            usageService: usageService,
            accountConsumptionService: StubAccountConsumptionService(),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            accountVault: vault,
            settingsCoordinator: SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: StubLaunchAtStartupService()
            ),
            dateProvider: FixedDateProvider(now: now)
        )

        _ = try await coordinator.refreshAllUsage(force: false) { _ in }
        let firstCallCount = await usageService.currentCallCount()
        XCTAssertEqual(firstCallCount, 0)

        _ = try await coordinator.refreshAllUsage(force: true) { _ in }
        let secondCallCount = await usageService.currentCallCount()
        XCTAssertEqual(secondCallCount, 1)
    }

    func testSwitchAccountWritesAuthUpdatesSelectionAndLaunchesCodex() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Backup",
                        email: "backup@example.com",
                        accountID: "account-9",
                        planType: "plus",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .null,
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentSelection: nil,
                settings: .defaultValue
            )
        )
        let authRepository = StubAuthRepository(
            currentAuth: nil,
            currentAccountID: nil,
            extractedByAccountID: [:]
        )
        let vault = InMemoryAccountVault()
        let authPayload = JSONValue.object(["account_id": .string("account-9"), "token": .string("payload")])
        try vault.save(authJSON: authPayload, for: "account-9")
        let codexCLIService = StubCodexCLIService()
        let settingsCoordinator = SettingsCoordinator(
            storeRepository: storeRepository,
            launchAtStartupService: StubLaunchAtStartupService()
        )
        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: authRepository,
            usageService: RecordingUsageService(resultByAccountID: [:]),
            accountConsumptionService: StubAccountConsumptionService(),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: codexCLIService,
            accountVault: vault,
            settingsCoordinator: settingsCoordinator,
            dateProvider: FixedDateProvider(now: now)
        )

        let result = try await coordinator.switchAccountAndApplySettings(id: "acct-1")
        let savedStore = try storeRepository.loadStore()

        XCTAssertEqual(result, .idle)
        XCTAssertEqual(authRepository.writtenAuth, authPayload)
        XCTAssertEqual(savedStore.currentSelection?.accountID, "account-9")
        XCTAssertEqual(codexCLIService.launchCount, 1)
    }

    func testSwitchAccountDoesNotSyncOpenClawWhenSettingDisabled() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Backup",
                        email: "backup@example.com",
                        accountID: "account-9",
                        planType: "plus",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .null,
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentSelection: nil,
                settings: .defaultValue
            )
        )
        let authRepository = StubAuthRepository(currentAuth: nil, currentAccountID: nil, extractedByAccountID: [:])
        let vault = InMemoryAccountVault()
        try vault.save(authJSON: .object(["account_id": .string("account-9")]), for: "account-9")
        let openClawSwitchService = StubOpenClawSwitchService(result: .init(synced: true, warning: nil, error: nil))

        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: authRepository,
            usageService: RecordingUsageService(resultByAccountID: [:]),
            accountConsumptionService: StubAccountConsumptionService(),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            openClawSwitchService: openClawSwitchService,
            accountVault: vault,
            settingsCoordinator: SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: StubLaunchAtStartupService()
            ),
            dateProvider: FixedDateProvider(now: now)
        )

        let result = try await coordinator.switchAccountAndApplySettings(id: "acct-1")
        let callCount = await openClawSwitchService.callCount

        XCTAssertFalse(result.openClawSynced)
        XCTAssertNil(result.openClawSyncWarning)
        XCTAssertNil(result.openClawSyncError)
        XCTAssertEqual(callCount, 0)
    }

    func testSwitchAccountSyncsOpenClawWhenSettingEnabled() async throws {
        let now: Int64 = 1_763_216_000
        let settings = AppSettings(
            launchAtStartup: false,
            launchCodexAfterSwitch: true,
            syncOpenClawOnSwitch: true,
            showEmails: false,
            autoRefreshIntervalMinutes: 5,
            autoSmartSwitch: false,
            syncOpencodeOpenaiAuth: false,
            restartEditorsOnSwitch: false,
            restartEditorTargets: [],
            autoStartApiProxy: false,
            remoteServers: [],
            locale: AppLocale.simplifiedChinese.identifier
        )
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Backup",
                        email: "backup@example.com",
                        accountID: "account-9",
                        planType: "plus",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .null,
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentSelection: nil,
                settings: settings
            )
        )
        let authRepository = StubAuthRepository(currentAuth: nil, currentAccountID: nil, extractedByAccountID: [:])
        let vault = InMemoryAccountVault()
        try vault.save(authJSON: .object(["account_id": .string("account-9")]), for: "account-9")
        let openClawSwitchService = StubOpenClawSwitchService(result: .init(synced: true, warning: nil, error: nil))

        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: authRepository,
            usageService: RecordingUsageService(resultByAccountID: [:]),
            accountConsumptionService: StubAccountConsumptionService(),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            openClawSwitchService: openClawSwitchService,
            accountVault: vault,
            settingsCoordinator: SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: StubLaunchAtStartupService()
            ),
            dateProvider: FixedDateProvider(now: now)
        )

        let result = try await coordinator.switchAccountAndApplySettings(id: "acct-1")
        let callCount = await openClawSwitchService.callCount
        let request = await openClawSwitchService.lastRequest

        XCTAssertTrue(result.openClawSynced)
        XCTAssertNil(result.openClawSyncWarning)
        XCTAssertNil(result.openClawSyncError)
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(request?.email, "backup@example.com")
        XCTAssertEqual(request?.accountID, "account-9")
    }

    func testSwitchAccountReturnsOpenClawWarningWithoutFailingMainSwitch() async throws {
        let now: Int64 = 1_763_216_000
        let settings = AppSettings(
            launchAtStartup: false,
            launchCodexAfterSwitch: true,
            syncOpenClawOnSwitch: true,
            showEmails: false,
            autoRefreshIntervalMinutes: 5,
            autoSmartSwitch: false,
            syncOpencodeOpenaiAuth: false,
            restartEditorsOnSwitch: false,
            restartEditorTargets: [],
            autoStartApiProxy: false,
            remoteServers: [],
            locale: AppLocale.simplifiedChinese.identifier
        )
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Backup",
                        email: "missing@example.com",
                        accountID: "account-9",
                        planType: "plus",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .null,
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentSelection: nil,
                settings: settings
            )
        )
        let authRepository = StubAuthRepository(currentAuth: nil, currentAccountID: nil, extractedByAccountID: [:])
        let vault = InMemoryAccountVault()
        try vault.save(authJSON: .object(["account_id": .string("account-9")]), for: "account-9")
        let openClawSwitchService = StubOpenClawSwitchService(
            result: .init(synced: false, warning: "No matching OpenClaw account was found", error: nil)
        )

        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: authRepository,
            usageService: RecordingUsageService(resultByAccountID: [:]),
            accountConsumptionService: StubAccountConsumptionService(),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            openClawSwitchService: openClawSwitchService,
            accountVault: vault,
            settingsCoordinator: SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: StubLaunchAtStartupService()
            ),
            dateProvider: FixedDateProvider(now: now)
        )

        let result = try await coordinator.switchAccountAndApplySettings(id: "acct-1")
        let savedStore = try storeRepository.loadStore()

        XCTAssertFalse(result.openClawSynced)
        XCTAssertEqual(result.openClawSyncWarning, "No matching OpenClaw account was found")
        XCTAssertNil(result.openClawSyncError)
        XCTAssertEqual(savedStore.currentSelection?.accountID, "account-9")
    }

    func testDeleteAccountRemovesStoredAccountAndVaultAuth() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Backup",
                        email: "backup@example.com",
                        accountID: "account-9",
                        planType: "plus",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .null,
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentSelection: CurrentAccountSelection(
                    accountID: "account-9",
                    selectedAt: now * 1_000,
                    sourceDeviceID: "macos-local"
                ),
                settings: .defaultValue
            )
        )
        let authRepository = StubAuthRepository(
            currentAuth: nil,
            currentAccountID: nil,
            extractedByAccountID: [:]
        )
        let vault = InMemoryAccountVault()
        try vault.save(authJSON: .object(["account_id": .string("account-9")]), for: "account-9")
        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: authRepository,
            usageService: RecordingUsageService(resultByAccountID: [:]),
            accountConsumptionService: StubAccountConsumptionService(),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            accountVault: vault,
            settingsCoordinator: SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: StubLaunchAtStartupService()
            ),
            dateProvider: FixedDateProvider(now: now)
        )

        try await coordinator.deleteAccount(id: "acct-1")

        let savedStore = try storeRepository.loadStore()
        XCTAssertTrue(savedStore.accounts.isEmpty)
        XCTAssertNil(savedStore.currentSelection)
        XCTAssertThrowsError(try vault.loadAuth(for: "account-9"))
    }

    func testCurrentAccountTokenCostStateReturnsUnavailableWithoutAPIKey() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Primary",
                        email: "primary@example.com",
                        accountID: "account-1",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .null,
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentSelection: CurrentAccountSelection(
                    accountID: "account-1",
                    selectedAt: now * 1_000,
                    sourceDeviceID: "macos-local"
                ),
                settings: .defaultValue
            )
        )
        let authRepository = StubAuthRepository(
            currentAuth: nil,
            currentAccountID: "account-1",
            extractedByAccountID: [
                "account-1": ExtractedAuth(
                    accountID: "account-1",
                    accessToken: "token-1",
                    email: "primary@example.com",
                    planType: "pro",
                    teamName: nil
                )
            ]
        )
        let vault = InMemoryAccountVault()
        try vault.save(authJSON: .object(["account_id": .string("account-1")]), for: "account-1")
        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: authRepository,
            usageService: RecordingUsageService(resultByAccountID: [:]),
            accountConsumptionService: StubAccountConsumptionService(),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            accountVault: vault,
            settingsCoordinator: SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: StubLaunchAtStartupService()
            ),
            dateProvider: FixedDateProvider(now: now)
        )

        let state = await coordinator.currentAccountTokenCostState()

        XCTAssertEqual(state, .unavailable)
    }

    func testCurrentAccountTokenCostStateUsesLocalFallbackWithoutAPIKey() async throws {
        let now: Int64 = 1_763_216_000
        let localSummary = AccountTokenCostSummary(
            todayCost: 6.5,
            todayTokens: 310_000,
            last30DaysCost: 48.9,
            last30DaysTokens: 5_400_000,
            currencyCode: "USD"
        )
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Primary",
                        email: "primary@example.com",
                        accountID: "account-1",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .null,
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentSelection: CurrentAccountSelection(
                    accountID: "account-1",
                    selectedAt: now * 1_000,
                    sourceDeviceID: "macos-local"
                ),
                settings: .defaultValue
            )
        )
        let authRepository = StubAuthRepository(
            currentAuth: nil,
            currentAccountID: "account-1",
            extractedByAccountID: [
                "account-1": ExtractedAuth(
                    accountID: "account-1",
                    accessToken: "token-1",
                    email: "primary@example.com",
                    planType: "pro",
                    teamName: nil
                )
            ]
        )
        let vault = InMemoryAccountVault()
        try vault.save(authJSON: .object(["account_id": .string("account-1")]), for: "account-1")
        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: authRepository,
            usageService: RecordingUsageService(resultByAccountID: [:]),
            accountConsumptionService: StubAccountConsumptionService(localSummary: localSummary),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            accountVault: vault,
            settingsCoordinator: SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: StubLaunchAtStartupService()
            ),
            dateProvider: FixedDateProvider(now: now)
        )

        let state = await coordinator.currentAccountTokenCostState()

        XCTAssertEqual(state, .available(localSummary))
    }

    func testCurrentAccountTokenCostStateLoadsSummaryWhenAPIKeyExists() async throws {
        let now: Int64 = 1_763_216_000
        let expected = AccountTokenCostSummary(
            todayCost: 12.5,
            todayTokens: 1_200_000,
            last30DaysCost: 78.2,
            last30DaysTokens: 12_300_000,
            currencyCode: "USD"
        )
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Primary",
                        email: "primary@example.com",
                        accountID: "account-1",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .null,
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentSelection: CurrentAccountSelection(
                    accountID: "account-1",
                    selectedAt: now * 1_000,
                    sourceDeviceID: "macos-local"
                ),
                settings: .defaultValue
            )
        )
        let authRepository = StubAuthRepository(
            currentAuth: nil,
            currentAccountID: "account-1",
            extractedByAccountID: [
                "account-1": ExtractedAuth(
                    accountID: "account-1",
                    accessToken: "token-1",
                    email: "primary@example.com",
                    planType: "pro",
                    teamName: nil
                )
            ]
        )
        let vault = InMemoryAccountVault()
        try vault.save(
            authJSON: .object([
                "account_id": .string("account-1"),
                "OPENAI_API_KEY": .string("sk-test")
            ]),
            for: "account-1"
        )
        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: authRepository,
            usageService: RecordingUsageService(resultByAccountID: [:]),
            accountConsumptionService: StubAccountConsumptionService(result: expected),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            accountVault: vault,
            settingsCoordinator: SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: StubLaunchAtStartupService()
            ),
            dateProvider: FixedDateProvider(now: now)
        )

        let state = await coordinator.currentAccountTokenCostState()

        XCTAssertEqual(state, .available(expected))
    }

    func testCurrentAccountTokenCostStateRefreshesTokensToRecoverAPIKey() async throws {
        let now: Int64 = 1_763_216_000
        let expected = AccountTokenCostSummary(
            todayCost: 8.2,
            todayTokens: 420_000,
            last30DaysCost: 61.7,
            last30DaysTokens: 9_100_000,
            currencyCode: "USD"
        )
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Primary",
                        email: "primary@example.com",
                        accountID: "account-1",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .null,
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentSelection: CurrentAccountSelection(
                    accountID: "account-1",
                    selectedAt: now * 1_000,
                    sourceDeviceID: "macos-local"
                ),
                settings: .defaultValue
            )
        )
        let authRepository = StubAuthRepository(
            currentAuth: .object([
                "auth_mode": .string("chatgpt"),
                "tokens": .object([
                    "account_id": .string("account-1"),
                    "access_token": .string("token-1"),
                    "refresh_token": .string("refresh-1"),
                    "id_token": .string("id-1")
                ])
            ]),
            currentAccountID: "account-1",
            extractedByAccountID: [
                "account-1": ExtractedAuth(
                    accountID: "account-1",
                    accessToken: "token-1",
                    email: "primary@example.com",
                    planType: "pro",
                    teamName: nil
                )
            ]
        )
        let refreshedTokens = ChatGPTOAuthTokens(
            accessToken: "token-2",
            refreshToken: "refresh-2",
            idToken: "id-2",
            apiKey: "sk-recovered"
        )
        let vault = InMemoryAccountVault()
        try vault.save(
            authJSON: .object([
                "auth_mode": .string("chatgpt"),
                "tokens": .object([
                    "account_id": .string("account-1"),
                    "access_token": .string("token-1"),
                    "refresh_token": .string("refresh-1"),
                    "id_token": .string("id-1")
                ])
            ]),
            for: "account-1"
        )
        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: authRepository,
            usageService: RecordingUsageService(resultByAccountID: [:]),
            accountConsumptionService: StubAccountConsumptionService(result: expected),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(refreshedTokens: refreshedTokens),
            codexCLIService: StubCodexCLIService(),
            accountVault: vault,
            settingsCoordinator: SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: StubLaunchAtStartupService()
            ),
            dateProvider: FixedDateProvider(now: now)
        )

        let state = await coordinator.currentAccountTokenCostState()

        XCTAssertEqual(state, .available(expected))
        let saved = try vault.loadAuth(for: "account-1")
        XCTAssertEqual(saved["OPENAI_API_KEY"]?.stringValue, "sk-recovered")
    }
}

final class OpenAIChatGPTOAuthLoginServiceCallbackTests: XCTestCase {
    func testResolveAuthorizationCodeAllowsValidCodeWhenStateMismatches() throws {
        let code = try OpenAIChatGPTOAuthLoginService.resolveAuthorizationCode(
            from: [
                "code": "oai-code-123",
                "state": "returned-state"
            ],
            expectedState: "expected-state"
        )

        XCTAssertEqual(code, "oai-code-123")
    }

    func testResolveAuthorizationCodePrefersOAuthErrorWithoutCode() {
        XCTAssertThrowsError(
            try OpenAIChatGPTOAuthLoginService.resolveAuthorizationCode(
                from: [
                    "error": "access_denied",
                    "error_description": "User denied access"
                ],
                expectedState: "expected-state"
            )
        ) { error in
            guard case .unauthorized(let message) = error as? AppError else {
                return XCTFail("Expected unauthorized error")
            }
            XCTAssertTrue(message.contains("User denied access"))
        }
    }

    func testResolveAuthorizationCodeRejectsMissingCodeWhenStateMismatches() {
        XCTAssertThrowsError(
            try OpenAIChatGPTOAuthLoginService.resolveAuthorizationCode(
                from: ["state": "wrong-state"],
                expectedState: "expected-state"
            )
        ) { error in
            guard case .unauthorized(let message) = error as? AppError else {
                return XCTFail("Expected unauthorized error")
            }
            XCTAssertEqual(message, L10n.tr("error.oauth.callback_state_mismatch"))
        }
    }
}

private final class InMemoryAccountsStoreRepository: AccountsStoreRepository, @unchecked Sendable {
    private var store: AccountsStore

    init(store: AccountsStore) {
        self.store = store
    }

    func loadStore() throws -> AccountsStore {
        store
    }

    func saveStore(_ store: AccountsStore) throws {
        self.store = store
    }
}

private struct FixedDateProvider: DateProviding {
    let now: Int64

    func unixSecondsNow() -> Int64 {
        now
    }
}

private final class StubAuthRepository: AuthRepository, @unchecked Sendable {
    private let currentAuthValue: JSONValue?
    private let currentAccountIDValue: String?
    private let extractedByAccountID: [String: ExtractedAuth]
    private(set) var writtenAuth: JSONValue?

    init(
        currentAuth: JSONValue?,
        currentAccountID: String?,
        extractedByAccountID: [String: ExtractedAuth]
    ) {
        self.currentAuthValue = currentAuth
        self.currentAccountIDValue = currentAccountID
        self.extractedByAccountID = extractedByAccountID
    }

    func readCurrentAuth() throws -> JSONValue {
        guard let currentAuthValue else {
            throw AppError.invalidData("Missing current auth")
        }
        return currentAuthValue
    }

    func readCurrentAuthOptional() throws -> JSONValue? {
        currentAuthValue
    }

    func readAuth(from url: URL) throws -> JSONValue {
        _ = url
        return try readCurrentAuth()
    }

    func writeCurrentAuth(_ auth: JSONValue) throws {
        writtenAuth = auth
    }

    func removeCurrentAuth() throws {}

    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue {
        var root: [String: JSONValue] = [
            "auth_mode": .string("chatgpt"),
            "tokens": .object([
                "account_id": .string("account-1"),
                "access_token": .string(tokens.accessToken),
                "refresh_token": .string(tokens.refreshToken),
                "id_token": .string(tokens.idToken)
            ])
        ]
        if let apiKey = tokens.apiKey {
            root["OPENAI_API_KEY"] = .string(apiKey)
        }
        return .object(root)
    }

    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth {
        if let accountID = auth["account_id"]?.stringValue, let extracted = extractedByAccountID[accountID] {
            return extracted
        }
        if let currentAccountIDValue, let extracted = extractedByAccountID[currentAccountIDValue] {
            return extracted
        }
        throw AppError.invalidData("Missing extracted auth")
    }

    func currentAuthAccountID() -> String? {
        currentAccountIDValue
    }
}

private actor RecordingUsageService: UsageService {
    private(set) var callCount = 0
    private let resultByAccountID: [String: UsageSnapshot]

    init(resultByAccountID: [String: UsageSnapshot]) {
        self.resultByAccountID = resultByAccountID
    }

    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot {
        _ = accessToken
        callCount += 1
        guard let result = resultByAccountID[accountID] else {
            throw AppError.invalidData("Missing usage for \(accountID)")
        }
        return result
    }

    func currentCallCount() -> Int {
        callCount
    }
}

private struct StubAccountConsumptionService: AccountConsumptionService {
    var result = AccountTokenCostSummary(
        todayCost: 0,
        todayTokens: 0,
        last30DaysCost: 0,
        last30DaysTokens: 0,
        currencyCode: "USD"
    )
    var localSummary: AccountTokenCostSummary?

    func fetchSummary(apiKey: String, now: Date) async throws -> AccountTokenCostSummary {
        _ = apiKey
        _ = now
        return result
    }

    func fetchLocalSummary(now: Date) async -> AccountTokenCostSummary? {
        _ = now
        return localSummary
    }
}

private final class StubChatGPTOAuthLoginService: ChatGPTOAuthLoginServiceProtocol, @unchecked Sendable {
    private let refreshedTokens: ChatGPTOAuthTokens?

    init(refreshedTokens: ChatGPTOAuthTokens? = nil) {
        self.refreshedTokens = refreshedTokens
    }

    func signInWithChatGPT(timeoutSeconds: TimeInterval) async throws -> ChatGPTOAuthTokens {
        _ = timeoutSeconds
        return ChatGPTOAuthTokens(accessToken: "account-1", refreshToken: "refresh", idToken: "id-token", apiKey: nil)
    }

    func refreshTokensIfPossible(from authJSON: JSONValue) async throws -> ChatGPTOAuthTokens? {
        _ = authJSON
        return refreshedTokens
    }
}

private final class StubCodexCLIService: CodexCLIServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var launchCount = 0

    func launchApp(workspacePath: String?) throws -> Bool {
        _ = workspacePath
        lock.lock()
        launchCount += 1
        lock.unlock()
        return false
    }
}

private struct StubLaunchAtStartupService: LaunchAtStartupServiceProtocol {
    func setEnabled(_ enabled: Bool) async throws {
        _ = enabled
    }

    func syncWithStoreValue(_ enabled: Bool) async throws {
        _ = enabled
    }
}

private actor StubOpenClawSwitchService: OpenClawSwitchServiceProtocol {
    private(set) var callCount = 0
    private(set) var lastRequest: (email: String?, accountID: String)?
    private let result: OpenClawSwitchExecutionResult

    init(result: OpenClawSwitchExecutionResult) {
        self.result = result
    }

    func syncCodexAccount(email: String?, accountID: String) async -> OpenClawSwitchExecutionResult {
        callCount += 1
        lastRequest = (email, accountID)
        return result
    }
}

private final class InMemoryAccountVault: AccountVault, @unchecked Sendable {
    private var values: [String: JSONValue] = [:]

    func save(authJSON: JSONValue, for accountID: String) throws {
        values[accountID] = authJSON
    }

    func loadAuth(for accountID: String) throws -> JSONValue {
        guard let value = values[accountID] else {
            throw AppError.invalidData("Missing auth for \(accountID)")
        }
        return value
    }

    func removeAuth(for accountID: String) throws {
        values.removeValue(forKey: accountID)
    }
}
