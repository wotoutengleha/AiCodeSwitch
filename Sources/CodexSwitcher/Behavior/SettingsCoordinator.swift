import Foundation

actor SettingsCoordinator {
    private let storeRepository: AccountsStoreRepository
    private let launchAtStartupService: LaunchAtStartupServiceProtocol

    init(
        storeRepository: AccountsStoreRepository,
        launchAtStartupService: LaunchAtStartupServiceProtocol
    ) {
        self.storeRepository = storeRepository
        self.launchAtStartupService = launchAtStartupService
    }

    func currentSettings() async throws -> AppSettings {
        try storeRepository.loadStore().settings
    }

    func updateSettings(_ patch: AppSettingsPatch) async throws -> AppSettings {
        let launchAtStartupPatch = patch.launchAtStartup

        var store = try storeRepository.loadStore()
        var settings = store.settings

        if let value = patch.launchAtStartup { settings.launchAtStartup = value }
        if let value = patch.launchCodexAfterSwitch { settings.launchCodexAfterSwitch = value }
        if let value = patch.showEmails { settings.showEmails = value }
        if let value = patch.autoRefreshIntervalMinutes {
            settings.autoRefreshIntervalMinutes = AppSettings.normalizedAutoRefreshInterval(value)
        }
        if let value = patch.autoSmartSwitch { settings.autoSmartSwitch = value }
        if let value = patch.syncOpencodeOpenaiAuth { settings.syncOpencodeOpenaiAuth = value }
        if let value = patch.restartEditorsOnSwitch { settings.restartEditorsOnSwitch = value }
        if let value = patch.restartEditorTargets { settings.restartEditorTargets = value }
        if let value = patch.autoStartApiProxy { settings.autoStartApiProxy = value }
        if let value = patch.remoteServers { settings.remoteServers = value }
        if let value = patch.locale { settings.locale = AppLocale.resolve(value).identifier }

        store.settings = settings
        try storeRepository.saveStore(store)

        if let launchAtStartupPatch {
            try await launchAtStartupService.setEnabled(launchAtStartupPatch)
        }

        return settings
    }

    func syncLaunchAtStartupFromStore() async throws {
        let settings = try storeRepository.loadStore().settings
        try await launchAtStartupService.syncWithStoreValue(settings.launchAtStartup)
    }
}
