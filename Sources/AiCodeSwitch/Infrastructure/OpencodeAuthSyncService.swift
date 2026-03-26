import Foundation
#if canImport(Security)
import Security
#endif

final class OpencodeAuthSyncService: OpencodeAuthSyncServiceProtocol, @unchecked Sendable {
    private static let fallbackExpiresInMs: Int64 = 55 * 60 * 1000

    func syncFromCodexAuth(_ authJSON: JSONValue) throws {
        let tokens = try extractTokens(from: authJSON)
        let paths = detectAuthPaths()
        guard !paths.isEmpty else {
            throw AppError.fileNotFound(L10n.tr("error.opencode.auth_path_not_found"))
        }

        var success = 0
        var errors: [String] = []
        for path in paths {
            do {
                try syncToPath(path, tokens: tokens)
                success += 1
            } catch {
                errors.append("\(path.path): \(error.localizedDescription)")
            }
        }

        guard success > 0 else {
            throw AppError.io(errors.joined(separator: " | "))
        }
    }

    private func syncToPath(_ path: URL, tokens: OAuthTokens) throws {
        let root = try readOrInitJSONObject(path)
        var openai = root["openai"] as? [String: Any] ?? [:]

        let expires = tokens.expiresAtMs ?? (nowUnixMillis() + Self.fallbackExpiresInMs)
        openai["type"] = (openai["type"] as? String) ?? "oauth"
        openai["access"] = tokens.accessToken
        openai["refresh"] = tokens.refreshToken
        openai["expires"] = expires
        if let accountID = tokens.accountID {
            openai["accountId"] = accountID
        }

        var merged = root
        merged["openai"] = openai

        let parent = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: path, options: .atomic)
        #if canImport(Darwin)
        _ = chmod(path.path, S_IRUSR | S_IWUSR)
        #endif
    }

    private func readOrInitJSONObject(_ path: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return [:]
        }
        let data = try Data(contentsOf: path)
        let obj = try JSONSerialization.jsonObject(with: data)
        return obj as? [String: Any] ?? [:]
    }

    private func detectAuthPaths() -> [URL] {
        if let custom = ProcessInfo.processInfo.environment["OPENCODE_AUTH_PATH"], !custom.isEmpty {
            return [URL(fileURLWithPath: custom)]
        }

        #if os(iOS)
        let appSupportBase = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let fallback = appSupportBase
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
        return [fallback]
        #else
        var candidates: [URL] = []
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser

        if let configHome = env["OPENCODE_CONFIG_HOME"], !configHome.isEmpty {
            candidates.append(URL(fileURLWithPath: configHome).appendingPathComponent("auth.json"))
        }
        if let xdgConfig = env["XDG_CONFIG_HOME"], !xdgConfig.isEmpty {
            candidates.append(URL(fileURLWithPath: xdgConfig).appendingPathComponent("opencode/auth.json"))
        }

        candidates.append(home.appendingPathComponent(".config/opencode/auth.json"))
        candidates.append(home.appendingPathComponent("Library/Application Support/opencode/auth.json"))

        if let xdgData = env["XDG_DATA_HOME"], !xdgData.isEmpty {
            candidates.append(URL(fileURLWithPath: xdgData).appendingPathComponent("opencode/auth.json"))
        }

        candidates.append(home.appendingPathComponent(".local/share/opencode/auth.json"))
        candidates.append(home.appendingPathComponent(".opencode/auth.json"))

        var unique: [URL] = []
        for url in candidates where !unique.contains(url) {
            unique.append(url)
        }

        let existing = unique.filter { FileManager.default.fileExists(atPath: $0.path) }
        return existing.isEmpty ? (unique.first.map { [$0] } ?? []) : existing
        #endif
    }

    private func extractTokens(from authJSON: JSONValue) throws -> OAuthTokens {
        guard let tokenObject = tokenObject(from: authJSON) else {
            throw AppError.invalidData(L10n.tr("error.opencode.missing_tokens"))
        }

        guard let access = tokenObject["access_token"]?.stringValue else {
            throw AppError.invalidData(L10n.tr("error.auth.missing_access_token"))
        }
        guard let refresh = tokenObject["refresh_token"]?.stringValue else {
            throw AppError.invalidData(L10n.tr("error.opencode.missing_refresh_token"))
        }
        let accountID = tokenObject["account_id"]?.stringValue

        let expiresAtMs = tokenObject["id_token"]?.stringValue
            .flatMap { try? decodeJWTPayload($0) }
            .flatMap { payload -> Int64? in
                guard let exp = payload["exp"]?.int64Value else { return nil }
                return exp * 1000
            }

        return OAuthTokens(
            accessToken: access,
            refreshToken: refresh,
            accountID: accountID,
            expiresAtMs: expiresAtMs
        )
    }

    private func tokenObject(from auth: JSONValue) -> [String: JSONValue]? {
        if let tokens = auth["tokens"]?.objectValue {
            return tokens
        }
        if let object = auth.objectValue,
           object["access_token"]?.stringValue != nil {
            return object
        }
        return nil
    }

    private func decodeJWTPayload(_ token: String) throws -> JSONValue {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else {
            throw AppError.invalidData(L10n.tr("error.auth.id_token_invalid_format"))
        }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload) else {
            throw AppError.invalidData(L10n.tr("error.auth.decode_id_token_failed"))
        }
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONValue.from(any: object)
    }

    private func nowUnixMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

