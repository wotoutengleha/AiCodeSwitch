import Foundation

struct LocalCodexSessionConsumptionLoader {
    fileprivate struct TokenTotals {
        var input: Int
        var cached: Int
        var output: Int
    }

    private struct ParsedFile {
        var sessionID: String?
        var usageByDay: [String: [String: TokenTotals]]
    }

    private let fileManager: FileManager
    private let calendar: Calendar
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .autoupdatingCurrent,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.environment = environment
    }

    func loadSummary(now: Date) -> AccountTokenCostSummary? {
        let todayStart = calendar.startOfDay(for: now)
        guard let rollingStart = calendar.date(byAdding: .day, value: -29, to: todayStart) else {
            return nil
        }

        let roots = sessionRoots()
        var seenPaths = Set<String>()
        var seenSessionIDs = Set<String>()
        var merged: [String: [String: TokenTotals]] = [:]

        for root in roots {
            for fileURL in listSessionFiles(root: root, since: rollingStart, until: now) {
                guard seenPaths.insert(fileURL.path).inserted else { continue }
                guard let parsed = parseFile(fileURL) else { continue }
                if let sessionID = parsed.sessionID, seenSessionIDs.contains(sessionID) {
                    continue
                }
                if let sessionID = parsed.sessionID {
                    seenSessionIDs.insert(sessionID)
                }
                merge(parsed.usageByDay, into: &merged)
            }
        }

        let todayKey = dayKey(for: todayStart)
        let rollingRangeKeys = dayKeys(since: rollingStart, until: now)

        var todayInput = 0
        var todayOutput = 0
        var rollingInput = 0
        var rollingOutput = 0
        var sawUsage = false

        for (dayKey, models) in merged {
            let inRollingWindow = rollingRangeKeys.contains(dayKey)
            let inToday = dayKey == todayKey
            guard inRollingWindow || inToday else { continue }

            for totals in models.values {
                let input = max(0, totals.input)
                let cached = min(max(0, totals.cached), input)
                let output = max(0, totals.output)
                if input > 0 || cached > 0 || output > 0 {
                    sawUsage = true
                }

                if inToday {
                    todayInput += input
                    todayOutput += output
                }
                if inRollingWindow {
                    rollingInput += input
                    rollingOutput += output
                }
            }
        }

        guard sawUsage else { return nil }

        return AccountTokenCostSummary(
            todayCost: rollingCost(usageByDay: merged, includedDayKeys: [todayKey]),
            todayTokens: Int64(todayInput + todayOutput),
            last30DaysCost: rollingCost(usageByDay: merged, includedDayKeys: rollingRangeKeys),
            last30DaysTokens: Int64(rollingInput + rollingOutput),
            currencyCode: "USD"
        )
    }

    private func rollingCost(
        usageByDay: [String: [String: TokenTotals]],
        includedDayKeys: Set<String>
    ) -> Double {
        var total = 0.0
        for (dayKey, models) in usageByDay where includedDayKeys.contains(dayKey) {
            _ = dayKey
            for (model, usage) in models {
                total += LocalCodexPricing.costUSD(
                    model: model,
                    inputTokens: max(0, usage.input),
                    cachedInputTokens: min(max(0, usage.cached), max(0, usage.input)),
                    outputTokens: max(0, usage.output)
                )
            }
        }
        return total
    }

    private func sessionRoots() -> [URL] {
        let sessionsRoot: URL
        if let codexHome = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty {
            sessionsRoot = URL(fileURLWithPath: codexHome, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        } else {
            sessionsRoot = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }

        let archivedRoot = sessionsRoot
            .deletingLastPathComponent()
            .appendingPathComponent("archived_sessions", isDirectory: true)
        return [sessionsRoot, archivedRoot]
    }

    private func listSessionFiles(root: URL, since: Date, until: Date) -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        var files: [URL] = []
        var currentDate = calendar.startOfDay(for: since)
        let endDate = calendar.startOfDay(for: until)

        while currentDate <= endDate {
            let components = calendar.dateComponents([.year, .month, .day], from: currentDate)
            let year = String(format: "%04d", components.year ?? 1970)
            let month = String(format: "%02d", components.month ?? 1)
            let day = String(format: "%02d", components.day ?? 1)

            let dayDirectory = root
                .appendingPathComponent(year, isDirectory: true)
                .appendingPathComponent(month, isDirectory: true)
                .appendingPathComponent(day, isDirectory: true)

            if let items = try? fileManager.contentsOfDirectory(
                at: dayDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                files.append(contentsOf: items.filter { $0.pathExtension.lowercased() == "jsonl" })
            }

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate.addingTimeInterval(1)
        }

        if let rootFiles = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            let flatFiles = rootFiles.filter { url in
                guard url.pathExtension.lowercased() == "jsonl" else { return false }
                guard let fileDayKey = dayKeyFromFilename(url.lastPathComponent) else { return true }
                return fileDayKey >= dayKey(for: since) && fileDayKey <= dayKey(for: until)
            }
            files.append(contentsOf: flatFiles)
        }

        return files.sorted { $0.path < $1.path }
    }

    private func parseFile(_ fileURL: URL) -> ParsedFile? {
        guard let data = try? Data(contentsOf: fileURL),
              let contents = String(data: data, encoding: .utf8) else {
            return nil
        }

        var sessionID: String?
        var currentModel: String?
        var previousTotals: TokenTotals?
        var usageByDay: [String: [String: TokenTotals]] = [:]

        contents.enumerateLines { line, _ in
            guard line.contains("\"type\":\"session_meta\"")
                || line.contains("\"type\":\"turn_context\"")
                || (line.contains("\"type\":\"event_msg\"") && line.contains("\"token_count\""))
            else { return }

            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                return
            }

            if type == "session_meta" {
                if sessionID == nil {
                    let payload = object["payload"] as? [String: Any]
                    sessionID = payload?["session_id"] as? String
                        ?? payload?["sessionId"] as? String
                        ?? payload?["id"] as? String
                        ?? object["session_id"] as? String
                        ?? object["sessionId"] as? String
                        ?? object["id"] as? String
                }
                return
            }

            if type == "turn_context" {
                let payload = object["payload"] as? [String: Any]
                currentModel = payload?["model"] as? String
                    ?? (payload?["info"] as? [String: Any])?["model"] as? String
                    ?? currentModel
                return
            }

            guard type == "event_msg",
                  let timestamp = object["timestamp"] as? String,
                  let dayKey = dayKeyFromTimestamp(timestamp),
                  let payload = object["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count" else {
                return
            }

            let info = payload["info"] as? [String: Any]
            let model = LocalCodexPricing.normalizeModel(
                info?["model"] as? String
                    ?? info?["model_name"] as? String
                    ?? payload["model"] as? String
                    ?? object["model"] as? String
                    ?? currentModel
                    ?? "gpt-5"
            )
            currentModel = model

            let totalUsage = info?["total_token_usage"] as? [String: Any]
            let lastUsage = info?["last_token_usage"] as? [String: Any]

            let input: Int
            let cached: Int
            let output: Int

            if let totalUsage {
                let currentTotals = TokenTotals(
                    input: intValue(totalUsage["input_tokens"]),
                    cached: intValue(totalUsage["cached_input_tokens"] ?? totalUsage["cache_read_input_tokens"]),
                    output: intValue(totalUsage["output_tokens"])
                )
                input = max(0, currentTotals.input - (previousTotals?.input ?? 0))
                cached = max(0, currentTotals.cached - (previousTotals?.cached ?? 0))
                output = max(0, currentTotals.output - (previousTotals?.output ?? 0))
                previousTotals = currentTotals
            } else if let lastUsage {
                input = max(0, intValue(lastUsage["input_tokens"]))
                cached = max(0, intValue(lastUsage["cached_input_tokens"] ?? lastUsage["cache_read_input_tokens"]))
                output = max(0, intValue(lastUsage["output_tokens"]))
            } else {
                return
            }

            if input == 0 && cached == 0 && output == 0 {
                return
            }

            var dayModels = usageByDay[dayKey] ?? [:]
            var totals = dayModels[model] ?? TokenTotals(input: 0, cached: 0, output: 0)
            totals.input += input
            totals.cached += min(cached, input)
            totals.output += output
            dayModels[model] = totals
            usageByDay[dayKey] = dayModels
        }

        guard !usageByDay.isEmpty || sessionID != nil else { return nil }
        return ParsedFile(sessionID: sessionID, usageByDay: usageByDay)
    }

    private func merge(
        _ source: [String: [String: TokenTotals]],
        into target: inout [String: [String: TokenTotals]]
    ) {
        for (dayKey, sourceModels) in source {
            var targetModels = target[dayKey] ?? [:]
            for (model, sourceTotals) in sourceModels {
                var totals = targetModels[model] ?? TokenTotals(input: 0, cached: 0, output: 0)
                totals.input += sourceTotals.input
                totals.cached += sourceTotals.cached
                totals.output += sourceTotals.output
                targetModels[model] = totals
            }
            target[dayKey] = targetModels
        }
    }

    private func dayKeys(since: Date, until: Date) -> Set<String> {
        var result = Set<String>()
        var currentDate = calendar.startOfDay(for: since)
        let endDate = calendar.startOfDay(for: until)

        while currentDate <= endDate {
            result.insert(dayKey(for: currentDate))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate.addingTimeInterval(1)
        }
        return result
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private func dayKeyFromTimestamp(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("T") {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: trimmed) ?? ISO8601DateFormatter().date(from: trimmed) {
                return dayKey(for: date)
            }
        }

        if trimmed.count >= 10 {
            let prefix = String(trimmed.prefix(10))
            if prefix.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                return prefix
            }
        }
        return nil
    }

    private func dayKeyFromFilename(_ value: String) -> String? {
        guard let range = value.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else {
            return nil
        }
        return String(value[range])
    }

    private func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String, let value = Int(string) {
            return value
        }
        return 0
    }
}

