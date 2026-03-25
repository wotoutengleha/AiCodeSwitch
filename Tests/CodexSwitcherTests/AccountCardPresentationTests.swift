import XCTest
@testable import CodexSwitcher

final class AccountCardPresentationTests: XCTestCase {
    override func tearDown() {
        L10n.setLocale(identifier: AppLocale.english.identifier)
        super.tearDown()
    }

    func testDisplayEmailMasksWhenHidden() {
        let account = makeAccount(email: "dev@example.com")

        let text = AccountCardPresentation.displayEmail(for: account, showEmails: false)

        XCTAssertEqual(text, "d••••@example.com")
    }

    func testDisplayEmailFallsBackToAccountIDWhenMissingEmail() {
        let account = makeAccount(email: nil, accountID: "acct_123456789")

        let text = AccountCardPresentation.displayEmail(for: account, showEmails: false)

        XCTAssertEqual(text, "acct_1••••")
    }

    func testCurrentPresentationUsesLocalizedUsageAndPlanLabel() {
        let account = makeAccount(
            email: "dev@example.com",
            planType: "enterprise",
            usage: UsageSnapshot(
                fetchedAt: 1_763_216_000,
                planType: "enterprise",
                fiveHour: UsageWindow(usedPercent: 44, windowSeconds: 18_000, resetAt: 1_763_219_600),
                oneWeek: UsageWindow(usedPercent: 87, windowSeconds: 604_800, resetAt: 1_763_820_800),
                credits: nil
            )
        )

        let presentation = AccountCardPresentation.current(
            account: account,
            showEmails: true,
            now: Date(timeIntervalSince1970: 1_763_216_010)
        )

        XCTAssertEqual(presentation.emailText, "dev@example.com")
        XCTAssertEqual(presentation.planText, "Team")
        XCTAssertEqual(presentation.fiveHour.remainingPercentText, "56%")
        XCTAssertEqual(presentation.week.remainingPercentText, "13%")
    }

    func testWarningTextReturnsFiveHourWarningFirst() {
        let account = makeAccount(
            usage: UsageSnapshot(
                fetchedAt: 1_763_216_000,
                planType: "pro",
                fiveHour: UsageWindow(usedPercent: 92, windowSeconds: 18_000, resetAt: nil),
                oneWeek: UsageWindow(usedPercent: 90, windowSeconds: 604_800, resetAt: nil),
                credits: nil
            )
        )

        XCTAssertEqual(AccountCardPresentation.warningText(for: account), L10n.tr("switcher.warning.five_hour_low"))
    }

    func testRowPresentationMarksExpiredAccounts() {
        let account = AccountSummary(
            id: "acct-1",
            label: "Backup",
            email: "backup@example.com",
            accountID: "account-1",
            planType: "plus",
            teamName: nil,
            teamAlias: nil,
            addedAt: 0,
            updatedAt: 0,
            usage: nil,
            usageError: AccountsCoordinator.expiredMarker,
            isCurrent: false
        )

        let presentation = AccountCardPresentation.row(account: account, showEmails: false)

        XCTAssertTrue(presentation.isExpired)
        XCTAssertEqual(presentation.planText, L10n.tr("switcher.account.expired"))
    }

    func testRowPresentationIncludesWeeklyRemainingPercent() {
        let account = makeAccount(
            usage: UsageSnapshot(
                fetchedAt: 1_763_216_000,
                planType: "plus",
                fiveHour: UsageWindow(usedPercent: 40, windowSeconds: 18_000, resetAt: nil),
                oneWeek: UsageWindow(usedPercent: 87, windowSeconds: 604_800, resetAt: nil),
                credits: nil
            )
        )

        let presentation = AccountCardPresentation.row(account: account, showEmails: false)

        XCTAssertEqual(presentation.fiveHourLabelText, L10n.tr("switcher.metric.five_hours"))
        XCTAssertEqual(presentation.fiveHourPercentText, "60%")
        XCTAssertEqual(presentation.weekLabelText, L10n.tr("switcher.metric.weekly"))
        XCTAssertEqual(presentation.weekPercentText, "13%")
    }

    func testUpdatedTextUsesEnglishLocaleWhenAppLanguageIsEnglish() {
        L10n.setLocale(identifier: AppLocale.english.identifier)

        let text = AccountCardPresentation.updatedText(
            fetchedAt: 1_763_216_000,
            now: Date(timeIntervalSince1970: 1_763_216_060)
        )

        XCTAssertTrue(text.lowercased().contains("minute"))
    }

    func testUpdatedTextUsesChineseLocaleWhenAppLanguageIsChinese() {
        L10n.setLocale(identifier: AppLocale.simplifiedChinese.identifier)

        let text = AccountCardPresentation.updatedText(
            fetchedAt: 1_763_216_000,
            now: Date(timeIntervalSince1970: 1_763_216_060)
        )

        XCTAssertTrue(text.contains("分钟"))
    }

    private func makeAccount(
        email: String? = "dev@example.com",
        accountID: String = "account-1",
        planType: String? = "pro",
        usage: UsageSnapshot? = nil
    ) -> AccountSummary {
        AccountSummary(
            id: "acct-1",
            label: "Primary",
            email: email,
            accountID: accountID,
            planType: planType,
            teamName: nil,
            teamAlias: nil,
            addedAt: 0,
            updatedAt: 0,
            usage: usage,
            usageError: nil,
            isCurrent: false
        )
    }
}
