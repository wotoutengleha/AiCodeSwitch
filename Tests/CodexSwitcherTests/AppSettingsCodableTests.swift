import XCTest
@testable import CodexSwitcher

final class AppSettingsCodableTests: XCTestCase {
    func testDecodeLegacySettingsWithoutAutoSmartSwitchUsesDefault() throws {
        let json = """
        {
          "launchAtStartup": true,
          "trayUsageDisplayMode": "remaining",
          "launchCodexAfterSwitch": true,
          "syncOpencodeOpenaiAuth": false,
          "restartEditorsOnSwitch": false,
          "restartEditorTargets": [],
          "autoStartApiProxy": true,
          "remoteServers": [],
          "locale": "en"
        }
        """

        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.autoSmartSwitch, false)
        XCTAssertEqual(decoded.autoStartApiProxy, true)
        XCTAssertEqual(decoded.locale, AppLocale.english.identifier)
        XCTAssertEqual(decoded.showEmails, false)
        XCTAssertEqual(decoded.autoRefreshIntervalMinutes, 5)
    }

    func testDecodeInvalidAutoRefreshIntervalFallsBackToFiveMinutes() throws {
        let json = """
        {
          "launchAtStartup": false,
          "launchCodexAfterSwitch": true,
          "showEmails": false,
          "autoRefreshIntervalMinutes": 3,
          "locale": "zh-Hans"
        }
        """

        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.autoRefreshIntervalMinutes, 5)
    }
}
