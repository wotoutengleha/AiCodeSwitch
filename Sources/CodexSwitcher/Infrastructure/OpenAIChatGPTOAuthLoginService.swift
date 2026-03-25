import Foundation
import CryptoKit

#if os(macOS)
import AppKit
#endif
#if os(iOS)
import AuthenticationServices
import UIKit
#endif

final class OpenAIChatGPTOAuthLoginService: ChatGPTOAuthLoginServiceProtocol, @unchecked Sendable {
    private enum Configuration {
        static let issuer = URL(string: "https://auth.openai.com")!
        static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
        static let originator = "codex_cli_rs"
        static let callbackPath = "/auth/callback"
        static let preferredCallbackPort: UInt16 = 1455
        static let maxPortScanOffset: UInt16 = 12
        static let scopes = "openid profile email offline_access api.connectors.read api.connectors.invoke"
    }

    private let configPath: URL
    private let session: URLSession
    #if os(iOS)
    @MainActor private static let authenticationSessionDriver = IOSWebAuthenticationSessionDriver()
    #endif

    init(configPath: URL, session: URLSession = .shared) {
        self.configPath = configPath
        self.session = session
    }

    func signInWithChatGPT(timeoutSeconds: TimeInterval) async throws -> ChatGPTOAuthTokens {
        let callback = OAuthCallbackBox<ChatGPTOAuthTokens>()
        let pkce = PKCECodes.make()
        let state = Self.randomBase64URL(byteCount: 32)
        let forcedWorkspaceID = resolveForcedWorkspaceID()

        let (server, port) = try makeCallbackServer(
            callback: callback,
            pkce: pkce,
            state: state,
            forcedWorkspaceID: forcedWorkspaceID
        )
        let redirectURI = Self.redirectURI(for: port)
        let authorizeURL = try makeAuthorizeURL(
            redirectURI: redirectURI,
            pkce: pkce,
            state: state,
            forcedWorkspaceID: forcedWorkspaceID
        )

        server.start()
        defer { server.stop() }

        try await beginAuthorizationSession(url: authorizeURL, callback: callback)

        do {
            let tokens = try await callback.wait(timeoutSeconds: timeoutSeconds) {
                AppError.io(L10n.tr("error.accounts.add_account_timeout"))
            }
            await endAuthorizationSession()
            return tokens
        } catch {
            await endAuthorizationSession()
            throw error
        }
    }

    func refreshTokensIfPossible(from authJSON: JSONValue) async throws -> ChatGPTOAuthTokens? {
        guard let tokens = authJSON["tokens"]?.objectValue ?? authJSON.objectValue else {
            return nil
        }
        guard let refreshToken = normalizedValue(tokens["refresh_token"]?.stringValue) else {
            return nil
        }

        var request = URLRequest(url: Self.endpointURL("/oauth/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": Configuration.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email"
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network(L10n.tr("error.oauth.token_exchange_failed_format", L10n.tr("error.usage.invalid_response")))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty ? "HTTP \(httpResponse.statusCode)" : String(detail.prefix(200))
            throw AppError.network(L10n.tr("error.oauth.token_exchange_failed_format", message))
        }

        let tokenResponse = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        let apiKey = try? await Self.exchangeIDTokenForAPIKey(session: session, idToken: tokenResponse.idToken)
        return ChatGPTOAuthTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: normalizedValue(tokenResponse.refreshToken) ?? refreshToken,
            idToken: tokenResponse.idToken,
            apiKey: apiKey
        )
    }

    private func beginAuthorizationSession(
        url: URL,
        callback: OAuthCallbackBox<ChatGPTOAuthTokens>
    ) async throws {
        #if os(macOS)
        guard NSWorkspace.shared.open(url) else {
            throw AppError.io(L10n.tr("error.oauth.browser_open_failed"))
        }
        #else
        try await Self.authenticationSessionDriver.start(url: url) { error in
            callback.fail(error)
        }
        #endif
    }

    private func endAuthorizationSession() async {
        #if os(iOS)
        await Self.authenticationSessionDriver.finishIfNeeded()
        #endif
    }

