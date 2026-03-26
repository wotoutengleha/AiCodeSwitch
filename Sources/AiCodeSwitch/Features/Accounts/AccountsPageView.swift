import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct AccountsPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @ObservedObject var model: AccountsPageModel
    let showEmails: Bool
    let onToggleEmails: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            contentPanel
        }
        .padding(.horizontal, LayoutRules.outerWindowInset)
        .padding(.vertical, LayoutRules.outerWindowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var contentPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            currentAccountSection
            panelDivider
            usageSection
            panelDivider
            costSection
            panelDivider
            accountsSection
            panelDivider
            footerMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(SwitcherPalette.panelBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SwitcherPalette.panelBorder(for: colorScheme), lineWidth: 1)
        )
    }

    private var currentAccountSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("switcher.title.app"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SwitcherPalette.primaryText(for: colorScheme))
                    Text(currentPresentation?.emailText ?? "--")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                    Text(currentPresentation?.updatedText ?? L10n.tr("switcher.updated.never"))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
                        .padding(.bottom, 3)
                }

                if let warning = model.quotaWarningText {
                    Text(warning)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Text(currentPresentation?.planText ?? "--")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SwitcherPalette.subduedFill(for: colorScheme), in: Capsule())

                Button {
                    Task { await model.refreshUsage() }
                } label: {
                    ToolbarIconLabel(
                        systemImage: "arrow.clockwise",
                        isSpinning: model.isRefreshing,
                        opticalScale: LayoutRules.toolbarRefreshIconOpticalScale,
                        tint: SwitcherPalette.secondaryText(for: colorScheme)
                    )
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .background(SwitcherPalette.subduedFill(for: colorScheme), in: Circle())
            }
        }
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            CurrentUsageBarView(display: currentPresentation?.fiveHour ?? emptyUsage(title: L10n.tr("switcher.metric.five_hours")))
            CurrentUsageBarView(display: currentPresentation?.week ?? emptyUsage(title: L10n.tr("switcher.metric.weekly")))
        }
        .padding(.vertical, 16)
    }

    private var costSection: some View {
        CurrentTokenCostCard(
            state: model.currentTokenCostState,
            locale: locale,
            onReauthorize: { Task { await model.reauthorizeCurrentAccount() } }
        )
        .padding(.vertical, 16)
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(accountsTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))

            if model.switchableAccounts.isEmpty {
                Text(L10n.tr("switcher.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.switchableAccounts) { account in
                        AccountCardView(
                            account: account,
                            showEmails: showEmails,
                            switching: model.switchingAccountID == account.id,
                            onTap: { Task { await model.performPrimaryAction(for: account) } },
                            onDelete: { Task { await model.deleteAccount(id: account.id) } }
                        )
                    }
                }
            }

            addAccountButton
        }
        .padding(.vertical, 16)
    }

    private var addAccountButton: some View {
        Button {
            model.addAccountViaLogin()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.isAdding ? "xmark" : "plus")
                    .font(.system(size: 14, weight: .regular))
                Text(model.isAdding ? L10n.tr("switcher.action.cancel_adding") : L10n.tr("switcher.action.add_account"))
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(SwitcherPalette.buttonBorder(for: colorScheme))
            )
        }
        .buttonStyle(.plain)
    }

    private var footerMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            SwitcherMenuActionRow(
                title: L10n.tr("switcher.action.status_page"),
                systemImage: "waveform.path.ecg"
            ) {
                openURL("https://status.openai.com")
            }

            SwitcherMenuActionRow(
                title: showEmails ? L10n.tr("switcher.action.hide_emails") : L10n.tr("switcher.action.show_emails"),
                systemImage: showEmails ? "eye.slash" : "eye"
            ) {
                onToggleEmails()
            }

            SwitcherMenuActionRow(
                title: L10n.tr("tab.settings"),
                systemImage: "gearshape"
            ) {
                onOpenSettings()
            }

            SwitcherMenuActionRow(
                title: L10n.tr("common.quit"),
                systemImage: "arrow.right.square",
                tint: Color(red: 0.90, green: 0.23, blue: 0.22)
            ) {
                #if canImport(AppKit)
                NSApp.terminate(nil)
                #endif
            }
        }
        .padding(.top, 14)
    }

    private var panelDivider: some View {
        Divider()
            .overlay(SwitcherPalette.divider(for: colorScheme))
    }

    private var currentPresentation: CurrentAccountPresentation? {
        model.currentAccount.map { AccountCardPresentation.current(account: $0, showEmails: showEmails) }
    }

    private var accountsTitle: String {
        locale.identifier.hasPrefix("zh") ? "账号列表" : "ACCOUNTS"
    }

    private func emptyUsage(title: String) -> UsageBarDisplay {
        UsageBarDisplay(
            title: title,
            remainingPercentText: "--",
            progress: 0,
            resetText: L10n.tr("switcher.reset.unknown")
        )
    }

    private func openURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}

