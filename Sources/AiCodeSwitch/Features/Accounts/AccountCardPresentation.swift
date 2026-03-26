import Foundation

struct UsageBarDisplay: Equatable {
    let title: String
    let remainingPercentText: String
    let progress: Double
    let resetText: String
}

struct CurrentAccountPresentation: Equatable {
    let emailText: String
    let updatedText: String
    let planText: String
    let fiveHour: UsageBarDisplay
    let week: UsageBarDisplay
}

struct SwitchAccountRowPresentation: Equatable {
    let emailText: String
    let planText: String
    let fiveHourLabelText: String
    let fiveHourPercentText: String
    let fiveHourProgress: Double
    let weekLabelText: String
    let weekPercentText: String
    let weekProgress: Double
    let isExpired: Bool
}

enum AccountCardPresentation {
    static func current(account: AccountSummary, showEmails: Bool, now: Date = Date()) -> CurrentAccountPresentation {
        CurrentAccountPresentation(
            emailText: displayEmail(for: account, showEmails: showEmails),
            updatedText: updatedText(fetchedAt: account.usage?.fetchedAt, now: now),
            planText: planLabel(for: account, expired: false),
            fiveHour: usageBar(title: "5 Hours", window: account.usage?.fiveHour),
            week: usageBar(title: "Weekly", window: account.usage?.oneWeek)
        )
    }

    static func row(account: AccountSummary, showEmails: Bool) -> SwitchAccountRowPresentation {
        SwitchAccountRowPresentation(
            emailText: displayEmail(for: account, showEmails: showEmails),
            planText: planLabel(for: account, expired: account.requiresReLogin),
            fiveHourLabelText: L10n.tr("switcher.metric.five_hours"),
            fiveHourPercentText: remainingPercentText(window: account.usage?.fiveHour),
            fiveHourProgress: remainingProgress(window: account.usage?.fiveHour),
            weekLabelText: L10n.tr("switcher.metric.weekly"),
            weekPercentText: remainingPercentText(window: account.usage?.oneWeek),
            weekProgress: remainingProgress(window: account.usage?.oneWeek),
            isExpired: account.requiresReLogin
        )
    }

    static func planLabel(for account: AccountSummary, expired: Bool) -> String {
        if expired {
            return L10n.tr("switcher.account.expired")
        }
        let normalized = account.normalizedPlanLabel.capitalized
        return normalized == "Enterprise" ? "Team" : normalized
    }

    static func displayEmail(for account: AccountSummary, showEmails: Bool) -> String {
        let raw = (account.email ?? account.accountID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "--" }
        guard !showEmails else { return raw }

        if let atIndex = raw.firstIndex(of: "@"), atIndex > raw.startIndex {
            let first = String(raw[raw.startIndex])
            let domain = String(raw[atIndex...])
            return "\(first)••••\(domain)"
        }

        let prefix = raw.prefix(6)
        return "\(prefix)••••"
    }

    static func updatedText(
        fetchedAt: Int64?,
        now: Date = Date(),
        locale: Locale = L10n.currentLocale()
    ) -> String {
        guard let fetchedAt else {
            return L10n.tr("switcher.updated.never")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        let text = formatter.localizedString(for: Date(timeIntervalSince1970: TimeInterval(fetchedAt)), relativeTo: now)
        return L10n.tr("switcher.updated.format", text)
    }

    static func warningText(for account: AccountSummary?) -> String? {
        guard let account else { return nil }
        if remainingProgress(window: account.usage?.fiveHour) <= 0.10 {
            return L10n.tr("switcher.warning.five_hour_low")
        }
        if remainingProgress(window: account.usage?.oneWeek) <= 0.15 {
            return L10n.tr("switcher.warning.week_low")
        }
        return nil
    }

    private static func usageBar(title: String, window: UsageWindow?) -> UsageBarDisplay {
        UsageBarDisplay(
            title: title,
            remainingPercentText: "\(Int((remainingProgress(window: window) * 100).rounded()))%",
            progress: remainingProgress(window: window),
            resetText: resetText(for: window)
        )
    }

    private static func remainingPercentText(window: UsageWindow?) -> String {
        "\(Int((remainingProgress(window: window) * 100).rounded()))%"
    }

    private static func resetText(for window: UsageWindow?) -> String {
        guard let resetAt = window?.resetAt else { return L10n.tr("switcher.reset.unknown") }
        let remaining = max(0, Int(resetAt - Int64(Date().timeIntervalSince1970)))
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 {
            return L10n.tr("switcher.reset.days", days)
        }
        if hours > 0 {
            return L10n.tr("switcher.reset.hours_minutes", hours, minutes)
        }
        return L10n.tr("switcher.reset.minutes", max(1, minutes))
    }

    private static func remainingProgress(window: UsageWindow?) -> Double {
        guard let used = window?.usedPercent else { return 0 }
        return max(0, min(1, (100 - used) / 100))
    }
}
