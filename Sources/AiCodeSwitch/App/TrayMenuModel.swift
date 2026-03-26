import Foundation
import Combine

extension Notification.Name {
    static let copoolAccountsSnapshotPushDidArrive = Notification.Name("copool.accounts-snapshot.push")
    static let copoolCurrentAccountSelectionPushDidArrive = Notification.Name("copool.current-account-selection.push")
    static let copoolProxyControlPushDidArrive = Notification.Name("copool.proxy-control.push")
}

@MainActor
final class TrayMenuModel: ObservableObject {
    @Published var accounts: [AccountSummary] = []
    @Published var notice: String?
    @Published private(set) var isFetchingRemoteUsage = false

    func startBackgroundRefresh() {}
    func stopBackgroundRefresh() {}
    func applySettings(_ settings: AppSettings) { _ = settings }
    func acceptLocalAccountsSnapshot(_ accounts: [AccountSummary]) { self.accounts = accounts }
}

struct CloudPushPullRetryPolicy: Sendable {
    let maxAttempts: Int
    let retryInterval: Duration

    static let nearRealtime = CloudPushPullRetryPolicy(
        maxAttempts: 12,
        retryInterval: .milliseconds(250)
    )
}