    private func makeCallbackServer(
        callback: OAuthCallbackBox<ChatGPTOAuthTokens>,
        pkce: PKCECodes,
        state: String,
        forcedWorkspaceID: String?
    ) throws -> (SimpleHTTPServer, UInt16) {
        let candidates = Self.callbackPortCandidates()
        var lastError: Error?

        for candidatePort in candidates {
            do {
                let redirectURI = Self.redirectURI(for: candidatePort)
                let server = try SimpleHTTPServer(port: candidatePort) { [session] request in
                    await Self.handleCallback(
                        request: request,
                        session: session,
                        redirectURI: redirectURI,
                        pkce: pkce,
                        state: state,
                        forcedWorkspaceID: forcedWorkspaceID,
                        callback: callback
                    )
                }
                return (server, candidatePort)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? AppError.io(L10n.tr("error.oauth.callback_server_start_failed"))
    }

    private static func handleCallback(
        request: HTTPRequest,
        session: URLSession,
        redirectURI: String,
        pkce: PKCECodes,
        state: String,
        forcedWorkspaceID: String?,
        callback: OAuthCallbackBox<ChatGPTOAuthTokens>
    ) async -> HTTPResponse {
        guard request.method == "GET" else {
            return .text(statusCode: 405, text: "Method Not Allowed")
        }

        switch request.path {
        case Configuration.callbackPath:
            let params = callbackParameters(from: request.queryItems)

            do {
                let code = try resolveAuthorizationCode(from: params, expectedState: state)
                do {
                    let tokens = try await exchangeCodeForTokens(
                        session: session,
                        redirectURI: redirectURI,
                        pkce: pkce,
                        code: code,
                        forcedWorkspaceID: forcedWorkspaceID
                    )
                    callback.succeed(tokens)
                    return .html(statusCode: 200, body: successPageHTML())
                } catch {
                    callback.fail(error)
                    return .html(statusCode: 500, body: errorPageHTML(message: error.localizedDescription))
                }
            } catch {
                let appError = normalizeCallbackError(error)
                callback.fail(appError)
                let statusCode = callbackHTTPStatusCode(for: appError)
                return .html(statusCode: statusCode, body: errorPageHTML(message: appError.localizedDescription))
            }
        case "/cancel":
            let error = AppError.io(L10n.tr("error.oauth.request_cancelled"))
            callback.fail(error)
            return .html(statusCode: 200, body: errorPageHTML(message: error.localizedDescription))
        default:
            return .text(statusCode: 404, text: "Not Found")
        }
    }

    static func callbackParameters(from queryItems: [URLQueryItem]) -> [String: String] {
        var params: [String: String] = [:]
        for item in queryItems {
            guard params[item.name] == nil else { continue }
            params[item.name] = item.value
        }
        return params
    }

    static func resolveAuthorizationCode(from params: [String: String], expectedState: String) throws -> String {
        let returnedState = normalizedQueryValue(params["state"])
        let stateMatches = returnedState == expectedState

        // Some browser-based localhost callback flows can still deliver a valid authorization
        // code while dropping or mutating the echoed state. The PKCE code verifier remains the
        // authoritative check, so prefer attempting the token exchange when a code is present.
        if let code = normalizedQueryValue(params["code"]) {
            return code
        }

        if let errorCode = normalizedQueryValue(params["error"]) {
            let description = normalizedQueryValue(params["error_description"])
            let message = description.map { L10n.tr("error.oauth.callback_failed_format", $0) }
                ?? L10n.tr("error.oauth.callback_failed_format", errorCode)
            throw AppError.unauthorized(message)
        }

        guard stateMatches else {
            throw AppError.unauthorized(L10n.tr("error.oauth.callback_state_mismatch"))
        }

        throw AppError.invalidData(L10n.tr("error.oauth.callback_missing_code"))
    }

    private static func normalizedQueryValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizeCallbackError(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .io(error.localizedDescription)
    }

    private static func callbackHTTPStatusCode(for error: AppError) -> Int {
        switch error {
        case .unauthorized:
            return 401
        case .invalidData:
            return 400
        case .fileNotFound, .io, .network:
            return 500
        }
    }

    private static func exchangeCodeForTokens(
        session: URLSession,
        redirectURI: String,
        pkce: PKCECodes,
        code: String,
        forcedWorkspaceID: String?
    ) async throws -> ChatGPTOAuthTokens {
        var request = URLRequest(url: endpointURL("/oauth/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("client_id", Configuration.clientID),
            ("code_verifier", pkce.codeVerifier)
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network(L10n.tr("error.oauth.token_exchange_failed_format", L10n.tr("error.usage.invalid_response")))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty ? "HTTP \(httpResponse.statusCode)" : String(detail.prefix(200))
            throw AppError.network(L10n.tr("error.oauth.token_exchange_failed_format", message))
        }

        let tokenResponse = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        if let forcedWorkspaceID {
            let accountID = try extractAccountID(fromIDToken: tokenResponse.idToken)
            guard accountID == forcedWorkspaceID else {
                throw AppError.unauthorized(L10n.tr("error.oauth.workspace_mismatch_format", forcedWorkspaceID))
            }
        }

        guard let refreshToken = normalizedQueryValue(tokenResponse.refreshToken) else {
            throw AppError.network(L10n.tr("error.oauth.token_exchange_failed_format", "Missing refresh_token"))
        }

        let apiKey = try? await exchangeIDTokenForAPIKey(session: session, idToken: tokenResponse.idToken)
        return ChatGPTOAuthTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: refreshToken,
            idToken: tokenResponse.idToken,
            apiKey: apiKey
        )
    }

    private static func exchangeIDTokenForAPIKey(session: URLSession, idToken: String) async throws -> String {
        var request = URLRequest(url: endpointURL("/oauth/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody([
            ("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange"),
            ("client_id", Configuration.clientID),
            ("requested_token", "openai-api-key"),
            ("subject_token", idToken),
            ("subject_token_type", "urn:ietf:params:oauth:token-type:id_token")
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw AppError.network(L10n.tr("error.oauth.api_key_exchange_failed"))
        }

        let payload = try JSONDecoder().decode(APIKeyExchangeResponse.self, from: data)
        return payload.accessToken
    }

    private func makeAuthorizeURL(
        redirectURI: String,
        pkce: PKCECodes,
        state: String,
        forcedWorkspaceID: String?
    ) throws -> URL {
        var components = URLComponents(url: Self.endpointURL("/oauth/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Configuration.scopes),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: Configuration.originator),
            URLQueryItem(name: "state", value: state)
        ]

        if let forcedWorkspaceID, !forcedWorkspaceID.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "allowed_workspace_id", value: forcedWorkspaceID))
        }

        guard let url = components?.url else {
            throw AppError.invalidData(L10n.tr("error.oauth.authorize_url_invalid"))
        }
        return url
    }

    private func resolveForcedWorkspaceID() -> String? {
        guard let raw = try? String(contentsOf: configPath, encoding: .utf8), !raw.isEmpty else {
            return nil
        }

        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("forced_chatgpt_workspace_id") else { continue }
            guard let equalIndex = trimmed.firstIndex(of: "=") else { continue }
            let value = trimmed[trimmed.index(after: equalIndex)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private static func extractAccountID(fromIDToken idToken: String) throws -> String {
        let segments = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count > 1 else {
            throw AppError.invalidData(L10n.tr("error.auth.id_token_invalid_format"))
        }

        let payload = try decodeBase64URL(String(segments[1]))
        let object = try JSONSerialization.jsonObject(with: payload)
        guard let json = try? JSONValue.from(any: object),
              let accountID = json["https://api.openai.com/auth"]?["chatgpt_account_id"]?.stringValue,
              !accountID.isEmpty else {
            throw AppError.invalidData(L10n.tr("error.auth.missing_chatgpt_account_id"))
        }
        return accountID
    }

    private static func decodeBase64URL(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else {
            throw AppError.invalidData(L10n.tr("error.auth.decode_id_token_failed"))
        }
        return data
    }

    private static func formEncodedBody(_ items: [(String, String)]) -> Data {
        let encoded = items
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .oauthFormAllowed) ?? value
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func endpointURL(_ path: String) -> URL {
        guard let url = URL(string: path, relativeTo: Configuration.issuer)?.absoluteURL else {
            return Configuration.issuer
        }
        return url
    }

    private static func redirectURI(for port: UInt16) -> String {
        "http://localhost:\(port)\(Configuration.callbackPath)"
    }

    private static func callbackPortCandidates() -> [UInt16] {
        let start = Configuration.preferredCallbackPort
        let end = Configuration.preferredCallbackPort + Configuration.maxPortScanOffset
        return Array(start ... end)
    }

    fileprivate static func randomBase64URL(byteCount: Int) -> String {
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }
        let data = Data(bytes)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func successPageHTML() -> Data {
        Data("<html><head><meta charset=\"utf-8\"><title>Codex Switcher</title></head><body style=\"font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;\"><h2>Sign-in complete</h2><p>You can return to Codex Switcher.</p></body></html>".utf8)
    }

    private static func errorPageHTML(message: String) -> Data {
        let escapedMessage = htmlEscape(message)
        return Data("<html><head><meta charset=\"utf-8\"><title>Codex Switcher</title></head><body style=\"font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;\"><h2>Sign-in failed</h2><p>\(escapedMessage)</p></body></html>".utf8)
    }

    private static func htmlEscape(_ value: String) -> String {
        var escaped = value
        let mappings = [
            ("&", "&amp;"),
            ("<", "&lt;"),
            (">", "&gt;"),
            ("\"", "&quot;"),
            ("'", "&#39;")
        ]
        for (source, target) in mappings {
            escaped = escaped.replacingOccurrences(of: source, with: target)
        }
        return escaped
    }
}

private struct PKCECodes {
    var codeVerifier: String
    var codeChallenge: String

    static func make() -> PKCECodes {
        let verifier = OpenAIChatGPTOAuthLoginService.randomBase64URL(byteCount: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return PKCECodes(codeVerifier: verifier, codeChallenge: challenge)
    }
}

private final class OAuthCallbackBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var result: Result<Value, AppError>?

    func wait(
        timeoutSeconds: TimeInterval,
        timeoutError: @escaping @Sendable () -> AppError
    ) async throws -> Value {
        let timeoutTask = Task { [weak self] in
            let nanoseconds = UInt64(max(timeoutSeconds, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            self?.fail(timeoutError())
        }
        defer { timeoutTask.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
                lock.lock()
                if let result {
                    lock.unlock()
                    resume(continuation, with: result)
                    return
                }
                self.continuation = continuation
                lock.unlock()
            }
        } onCancel: { [weak self] in
            self?.fail(AppError.io(L10n.tr("error.oauth.request_cancelled")))
        }
    }

    func succeed(_ value: Value) {
        resolve(.success(value))
    }

    func fail(_ error: Error) {
        resolve(.failure(Self.normalize(error)))
    }

    private func resolve(_ result: Result<Value, AppError>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        if let continuation {
            resume(continuation, with: result)
        }
    }

    private func resume(_ continuation: CheckedContinuation<Value, any Error>, with result: Result<Value, AppError>) {
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private static func normalize(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .io(error.localizedDescription)
    }
}

private struct TokenExchangeResponse: Decodable {
    let idToken: String
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct APIKeyExchangeResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

#if os(iOS)
@MainActor
private final class IOSWebAuthenticationSessionDriver: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var completionHandler: ((Error) -> Void)?

    func start(url: URL, completionHandler: @escaping (Error) -> Void) throws {
        finishIfNeeded()

        self.completionHandler = completionHandler
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: nil
        ) { [weak self] _, error in
            guard let self else { return }
            Task { @MainActor in
                let completionHandler = self.completionHandler
                self.completionHandler = nil
                self.session = nil

                guard let error else { return }
                completionHandler?(Self.normalize(error))
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false

        guard session.start() else {
            self.completionHandler = nil
            throw AppError.io(L10n.tr("error.oauth.browser_open_failed"))
        }

        self.session = session
    }

    func finishIfNeeded() {
        completionHandler = nil
        session?.cancel()
        session = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let foregroundScenes = windowScenes.filter {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }
        let windows = foregroundScenes.flatMap(\.windows)

        if let keyWindow = windows.first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let fallbackWindow = windows.first {
            return fallbackWindow
        }
        guard let fallbackScene = foregroundScenes.first ?? windowScenes.first else {
            preconditionFailure("ASWebAuthenticationSession requires a foreground window scene.")
        }
        return ASPresentationAnchor(windowScene: fallbackScene)
    }

    private static func normalize(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == ASWebAuthenticationSessionErrorDomain,
           nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            return AppError.io(L10n.tr("error.oauth.request_cancelled"))
        }
        return error
    }
}
#endif

private extension CharacterSet {
    static let oauthFormAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

private extension HTTPResponse {
    static func html(statusCode: Int, body: Data) -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: body
        )
    }
}