private struct OAuthTokens {
    var accessToken: String
    var refreshToken: String
    var accountID: String?
    var expiresAtMs: Int64?
}

final class KeychainAccountVault: AccountVault, @unchecked Sendable {
    private let service = "com.wenlong.aicodeswitch.auth"
    private let legacyServices = [
        "com.wenlong.codexswitcher.auth"
    ]
    private let fallbackDirectory: URL?
    private let fileManager: FileManager

    init(fallbackDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fallbackDirectory = fallbackDirectory
        self.fileManager = fileManager
    }

    func save(authJSON: JSONValue, for accountID: String) throws {
        let data = try encode(authJSON)
        let addQuery = makeAddQuery(for: accountID, service: service, data: data)

        // Best-effort cleanup. Old builds may have created items with a different
        // code signature and ACL, so we ignore delete failures and simply write
        // into the new namespace.
        for candidate in allServices {
            SecItemDelete(baseQuery(for: accountID, service: candidate) as CFDictionary)
        }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query = baseQuery(for: accountID, service: service)
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
            if shouldUseFileFallback(for: updateStatus) {
                try saveFallback(data: data, for: accountID)
                return
            }
            guard updateStatus == errSecSuccess else {
                throw AppError.io("Failed to update account credentials in Keychain (\(updateStatus)).")
            }
            return
        }

        if shouldUseFileFallback(for: status) {
            try saveFallback(data: data, for: accountID)
            return
        }
        guard status == errSecSuccess else {
            throw AppError.io("Failed to save account credentials to Keychain (\(status)).")
        }
    }

    func loadAuth(for accountID: String) throws -> JSONValue {
        var firstError: OSStatus?
        for candidate in allServices {
            var query = baseQuery(for: accountID, service: candidate)
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = kCFBooleanTrue

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound {
                continue
            }
            guard status == errSecSuccess, let data = result as? Data else {
                firstError = firstError ?? status
                continue
            }

            let object = try JSONSerialization.jsonObject(with: data)
            let auth = try JSONValue.from(any: object)

            if candidate != service {
                try? save(authJSON: auth, for: accountID)
            }
            return auth
        }

        if let fallback = try? loadFallback(for: accountID) {
            return fallback
        }
        if let firstError {
            throw AppError.io("Failed to load account credentials from Keychain (\(firstError)).")
        }
        throw AppError.fileNotFound("No saved credentials found for this account.")
    }

    func removeAuth(for accountID: String) throws {
        var firstError: OSStatus?
        for candidate in allServices {
            let status = SecItemDelete(baseQuery(for: accountID, service: candidate) as CFDictionary)
            switch status {
            case errSecSuccess, errSecItemNotFound:
                continue
            default:
                if !shouldUseFileFallback(for: status) {
                    firstError = firstError ?? status
                }
            }
        }

        if let firstError {
            throw AppError.io("Failed to delete account credentials from Keychain (\(firstError)).")
        }

        try removeFallback(for: accountID)
    }

    private var allServices: [String] {
        [service] + legacyServices
    }

    private func makeAddQuery(for accountID: String, service: String, data: Data) -> [String: Any] {
        var addQuery = baseQuery(for: accountID, service: service)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return addQuery
    }

    private func encode(_ authJSON: JSONValue) throws -> Data {
        let object = authJSON.toAny()
        guard JSONSerialization.isValidJSONObject(object) else {
            throw AppError.invalidData("Account auth payload has an invalid JSON structure.")
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func baseQuery(for accountID: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
        ]
    }

    private func shouldUseFileFallback(for status: OSStatus) -> Bool {
        status == errSecAuthFailed ||
        status == errSecInteractionNotAllowed ||
        status == errSecNotAvailable
    }

    private func saveFallback(data: Data, for accountID: String) throws {
        guard let fileURL = fallbackFileURL(for: accountID) else {
            throw AppError.io("Failed to save account credentials to Keychain.")
        }
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        #if canImport(Darwin)
        _ = chmod(fileURL.path, S_IRUSR | S_IWUSR)
        #endif
    }

    private func loadFallback(for accountID: String) throws -> JSONValue {
        guard let fileURL = fallbackFileURL(for: accountID),
              fileManager.fileExists(atPath: fileURL.path) else {
            throw AppError.fileNotFound("No saved credentials found for this account.")
        }
        let data = try Data(contentsOf: fileURL)
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONValue.from(any: object)
    }

    private func removeFallback(for accountID: String) throws {
        guard let fileURL = fallbackFileURL(for: accountID),
              fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }

    private func fallbackFileURL(for accountID: String) -> URL? {
        fallbackDirectory?
            .appendingPathComponent("private-auth", isDirectory: true)
            .appendingPathComponent("\(accountID).json", isDirectory: false)
    }
}