private enum LocalCodexPricing {
    private struct Pricing {
        var inputCostPerToken: Double
        var outputCostPerToken: Double
        var cacheReadInputCostPerToken: Double?
    }

    private static let table: [String: Pricing] = [
        "gpt-5": Pricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
        "gpt-5-codex": Pricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
        "gpt-5-mini": Pricing(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadInputCostPerToken: 2.5e-8),
        "gpt-5-nano": Pricing(inputCostPerToken: 5e-8, outputCostPerToken: 4e-7, cacheReadInputCostPerToken: 5e-9),
        "gpt-5-pro": Pricing(inputCostPerToken: 1.5e-5, outputCostPerToken: 1.2e-4, cacheReadInputCostPerToken: nil),
        "gpt-5.1": Pricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
        "gpt-5.1-codex": Pricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
        "gpt-5.1-codex-max": Pricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
        "gpt-5.1-codex-mini": Pricing(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadInputCostPerToken: 2.5e-8),
        "gpt-5.2": Pricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7),
        "gpt-5.2-codex": Pricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7),
        "gpt-5.2-pro": Pricing(inputCostPerToken: 2.1e-5, outputCostPerToken: 1.68e-4, cacheReadInputCostPerToken: nil),
        "gpt-5.3-codex": Pricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7),
        "gpt-5.3-codex-spark": Pricing(inputCostPerToken: 0, outputCostPerToken: 0, cacheReadInputCostPerToken: 0),
        "gpt-5.4": Pricing(inputCostPerToken: 2.5e-6, outputCostPerToken: 1.5e-5, cacheReadInputCostPerToken: 2.5e-7),
        "gpt-5.4-mini": Pricing(inputCostPerToken: 7.5e-7, outputCostPerToken: 4.5e-6, cacheReadInputCostPerToken: 7.5e-8),
        "gpt-5.4-nano": Pricing(inputCostPerToken: 2e-7, outputCostPerToken: 1.25e-6, cacheReadInputCostPerToken: 2e-8),
        "gpt-5.4-pro": Pricing(inputCostPerToken: 3e-5, outputCostPerToken: 1.8e-4, cacheReadInputCostPerToken: nil)
    ]

    static func normalizeModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            trimmed = String(trimmed.dropFirst("openai/".count))
        }
        if table[trimmed] != nil {
            return trimmed
        }
        if let range = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(trimmed[..<range.lowerBound])
            if table[base] != nil {
                return base
            }
        }
        return trimmed
    }

    static func costUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int
    ) -> Double {
        let normalized = normalizeModel(model)
        guard let pricing = table[normalized] else { return 0 }
        let cached = min(max(0, cachedInputTokens), max(0, inputTokens))
        let nonCached = max(0, inputTokens - cached)
        let cachedRate = pricing.cacheReadInputCostPerToken ?? pricing.inputCostPerToken
        return Double(nonCached) * pricing.inputCostPerToken
            + Double(cached) * cachedRate
            + Double(max(0, outputTokens)) * pricing.outputCostPerToken
    }
}
