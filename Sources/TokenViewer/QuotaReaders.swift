import Foundation

protocol QuotaReading: Sendable {
    func read() async -> ProviderQuota
}

extension LocalProvider {
    func makeReader(homeDirectory: URL) -> any QuotaReading {
        switch self {
        case .claude:
            ClaudeQuotaReader(homeDirectory: homeDirectory)
        case .codex:
            CodexQuotaReader(homeDirectory: homeDirectory)
        }
    }
}

struct CodexQuotaReader: QuotaReading {
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser

    func read() async -> ProviderQuota {
        let sessions = homeDirectory.appending(path: ".codex/sessions")
        guard let record = JSONLQuotaScanner.latestQuotaRecord(in: sessions) else {
            return ProviderQuota(
                id: "codex",
                name: "Codex",
                symbol: "terminal",
                windows: [],
                state: .unavailable("尚未找到 Codex 额度记录"),
                updatedAt: nil
            )
        }

        let windows = [
            record.window(key: "primary", fallbackName: "5 小时"),
            record.window(key: "secondary", fallbackName: "7 天")
        ].compactMap { $0 }

        return ProviderQuota(
            id: "codex",
            name: "Codex",
            symbol: "terminal",
            windows: windows,
            state: windows.isEmpty ? .unavailable("额度记录格式暂不支持") : .available,
            updatedAt: record.timestamp
        )
    }
}

struct ClaudeQuotaReader: QuotaReading {
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser

    func read() async -> ProviderQuota {
        let claudeDirectory = homeDirectory.appending(path: ".claude")
        guard let record = JSONLQuotaScanner.latestQuotaRecord(in: claudeDirectory) else {
            return ProviderQuota(
                id: "claude",
                name: "Claude",
                symbol: "sparkles",
                windows: [],
                state: .unavailable("Claude 本地日志未提供额度数据"),
                updatedAt: nil
            )
        }

        let windows = [
            record.window(key: "primary", fallbackName: "当前窗口"),
            record.window(key: "secondary", fallbackName: "每周")
        ].compactMap { $0 }

        return ProviderQuota(
            id: "claude",
            name: "Claude",
            symbol: "sparkles",
            windows: windows,
            state: windows.isEmpty ? .unavailable("Claude 本地日志未提供额度数据") : .available,
            updatedAt: record.timestamp
        )
    }
}

struct QuotaRecord {
    let timestamp: Date?
    let rateLimits: [String: Any]

    func window(key: String, fallbackName: String) -> QuotaWindow? {
        guard let value = rateLimits[key] as? [String: Any],
              let usedPercent = Self.number(value["used_percent"] ?? value["usedPercent"]) else {
            return nil
        }

        let resetSeconds = Self.number(value["resets_at"] ?? value["reset_at"] ?? value["resetsAt"])
        let resetAt = resetSeconds.map { Date(timeIntervalSince1970: $0) }
        let minutes = Self.number(value["window_minutes"] ?? value["windowMinutes"])
        let name = Self.windowName(minutes: minutes) ?? fallbackName

        return QuotaWindow(
            id: key,
            name: name,
            usedPercent: usedPercent,
            resetAt: resetAt
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func windowName(minutes: Double?) -> String? {
        guard let minutes else { return nil }
        if minutes == 300 { return "5 小时" }
        if minutes == 10_080 { return "7 天" }
        if minutes >= 1_440, minutes.truncatingRemainder(dividingBy: 1_440) == 0 {
            return "\(Int(minutes / 1_440)) 天"
        }
        if minutes >= 60, minutes.truncatingRemainder(dividingBy: 60) == 0 {
            return "\(Int(minutes / 60)) 小时"
        }
        return "\(Int(minutes)) 分钟"
    }
}

enum JSONLQuotaScanner {
    static func latestQuotaRecord(in directory: URL) -> QuotaRecord? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let files = enumerator.compactMap { item -> (URL, Date)? in
            guard let url = item as? URL,
                  url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(20)

        for (file, _) in files {
            if let record = latestQuotaRecord(inFile: file) {
                return record
            }
        }
        return nil
    }

    static func latestQuotaRecord(inFile file: URL) -> QuotaRecord? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let readSize = min(size, 1_048_576)
        try? handle.seek(toOffset: size - readSize)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in text.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any],
                  let limits = findRateLimits(in: dictionary) else {
                continue
            }
            return QuotaRecord(
                timestamp: parseDate(dictionary["timestamp"]),
                rateLimits: limits
            )
        }
        return nil
    }

    private static func findRateLimits(in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            for key in ["rate_limits", "rateLimits", "usage_limits", "usageLimits"] {
                if let limits = dictionary[key] as? [String: Any] {
                    return limits
                }
            }
            for child in dictionary.values {
                if let result = findRateLimits(in: child) { return result }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let result = findRateLimits(in: child) { return result }
            }
        }
        return nil
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
}
