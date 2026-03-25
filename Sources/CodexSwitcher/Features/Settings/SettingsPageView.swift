import SwiftUI

struct SettingsPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: SettingsPageModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            settingsCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LayoutRules.outerWindowInset)
        .padding(.vertical, LayoutRules.outerWindowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SwitcherPalette.primaryText(for: colorScheme))
                    .frame(width: 28, height: 28)
                    .background(SwitcherPalette.subduedFill(for: colorScheme), in: Circle())
            }
            .buttonStyle(.plain)

            Text(L10n.tr("tab.settings"))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(SwitcherPalette.primaryText(for: colorScheme))

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .padding(.horizontal, LayoutRules.panelContentInset)
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingsToggleRow(
                title: L10n.tr("settings.launch_at_startup"),
                isOn: Binding(
                    get: { model.settings.launchAtStartup },
                    set: { model.setLaunchAtStartup($0) }
                ),
                isLoading: model.isUpdatingLaunchAtStartup
            )

            rowDivider

            autoRefreshRow

            rowDivider

            languageRow

            rowDivider

            settingsToggleRow(
                title: L10n.tr("settings.relaunch_after_switch"),
                isOn: Binding(
                    get: { model.settings.launchCodexAfterSwitch },
                    set: { model.setLaunchAfterSwitch($0) }
                )
            )
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: LayoutRules.cardRadius, style: .continuous)
                .fill(settingsCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LayoutRules.cardRadius, style: .continuous)
                .stroke(settingsCardBorder, lineWidth: 1)
        )
    }

    private var autoRefreshRow: some View {
        settingsRow(title: L10n.tr("settings.auto_refresh")) {
            Menu {
                ForEach(AppSettings.supportedAutoRefreshIntervals, id: \.self) { minutes in
                    Button {
                        model.setAutoRefreshIntervalMinutes(minutes)
                    } label: {
                        HStack {
                            Text(refreshIntervalTitle(minutes))
                            if minutes == model.settings.autoRefreshIntervalMinutes {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(refreshIntervalTitle(model.settings.autoRefreshIntervalMinutes))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SwitcherPalette.primaryText(for: colorScheme))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
                }
                .frame(width: 112, height: 30, alignment: .trailing)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(SwitcherPalette.subduedFill(for: colorScheme))
                )
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        }
    }

    private var languageRow: some View {
        settingsRow(title: L10n.tr("settings.language")) {
            HStack(spacing: 6) {
                languageButton(locale: .simplifiedChinese, title: "中文")
                languageButton(locale: .english, title: "English")
            }
        }
    }

    private func languageButton(locale: AppLocale, title: String) -> some View {
        let isSelected = AppLocale.resolve(model.settings.locale) == locale
        return Button {
            model.setLocale(locale.identifier)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : SwitcherPalette.primaryText(for: colorScheme)
                )
                .frame(minWidth: 68, minHeight: 30)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            isSelected
                                ? Color(red: 0.22, green: 0.70, blue: 0.78)
                                : SwitcherPalette.subduedFill(for: colorScheme)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func settingsToggleRow(title: String, isOn: Binding<Bool>, isLoading: Bool = false) -> some View {
        settingsRow(title: title) {
            ZStack(alignment: .trailing) {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.72 : 1)
                    .animation(.easeInOut(duration: 0.16), value: isLoading)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SwitcherPalette.secondaryText(for: colorScheme))
                        .scaleEffect(0.72)
                        .offset(x: -42)
                        .transition(.opacity)
                }
            }
            .frame(minWidth: 60, alignment: .trailing)
        }
    }

    private func settingsRow<Accessory: View>(
        title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SwitcherPalette.primaryText(for: colorScheme))

            Spacer(minLength: 12)

            accessory()
        }
        .padding(.horizontal, LayoutRules.panelContentInset)
        .padding(.vertical, 11)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(SwitcherPalette.divider(for: colorScheme))
            .padding(.leading, LayoutRules.panelContentInset)
    }

    private var settingsCardBackground: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.055)
        default:
            return Color(red: 0.95, green: 0.98, blue: 1.0)
        }
    }

    private var settingsCardBorder: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.08)
        default:
            return Color.black.opacity(0.06)
        }
    }

    private func refreshIntervalTitle(_ minutes: Int) -> String {
        String(format: L10n.tr("settings.auto_refresh.interval_format"), minutes)
    }
}
