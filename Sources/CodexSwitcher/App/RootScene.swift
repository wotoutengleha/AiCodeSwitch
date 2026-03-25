import SwiftUI

private enum RootPanelMode {
    case accounts
    case settings
}

struct RootScene: View {
    @State private var mode: RootPanelMode = .accounts
    @State private var measuredAccountsContentHeight = CGFloat.zero
    @State private var measuredSettingsContentHeight = CGFloat.zero
    @ObservedObject private var accountsModel: AccountsPageModel
    @ObservedObject private var settingsModel: SettingsPageModel

    init(container: AppContainer) {
        self.accountsModel = container.accountsModel
        self.settingsModel = container.settingsModel
    }

    private var runtimeLocale: Locale {
        Locale(identifier: AppLocale.resolve(settingsModel.settings.locale).identifier)
    }

    private var currentNotice: NoticeMessage? {
        settingsModel.notice ?? accountsModel.notice
    }

    private var panelHeight: CGFloat {
        let visibleContentHeight = switch mode {
        case .accounts:
            measuredAccountsContentHeight
        case .settings:
            max(measuredAccountsContentHeight, measuredSettingsContentHeight)
        }

        let baseContentHeight = max(visibleContentHeight, LayoutRules.defaultPanelHeight)
        let noticeInset = currentNotice == nil ? CGFloat(0) : CGFloat(40)
        return baseContentHeight + noticeInset
    }

    var body: some View {
        Group {
            switch mode {
            case .accounts:
                AccountsPageView(
                    model: accountsModel,
                    showEmails: settingsModel.settings.showEmails,
                    onToggleEmails: { settingsModel.toggleShowEmails() },
                    onOpenSettings: { mode = .settings }
                )
            case .settings:
                SettingsPageView(
                    model: settingsModel,
                    onBack: { mode = .accounts }
                )
            }
        }
        .background(ContentHeightReader())
        .onPreferenceChange(ContentHeightPreferenceKey.self) { value in
            guard value > 0 else { return }
            switch mode {
            case .accounts:
                measuredAccountsContentHeight = value
            case .settings:
                measuredSettingsContentHeight = value
            }
        }
        .task {
            await settingsModel.loadIfNeeded()
            accountsModel.configureAutoRefresh(intervalMinutes: settingsModel.settings.autoRefreshIntervalMinutes)
            await accountsModel.loadIfNeeded()
        }
        .environment(\.locale, runtimeLocale)
        .onAppear {
            L10n.setLocale(identifier: settingsModel.settings.locale)
            accountsModel.configureAutoRefresh(intervalMinutes: settingsModel.settings.autoRefreshIntervalMinutes)
        }
        .onChange(of: settingsModel.settings.locale) { _, value in
            L10n.setLocale(identifier: value)
        }
        .onChange(of: settingsModel.settings.autoRefreshIntervalMinutes) { _, value in
            accountsModel.configureAutoRefresh(intervalMinutes: value)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            NoticeBanner(notice: currentNotice)
                .padding(.horizontal, LayoutRules.outerWindowInset)
                .padding(.top, 6)
        }
        .background(PanelWindowBackground())
        .frame(
            minWidth: LayoutRules.minimumPanelWidth,
            idealWidth: LayoutRules.defaultPanelWidth,
            maxWidth: LayoutRules.maximumPanelWidth,
            minHeight: panelHeight,
            idealHeight: panelHeight,
            maxHeight: panelHeight
        )
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue = CGFloat.zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContentHeightReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: ContentHeightPreferenceKey.self, value: proxy.size.height)
        }
    }
}

private struct PanelWindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            SwitcherPalette.windowBackground(for: colorScheme)
            SwitcherPalette.windowGradient(for: colorScheme)
        }
    }
}
