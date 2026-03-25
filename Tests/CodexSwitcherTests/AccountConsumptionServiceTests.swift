import XCTest
@testable import CodexSwitcher

final class AccountConsumptionServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        let resetExpectation = expectation(description: "reset consumption mock protocol")
        Task {
            await ConsumptionMockURLProtocol.store.reset()
            resetExpectation.fulfill()
        }
        wait(for: [resetExpectation], timeout: 1)
    }

    func testFetchSummaryAggregatesTodayAndLastThirtyDays() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConsumptionMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = DefaultAccountConsumptionService(
            session: session,
            calendar: Calendar(identifier: .gregorian)
        )
        let now = Date(timeIntervalSince1970: 1_763_216_000)

        await ConsumptionMockURLProtocol.store.setHandler { request in
            let url = try XCTUnwrap(request.url)
            let path = url.path
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let startTime = items.first(where: { $0.name == "start_time" })?.value
            let limit = items.first(where: { $0.name == "limit" })?.value

            let data: Data
            switch (path, limit, startTime) {
            case ("/v1/organization/usage/completions", "1", _):
                data = Data(
                    #"{"object":"page","data":[{"object":"bucket","start_time":1763164800,"end_time":1763251200,"results":[{"object":"organization.usage.completions.result","input_tokens":1100000,"output_tokens":100000,"input_audio_tokens":0,"output_audio_tokens":0}]}]}"#.utf8
                )
            case ("/v1/organization/costs", "1", _):
                data = Data(
                    #"{"object":"page","data":[{"object":"bucket","start_time":1763164800,"end_time":1763251200,"results":[{"object":"organization.costs.result","amount":{"value":16.9,"currency":"usd"},"line_item":null}]}]}"#.utf8
                )
            case ("/v1/organization/usage/completions", "30", _):
                data = Data(
                    #"{"object":"page","data":[{"object":"bucket","start_time":1760572800,"end_time":1760659200,"results":[{"object":"organization.usage.completions.result","input_tokens":4000000,"output_tokens":1000000}]},{"object":"bucket","start_time":1763164800,"end_time":1763251200,"results":[{"object":"organization.usage.completions.result","input_tokens":29000000,"output_tokens":4000000}]}]}"#.utf8
                )
            case ("/v1/organization/costs", "30", _):
                data = Data(
                    #"{"object":"page","data":[{"object":"bucket","start_time":1760572800,"end_time":1760659200,"results":[{"object":"organization.costs.result","amount":{"value":59.65,"currency":"usd"},"line_item":null}]},{"object":"bucket","start_time":1763164800,"end_time":1763251200,"results":[{"object":"organization.costs.result","amount":{"value":16.9,"currency":"usd"},"line_item":null}]}]}"#.utf8
                )
            default:
                XCTFail("Unexpected request: \(url.absoluteString)")
                data = Data()
            }

            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let summary = try await service.fetchSummary(apiKey: "sk-test", now: now)

        XCTAssertEqual(summary.todayTokens, 1_200_000)
        XCTAssertEqual(summary.todayCost, 16.9, accuracy: 0.0001)
        XCTAssertEqual(summary.last30DaysTokens, 38_000_000)
        XCTAssertEqual(summary.last30DaysCost, 76.55, accuracy: 0.0001)
        XCTAssertEqual(summary.currencyCode, "USD")
    }

    func testFetchSummaryTreatsUnauthorizedAsUnauthorizedError() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConsumptionMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = DefaultAccountConsumptionService(
            session: session,
            calendar: Calendar(identifier: .gregorian)
        )

        await ConsumptionMockURLProtocol.store.setHandler { request in
            let url = try XCTUnwrap(request.url)
            return (
                HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data(#"{"error":"unauthorized"}"#.utf8)
            )
        }

        do {
            _ = try await service.fetchSummary(apiKey: "sk-test", now: Date(timeIntervalSince1970: 1_763_216_000))
            XCTFail("Expected unauthorized error")
        } catch let error as AppError {
            guard case .unauthorized = error else {
                XCTFail("Expected unauthorized error, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected AppError.unauthorized, got \(error)")
        }
    }

    func testFetchLocalSummaryAggregatesCodexSessionLogs() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: 2026,
                month: 3,
                day: 24,
                hour: 16,
                minute: 0,
                second: 0
            ))
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let codexHome = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
        let sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
        let archivedRoot = codexHome.appendingPathComponent("archived_sessions", isDirectory: true)

        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archivedRoot, withIntermediateDirectories: true)

        try writeSessionFile(
            root: sessionsRoot,
            day: "2026-03-24",
            fileName: "session-a.jsonl",
            contents: [
                #"{"type":"session_meta","payload":{"session_id":"session-a"}}"#,
                #"{"type":"turn_context","payload":{"model":"gpt-5"}}"#,
                #"{"timestamp":"2026-03-24T09:15:00Z","type":"event_msg","payload":{"type":"token_count","info":{"model":"gpt-5","total_token_usage":{"input_tokens":2000000,"cached_input_tokens":500000,"output_tokens":300000}}}}"#
            ]
        )
        try writeSessionFile(
            root: sessionsRoot,
            day: "2026-03-10",
            fileName: "session-b.jsonl",
            contents: [
                #"{"type":"session_meta","payload":{"session_id":"session-b"}}"#,
                #"{"type":"turn_context","payload":{"model":"gpt-5"}}"#,
                #"{"timestamp":"2026-03-10T14:05:00Z","type":"event_msg","payload":{"type":"token_count","info":{"model":"gpt-5","last_token_usage":{"input_tokens":1000000,"cached_input_tokens":0,"output_tokens":200000}}}}"#
            ]
        )
        try writeSessionFile(
            root: archivedRoot,
            day: "2026-03-24",
            fileName: "session-a-copy.jsonl",
            contents: [
                #"{"type":"session_meta","payload":{"session_id":"session-a"}}"#,
                #"{"type":"turn_context","payload":{"model":"gpt-5"}}"#,
                #"{"timestamp":"2026-03-24T09:15:00Z","type":"event_msg","payload":{"type":"token_count","info":{"model":"gpt-5","total_token_usage":{"input_tokens":2000000,"cached_input_tokens":500000,"output_tokens":300000}}}}"#
            ]
        )

        let loader = LocalCodexSessionConsumptionLoader(
            fileManager: .default,
            calendar: calendar,
            environment: ["CODEX_HOME": codexHome.path]
        )
        let service = DefaultAccountConsumptionService(
            session: .shared,
            calendar: calendar,
            localConsumptionLoader: loader
        )

        let summary = await service.fetchLocalSummary(now: now)

        XCTAssertEqual(summary?.todayTokens, 2_300_000)
        XCTAssertEqual(summary?.todayCost ?? 0, 4.9375, accuracy: 0.0001)
        XCTAssertEqual(summary?.last30DaysTokens, 3_500_000)
        XCTAssertEqual(summary?.last30DaysCost ?? 0, 8.1875, accuracy: 0.0001)
        XCTAssertEqual(summary?.currencyCode, "USD")
    }
}

private func writeSessionFile(
    root: URL,
    day: String,
    fileName: String,
    contents: [String]
) throws {
    let parts = day.split(separator: "-")
    let directory = root
        .appendingPathComponent(String(parts[0]), isDirectory: true)
        .appendingPathComponent(String(parts[1]), isDirectory: true)
        .appendingPathComponent(String(parts[2]), isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent(fileName)
    let body = contents.joined(separator: "\n") + "\n"
    try body.write(to: fileURL, atomically: true, encoding: .utf8)
}

private final class ConsumptionMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = ConsumptionMockURLProtocolStore()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Task {
            do {
                guard let handler = await Self.store.handler() else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                    return
                }

                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private actor ConsumptionMockURLProtocolStore {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private var currentHandler: Handler?

    func setHandler(_ handler: @escaping Handler) {
        currentHandler = handler
    }

    func handler() -> Handler? {
        currentHandler
    }

    func reset() {
        currentHandler = nil
    }
}
