import Foundation

@MainActor
struct AppContainer {
    let accountsModel: AccountsPageModel
    let settingsModel: SettingsPageModel

    static func liveOrCrash() -> AppContainer {
        do {
            let paths = try FileSystemPaths.live()
            let storeRepository = StoreFileRepository(paths: paths)
            let authRepository = AuthFileRepository(paths: paths)
            let usageService = DefaultUsageService(configPath: paths.codexConfigPath)
            let accountConsumptionService = DefaultAccountConsumptionService()
            let loginService = OpenAIChatGPTOAuthLoginService(configPath: paths.codexConfigPath)
            let codexCLIService = CodexCLIService()
            let launchAtStartupService = LaunchAtStartupService()
            let accountVault = KeychainAccountVault(fallbackDirectory: paths.applicationSupportDirectory)

            let settingsCoordinator = SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: launchAtStartupService
            )
            let accountsCoordinator = AccountsCoordinator(
                storeRepository: storeRepository,
                authRepository: authRepository,
                usageService: usageService,
                accountConsumptionService: accountConsumptionService,
                chatGPTOAuthLoginService: loginService,
                codexCLIService: codexCLIService,
                accountVault: accountVault,
                settingsCoordinator: settingsCoordinator
            )

            Task {
                try? await settingsCoordinator.syncLaunchAtStartupFromStore()
            }

            return AppContainer(
                accountsModel: AccountsPageModel(coordinator: accountsCoordinator),
                settingsModel: SettingsPageModel(settingsCoordinator: settingsCoordinator)
            )
        } catch {
            fatalError("Failed to bootstrap CodexSwitcher: \(error.localizedDescription)")
        }
    }
}
