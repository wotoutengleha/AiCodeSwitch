import Foundation

final class DefaultAccountConsumptionService: AccountConsumptionService, @unchecked Sendable {
    private enum RequestPolicy {
        static let timeout: TimeInterval = 15
        static let userAgent = "codex-switcher/0.1"
        static let baseURL = "https://api.openai.com/v1"
    }

    private let session: URLSession
    private let calendar: Calendar
    private let localConsumptionLoader: LocalCodexSessionConsumptionLoader

    init(
        session: URLSession = .shared,
        calendar: Calendar = .autoupdatingCurrent,
        localConsumptionLoader: LocalCodexSessionConsumptionLoader? = nil
    ) {
        self.session = session
        self.calendar = calendar
        self.localConsumptionLoader = localConsumptionLoader ?? LocalCodexSessionConsumptionLoader(calendar: calendar)
    }

    func fetchSummary(apiKey: String, now: Date) async throws -> AccountTokenCostSummary {
        let todayStart = calendar.startOfDay(for: now)
        guard let rollingStart = calendar.date(byAdding: .day, value: -29, to: todayStart) else {
            throw AppError.invalidData(L10n.tr("error.consumption.invalid_response"))
        }

        async let todayTokens = fetchTokenTotal(
            apiKey: apiKey,
            start: todayStart,
            end: now,
            bucketLimit: 1
        )
        async let todayCosts = fetchCostTotal(
            apiKey: apiKey,
            start: todayStart,
            end: now,
            bucketLimit: 1
        )
        async let rollingTokens = fetchTokenTotal(
            apiKey: apiKey,
            start: rollingStart,
            end: now,
            bucketLimit: 30
        )
        async let rollingCosts = fetchCostTotal(
            apiKey: apiKey,
            start: rollingStart,
            end: now,
            bucketLimit: 30
        )

        let resolvedTodayTokens = try await todayTokens
        let resolvedTodayCosts = try await todayCosts
        let resolvedRollingTokens = try await rollingTokens
        let resolvedRollingCosts = try await rollingCosts

        return AccountTokenCostSummary(
            todayCost: resolvedTodayCosts.value,
            todayTokens: resolvedTodayTokens,
            last30DaysCost: resolvedRollingCosts.value,
            last30DaysTokens: resolvedRollingTokens,
            currencyCode: resolvedRollingCosts.currencyCode ?? resolvedTodayCosts.currencyCode ?? "USD"
        )
    }

    func fetchLocalSummary(now: Date) async -> AccountTokenCostSummary? {
        localConsumptionLoader.loadSummary(now: now)
    }

    private func fetchTokenTotal(
        apiKey: String,
        start: Date,
        end: Date,
        bucketLimit: Int
    ) async throws -> Int64 {
        let request = try makeRequest(
            path: "/organization/usage/completions",
            apiKey: apiKey,
            queryItems: [
                URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))),
                URLQueryItem(name: "end_time", value: String(Int(end.timeIntervalSince1970))),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: String(bucketLimit))
            ]
        )
        let json = try await performJSONRequest(request)
        guard let buckets = json["data"]?.arrayValue else {
            throw AppError.invalidData(L10n.tr("error.consumption.invalid_response"))
        }

        var total: Int64 = 0
        for bucket in buckets {
            for result in bucket["results"]?.arrayValue ?? [] {
                total += result["input_tokens"]?.int64Value ?? 0
                total += result["output_tokens"]?.int64Value ?? 0
                total += result["input_audio_tokens"]?.int64Value ?? 0
                total += result["output_audio_tokens"]?.int64Value ?? 0
            }
        }
        return total
    }

    private func fetchCostTotal(
        apiKey: String,
        start: Date,
        end: Date,
        bucketLimit: Int
    ) async throws -> CostAggregate {
        let request = try makeRequest(
            path: "/organization/costs",
            apiKey: apiKey,
            queryItems: [
                URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))),
                URLQueryItem(name: "end_time", value: String(Int(end.timeIntervalSince1970))),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: String(bucketLimit))
            ]
        )
        let json = try await performJSONRequest(request)
        guard let buckets = json["data"]?.arrayValue else {
            throw AppError.invalidData(L10n.tr("error.consumption.invalid_response"))
        }

        var total = 0.0
        var currencyCode: String?

        for bucket in buckets {
            for result in bucket["results"]?.arrayValue ?? [] {
                total += result["amount"]?["value"]?.doubleValue ?? 0
                if currencyCode == nil,
                   let value = result["amount"]?["currency"]?.stringValue,
                   !value.isEmpty {
                    currencyCode = value.uppercased()
                }
            }
        }

        return CostAggregate(value: total, currencyCode: currencyCode)
    }

    private func makeRequest(
        path: String,
        apiKey: String,
        queryItems: [URLQueryItem]
    ) throws -> URLRequest {
        guard var components = URLComponents(string: RequestPolicy.baseURL + path) else {
            throw AppError.invalidData(L10n.tr("error.consumption.invalid_response"))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw AppError.invalidData(L10n.tr("error.consumption.invalid_response"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = RequestPolicy.timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(RequestPolicy.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func performJSONRequest(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidData(L10n.tr("error.consumption.invalid_response"))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = detail.isEmpty ? "HTTP \(httpResponse.statusCode)" : String(detail.prefix(200))
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AppError.unauthorized(message)
            }
            throw AppError.network(L10n.tr("error.consumption.request_failed_format", message))
        }

        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONValue.from(any: object)
    }
}

private struct CostAggregate {
    var value: Double
    var currencyCode: String?
}