private struct CurrentTokenCostCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: CurrentAccountTokenCostState
    let locale: Locale
    let onReauthorize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("switcher.cost.title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SwitcherPalette.primaryText(for: colorScheme))

            switch state {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(red: 0.98, green: 0.62, blue: 0.12))
                    Text(L10n.tr("switcher.cost.loading"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
                }
            case .available(let summary):
                VStack(alignment: .leading, spacing: 10) {
                    costRow(
                        label: L10n.tr("switcher.cost.today"),
                        cost: formattedCurrency(summary.todayCost, currencyCode: summary.currencyCode),
                        tokens: formattedTokens(summary.todayTokens)
                    )
                    costRow(
                        label: L10n.tr("switcher.cost.last_30_days"),
                        cost: formattedCurrency(summary.last30DaysCost, currencyCode: summary.currencyCode),
                        tokens: formattedTokens(summary.last30DaysTokens)
                    )
                }
            case .unavailable:
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("switcher.cost.enable_with_reauth"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))

                    Button(action: onReauthorize) {
                        Text(L10n.tr("switcher.action.reauthorize"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SwitcherPalette.primaryText(for: colorScheme))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(SwitcherPalette.subduedFill(for: colorScheme), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            case .failed:
                Text(L10n.tr("switcher.cost.temporarily_unavailable"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedCurrency(_ amount: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode.uppercased()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        if let value = formatter.string(from: NSNumber(value: amount)) {
            return value
        }

        return "\(currencyCode.uppercased()) \(String(format: "%.2f", amount))"
    }

    private func formattedTokens(_ value: Int64) -> String {
        value.formatted(
            .number
                .locale(locale)
                .notation(.compactName)
        )
    }

    private func costRow(label: String, cost: String, tokens: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
            Spacer(minLength: 0)
            Text(cost)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SwitcherPalette.primaryText(for: colorScheme))
            Text(tokens)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
        }
    }
}

private struct CurrentUsageBarView: View {
    @Environment(\.colorScheme) private var colorScheme
    let display: UsageBarDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(barColor)
                            .frame(width: 12, height: 12)
                        Image(systemName: iconName)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text(display.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SwitcherPalette.primaryText(for: colorScheme))
                }
                Spacer(minLength: 0)
                Text(display.remainingPercentText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(barColor)
            }

            UsageProgressBar(
                progress: display.progress,
                fillColor: barColor,
                trackColor: SwitcherPalette.compactProgressTrack(for: colorScheme),
                height: 6
            )

            Text(display.resetText)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(SwitcherPalette.secondaryText(for: colorScheme))
        }
    }

    private var barColor: Color {
        let lower = display.title.lowercased()
        if lower.contains("week") {
            return Color(red: 0.20, green: 0.79, blue: 0.39)
        }
        return Color(red: 0.98, green: 0.28, blue: 0.46)
    }

    private var iconName: String {
        let lower = display.title.lowercased()
        if lower.contains("week") {
            return "calendar"
        }
        return "bolt.fill"
    }
}
