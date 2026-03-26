import Foundation

#if os(macOS)
private struct OpenClawAuthProfilesDocument: Decodable {
    struct Profile: Decodable {
        var provider: String
        var email: String?
        var accountId: String?
    }

    var profiles: [String: Profile]
    var lastGood: [String: String]?
}

final class OpenClawProfileRepository: @unchecked Sendable {
    let authProfilesPath: URL

    init(authProfilesPath: URL) {
        self.authProfilesPath = authProfilesPath
    }

    fileprivate func loadDocument() throws -> OpenClawAuthProfilesDocument {
        let data = try Data(contentsOf: authProfilesPath)
        return try JSONDecoder().decode(OpenClawAuthProfilesDocument.self, from: data)
    }

    func updateLastGood(provider: String, profileID: String) throws {
        let data = try Data(contentsOf: authProfilesPath)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.invalidData("OpenClaw auth-profiles.json is not a valid JSON object.")
        }

        var lastGood = root["lastGood"] as? [String: Any] ?? [:]
        lastGood[provider] = profileID
        root["lastGood"] = lastGood

        let updatedData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try updatedData.write(to: authProfilesPath, options: .atomic)
    }
}

final class OpenClawSwitchService: OpenClawSwitchServiceProtocol, @unchecked Sendable {
    private static let providerID = "openai-codex"

    private let profileRepository: OpenClawProfileRepository

    init(profileRepository: OpenClawProfileRepository) {
        self.profileRepository = profileRepository
    }

    func syncCodexAccount(email: String?, accountID: String) async -> OpenClawSwitchExecutionResult {
        do {
            let document = try profileRepository.loadDocument()
            let providerProfiles = document.profiles
                .filter { $0.value.provider == Self.providerID }
                .map { OpenClawProfile(id: $0.key, email: normalized($0.value.email), accountID: normalized($0.value.accountId)) }

            guard !providerProfiles.isEmpty else {
                return .init(
                    synced: false,
                    warning: L10n.tr("switcher.notice.openclaw_missing_profiles"),
                    error: nil
                )
            }

            guard let targetProfile = resolveTargetProfile(
                profiles: providerProfiles,
                email: normalized(email),
                accountID: accountID
            ) else {
                let fallbackLabel = normalized(email) ?? accountID
                return .init(
                    synced: false,
                    warning: L10n.tr("switcher.notice.openclaw_account_not_found", fallbackLabel),
                    error: nil
                )
            }

            let orderedProfiles = [targetProfile.id] + providerProfiles
                .map(\.id)
                .filter { $0 != targetProfile.id }
                .sorted()

            let openclawPath = try resolveOpenClawExecutablePath()
            _ = try CommandRunner.runChecked(
                openclawPath,
                arguments: ["models", "auth", "order", "set", "--provider", Self.providerID] + orderedProfiles,
                timeout: 15,
                errorPrefix: L10n.tr("error.openclaw_sync.order_set_failed")
            )
            try profileRepository.updateLastGood(provider: Self.providerID, profileID: targetProfile.id)
            _ = try CommandRunner.runChecked(
                openclawPath,
                arguments: ["gateway", "restart"],
                timeout: 20,
                errorPrefix: L10n.tr("error.openclaw_sync.restart_failed")
            )

            return .init(synced: true, warning: nil, error: nil)
        } catch {
            return .init(synced: false, warning: nil, error: error.localizedDescription)
        }
    }

    private func resolveTargetProfile(
        profiles: [OpenClawProfile],
        email: String?,
        accountID: String
    ) -> OpenClawProfile? {
        if let email {
            if let matchedByEmail = profiles.first(where: { $0.email == email }) {
                return matchedByEmail
            }
            let profileID = "\(Self.providerID):\(email)"
            if let matchedByID = profiles.first(where: { $0.id == profileID }) {
                return matchedByID
            }
        }

        return profiles.first(where: { $0.accountID == accountID })
    }

    private func resolveOpenClawExecutablePath() throws -> String {
        if let resolved = CommandRunner.resolveExecutable("openclaw"), !resolved.isEmpty {
            return resolved
        }
        throw AppError.fileNotFound(L10n.tr("error.openclaw_sync.executable_not_found"))
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct OpenClawProfile: Equatable {
    var id: String
    var email: String?
    var accountID: String?
}
#else
final class OpenClawProfileRepository: @unchecked Sendable {
    init(authProfilesPath: URL) {
        _ = authProfilesPath
    }
}

final class OpenClawSwitchService: OpenClawSwitchServiceProtocol, @unchecked Sendable {
    init(profileRepository: OpenClawProfileRepository) {
        _ = profileRepository
    }

    func syncCodexAccount(email: String?, accountID: String) async -> OpenClawSwitchExecutionResult {
        _ = email
        _ = accountID
        return .notRequested
    }
}
#endif
