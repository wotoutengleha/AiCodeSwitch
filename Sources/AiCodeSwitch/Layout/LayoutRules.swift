import SwiftUI

enum LayoutRules {
    static let outerWindowInset = CGFloat(0)
    static let pagePadding = CGFloat(10)
    static let panelContentInset = CGFloat(15)
    static let dividerInset = CGFloat(15)
    static let sectionSpacing = CGFloat(14)
    static let cardRadius = CGFloat(15)
    static let liquidProgressHeight = CGFloat(10)
    static let liquidProgressInset = CGFloat(2)
    static let listRowSpacing = CGFloat(8)
    static let tabSwitcherMaxWidth = CGFloat(260)
    static let minimumPanelHeight = CGFloat(420)
    static let defaultPanelHeight = CGFloat(620)
    static let accountsRowSpacing = CGFloat(14)
    static let accountsExpandedColumns = 1
    static let accountsCollapsedColumns = 1
    static let accountsCardWidth = CGFloat(318)
    static let iOSAccountsExpandedColumns = 1
    static let iOSAccountsCollapsedColumns = 1
    static let iOSAccountsScrollBottomPadding = CGFloat(28)
    static let iOSBottomBarHorizontalPadding = CGFloat(16)
    static let iOSBottomBarTopInset = CGFloat(8)
    static let iOSBottomBarBottomInset = CGFloat(10)
    static let iOSNoticeCornerRadius = CGFloat(14)
    static let iOSToolbarButtonSize = CGFloat(44)
    static let toolbarIconPointSize = CGFloat(15)
    static let toolbarRefreshIconOpticalScale = CGFloat(0.78)
    static let proxyDetailCardSpacing = CGFloat(12)
    static let proxyHeroPortFieldWidth = CGFloat(108)
    static let proxyRemoteFieldMinWidth = CGFloat(160)
    static let proxyRemoteActionMinWidth = CGFloat(118)
    static let proxyRemoteMetricMinWidth = CGFloat(108)
    static let proxyRemoteMetricHeight = CGFloat(68)
    static let proxyRemoteDetailMinWidth = CGFloat(220)
    static let proxyRemoteLogsHeight = CGFloat(120)
    static let proxyPublicModeMinWidth = CGFloat(240)
    static let proxyPublicFieldMinWidth = CGFloat(220)
    static let proxyPublicStatusCardMinWidth = CGFloat(170)

    static let switchRowCompactBarWidth = CGFloat(42)
    static let switchRowMetricWidth = CGFloat(130)
    static let switchRowSectionSpacing = CGFloat(8)
    static let menuRowHeight = CGFloat(34)
    static let menuIconWidth = CGFloat(15)
    static let menuRowSpacing = CGFloat(10)
    static let menuLeadingInset = CGFloat(6)

    static var accountsTwoColumnContentWidth: CGFloat {
        accountsCardWidth
    }

    static var accountsPageTargetWidth: CGFloat {
        accountsTwoColumnContentWidth + pagePadding * 2
    }

    static var accountsCollapsedCardWidth: CGFloat {
        accountsCardWidth
    }

    static var minimumPanelWidth: CGFloat {
        344
    }

    static var defaultPanelWidth: CGFloat {
        356
    }

    static var maximumPanelWidth: CGFloat {
        356
    }

    static func accountsPanelHeight(
        switchableAccountCount: Int,
        hasQuotaWarning: Bool,
        hasNotice: Bool
    ) -> CGFloat {
        let warningHeight = hasQuotaWarning ? CGFloat(20) : 0
        let noticeHeight = hasNotice ? CGFloat(34) : 0
        let switchContentHeight: CGFloat

        if switchableAccountCount == 0 {
            switchContentHeight = 54
        } else {
            switchContentHeight = CGFloat(switchableAccountCount) * 54
                + CGFloat(max(0, switchableAccountCount - 1)) * 14
        }

        let baseHeight = CGFloat(392)
        return min(max(baseHeight + warningHeight + noticeHeight + switchContentHeight, 446), 720)
    }

    static func settingsPanelHeight(hasNotice: Bool) -> CGFloat {
        let noticeHeight = hasNotice ? CGFloat(34) : 0
        return 316 + noticeHeight
    }

    static func iOSAccountsContentTopPadding(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + pagePadding
    }

    static func iOSAccountsContentBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom + iOSAccountsScrollBottomPadding
    }

    static func accountsGridColumns(isOverviewMode: Bool, isCompactWidth: Bool) -> [GridItem] {
        [
            GridItem(
                .flexible(minimum: 0, maximum: .infinity),
                spacing: accountsRowSpacing,
                alignment: .top
            )
        ]
    }

    static func accountsCardFrameWidth(isOverviewMode: Bool, isCompactWidth: Bool) -> CGFloat? {
        isCompactWidth ? nil : accountsCardWidth
    }
}
