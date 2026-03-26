import Foundation
import Combine

@MainActor
final class SettingsPageModel: ObservableObject {
    private let settingsCoordinator: SettingsCoordinator
    private let noticeScheduler = NoticeAutoDismissScheduler()
    private var hasLoaded = false

    @Published var settings: AppSettings = .defaultValue
    @Published var isUpdatingLaunchAtStartup = false
    @Published var notice: NoticeMessage? {
        didSet {
            noticeScheduler.schedule(notice) { [weak self] in
                self?.notice = nil
            }
        }
    }

    init(settingsCoordinator: SettingsCoordinator) {
        self.settingsCoordinator = settingsCoordinator
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            settings = try await settingsCoordinator.currentSettings()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func toggleShowEmails() {
        Task {
            await update(AppSettingsPatch(showEmails: !settings.showEmails))
        }
    }

    func setLaunchAtStartup(_ value: Bool) {
        let previousSettings = settings
        settings.launchAtStartup = value

        Task {
            isUpdatingLaunchAtStartup = true
            defer { isUpdatingLaunchAtStartup = false }
            await update(AppSettingsPatch(launchAtStartup: value), rollbackTo: previousSettings)
        }
    }

    func setLaunchAfterSwitch(_ value: Bool) {
        Task {
            await update(AppSettingsPatch(launchCodexAfterSwitch: value))
        }
    }

    func setSyncOpenClawOnSwitch(_ value: Bool) {
        Task {
            await update(AppSettingsPatch(syncOpenClawOnSwitch: value))
        }
    }

    func setLocale(_ value: String) {
        let resolved = AppLocale.resolve(value).identifier
        guard settings.locale != resolved else { return }

        let previousSettings = settings
        settings.locale = resolved
        L10n.setLocale(identifier: resolved)

        Task {
            await update(AppSettingsPatch(locale: resolved), rollbackTo: previousSettings)
        }
    }

    func setAutoRefreshIntervalMinutes(_ value: Int) {
        Task {
            await update(AppSettingsPatch(autoRefreshIntervalMinutes: value))
        }
    }

    private func update(_ patch: AppSettingsPatch, rollbackTo rollbackSettings: AppSettings? = nil) async {
        do {
            settings = try await settingsCoordinator.updateSettings(patch)
        } catch {
            if let rollbackSettings {
                settings = rollbackSettings
                L10n.setLocale(identifier: rollbackSettings.locale)
            }
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }
}
