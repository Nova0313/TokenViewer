import Foundation
import OSLog

enum SharedQuotaStorage {
    static let appGroup = "group.com.qianchen.tokenviewer.shared"
    static let snapshotKey = "quotaSnapshot"
    private static let snapshotFileName = "quota-snapshot.json"
    private static let logger = Logger(
        subsystem: "com.qianchen.tokenviewer",
        category: "SharedQuotaStorage"
    )

    @discardableResult
    static func save(_ providers: [ProviderQuota], at date: Date) -> Bool {
        let previous = load()
        let snapshot = QuotaSnapshot(
            updatedAt: date,
            providers: providers.map { provider in
                let criticalWindow = provider.windows.min {
                    $0.remainingPercent < $1.remainingPercent
                }
                let previousProvider = previous.providers.first { $0.id == provider.id }
                let windows = provider.windows.map { window in
                    let previousWindow = previousProvider?.windows.first { $0.id == window.id }
                    return QuotaSnapshot.Provider.Window(
                        id: window.id,
                        name: window.name,
                        remainingPercent: window.remainingPercent,
                        displayText: window.displayText,
                        displayMode: snapshotDisplayMode(for: window.displayMode),
                        resetAt: window.resetAt,
                        resetDetectedAt: detectedResetDate(
                            previousRemainingPercent: previousWindow?.remainingPercent,
                            existingResetDetectedAt: previousWindow?.resetDetectedAt,
                            remainingPercent: window.remainingPercent,
                            at: date
                        )
                    )
                }
                let resetDetectedAt = detectedResetDate(
                    previousRemainingPercent: previousProvider?.remainingPercent,
                    existingResetDetectedAt: previousProvider?.resetDetectedAt,
                    remainingPercent: provider.lowestRemainingPercent,
                    at: date
                )

                return QuotaSnapshot.Provider(
                    id: provider.id,
                    name: provider.name,
                    symbol: provider.symbol,
                    remainingPercent: provider.lowestRemainingPercent,
                    isAvailable: !provider.windows.isEmpty,
                    periodName: criticalWindow?.name,
                    resetAt: criticalWindow?.resetAt,
                    resetDetectedAt: resetDetectedAt,
                    windows: windows
                )
            }
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        for snapshotFileURL in writableSnapshotFileURLs {
            try? FileManager.default.createDirectory(
                at: snapshotFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: snapshotFileURL, options: .atomic)
        }
        let sharedDefaults = defaults
        sharedDefaults.set(data, forKey: snapshotKey)
        sharedDefaults.synchronize()
        return previous.providers != snapshot.providers
    }

    static func load() -> QuotaSnapshot {
        for snapshotFileURL in readableSnapshotFileURLs {
            do {
                let data = try Data(contentsOf: snapshotFileURL)
                let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
                logger.info("Loaded quota snapshot from \(snapshotFileURL.path, privacy: .public)")
                return snapshot
            } catch {
                logger.debug(
                    "Could not load \(snapshotFileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        let sharedDefaults = defaults
        sharedDefaults.synchronize()
        guard let data = sharedDefaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(QuotaSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private static var writableSnapshotFileURLs: [URL] {
        [appGroupSnapshotFileURL, physicalHomeSnapshotFileURL].compactMap { $0 }
    }

    private static var readableSnapshotFileURLs: [URL] {
        var values = [appGroupSnapshotFileURL, physicalHomeSnapshotFileURL].compactMap { $0 }
        let sandboxHomeURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/TokenViewer")
            .appending(path: snapshotFileName)
        if !values.contains(sandboxHomeURL) {
            values.append(sandboxHomeURL)
        }
        return values
    }

    private static var appGroupSnapshotFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: snapshotFileName)
    }

    private static var physicalHomeSnapshotFileURL: URL? {
        let sandboxHome = FileManager.default.homeDirectoryForCurrentUser
        let components = sandboxHome.pathComponents
        let homeURL: URL?

        if components.count >= 3, components[1] == "Users" {
            homeURL = URL(filePath: "/Users").appending(path: components[2])
        } else if let homePath = NSHomeDirectoryForUser(NSUserName()), !homePath.isEmpty {
            homeURL = URL(filePath: homePath)
        } else {
            homeURL = nil
        }

        return homeURL?
            .appending(path: "Library/Application Support/TokenViewer")
            .appending(path: snapshotFileName)
    }

    private static func detectedResetDate(
        previousRemainingPercent: Double?,
        existingResetDetectedAt: Date?,
        remainingPercent: Double?,
        at date: Date
    ) -> Date? {
        if let previousRemaining = previousRemainingPercent,
           let remainingPercent,
           remainingPercent >= 60,
           remainingPercent - previousRemaining >= 25 {
            return date
        }

        guard let existing = existingResetDetectedAt,
              date.timeIntervalSince(existing) < 10 * 60 else {
            return nil
        }
        return existing
    }

    private static func snapshotDisplayMode(for mode: QuotaWindow.DisplayMode) -> QuotaSnapshot.Provider.WindowDisplayMode {
        switch mode {
        case .percent: return .percent
        case .balance: return .balance
        }
    }
}

struct QuotaSnapshot: Codable, Equatable, Sendable {
    struct Provider: Codable, Equatable, Identifiable, Sendable {
        enum WindowDisplayMode: String, Codable, Equatable, Sendable {
            case percent
            case balance
        }

        struct Window: Codable, Equatable, Identifiable, Sendable {
            let id: String
            let name: String
            let remainingPercent: Double?
            let displayText: String?
            let displayMode: WindowDisplayMode?
            let resetAt: Date?
            let resetDetectedAt: Date?

            enum CodingKeys: String, CodingKey {
                case id
                case name
                case remainingPercent
                case displayText
                case displayMode
                case resetAt
                case resetDetectedAt
            }

            init(
                id: String,
                name: String,
                remainingPercent: Double?,
                displayText: String? = nil,
                displayMode: WindowDisplayMode? = nil,
                resetAt: Date?,
                resetDetectedAt: Date?
            ) {
                self.id = id
                self.name = name
                self.remainingPercent = remainingPercent
                self.displayText = displayText
                self.displayMode = displayMode
                self.resetAt = resetAt
                self.resetDetectedAt = resetDetectedAt
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                name = try container.decode(String.self, forKey: .name)
                remainingPercent = try container.decodeIfPresent(Double.self, forKey: .remainingPercent)
                displayText = try container.decodeIfPresent(String.self, forKey: .displayText)
                displayMode = try container.decodeIfPresent(WindowDisplayMode.self, forKey: .displayMode)
                resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
                resetDetectedAt = try container.decodeIfPresent(Date.self, forKey: .resetDetectedAt)
            }

            func petMood(at date: Date) -> QuotaPetMood {
                guard let remainingPercent else { return .disconnected }
                if let resetDetectedAt,
                   date.timeIntervalSince(resetDetectedAt) >= 0,
                   date.timeIntervalSince(resetDetectedAt) < 10 * 60 {
                    return .revived
                }
                if remainingPercent <= 10 { return .exhausted }
                if remainingPercent < 35 { return .tired }
                if remainingPercent < 70 { return .focused }
                return .relaxed
            }
        }

        let id: String
        let name: String
        let symbol: String
        let remainingPercent: Double?
        let isAvailable: Bool
        let periodName: String?
        let resetAt: Date?
        let resetDetectedAt: Date?
        let windows: [Window]

        init(
            id: String,
            name: String,
            symbol: String,
            remainingPercent: Double?,
            isAvailable: Bool,
            periodName: String?,
            resetAt: Date?,
            resetDetectedAt: Date?,
            windows: [Window] = []
        ) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.remainingPercent = remainingPercent
            self.isAvailable = isAvailable
            self.periodName = periodName
            self.resetAt = resetAt
            self.resetDetectedAt = resetDetectedAt
            self.windows = windows
        }

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case symbol
            case remainingPercent
            case isAvailable
            case periodName
            case resetAt
            case resetDetectedAt
            case windows
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            symbol = try container.decode(String.self, forKey: .symbol)
            remainingPercent = try container.decodeIfPresent(Double.self, forKey: .remainingPercent)
            isAvailable = try container.decode(Bool.self, forKey: .isAvailable)
            periodName = try container.decodeIfPresent(String.self, forKey: .periodName)
            resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
            resetDetectedAt = try container.decodeIfPresent(Date.self, forKey: .resetDetectedAt)
            windows = try container.decodeIfPresent([Window].self, forKey: .windows) ?? []
        }

        func petMood(at date: Date) -> QuotaPetMood {
            guard isAvailable, let remainingPercent else { return .disconnected }
            if let resetDetectedAt,
               date.timeIntervalSince(resetDetectedAt) >= 0,
               date.timeIntervalSince(resetDetectedAt) < 10 * 60 {
                return .revived
            }
            if remainingPercent <= 10 { return .exhausted }
            if remainingPercent < 35 { return .tired }
            if remainingPercent < 70 { return .focused }
            return .relaxed
        }

        func window(id windowID: String) -> Window? {
            windows.first { $0.id == windowID }
        }
    }

    let updatedAt: Date
    let providers: [Provider]

    static let placeholder = QuotaSnapshot(
        updatedAt: .now,
        providers: [
            Provider(
                id: "claude",
                name: "Claude",
                symbol: "sparkles",
                remainingPercent: 72,
                isAvailable: true,
                periodName: "当前窗口",
                resetAt: .now.addingTimeInterval(2 * 60 * 60),
                resetDetectedAt: nil
            ),
            Provider(
                id: "codex",
                name: "Codex",
                symbol: "terminal",
                remainingPercent: 96,
                isAvailable: true,
                periodName: "5 小时",
                resetAt: .now.addingTimeInterval(4 * 60 * 60),
                resetDetectedAt: nil
            )
        ]
    )

    static let empty = QuotaSnapshot(
        updatedAt: .now,
        providers: []
    )
}

enum QuotaPetMood: String, Codable, Equatable, Sendable {
    case disconnected
    case revived
    case relaxed
    case focused
    case tired
    case exhausted

    var statusText: String {
        switch self {
        case .disconnected: "等待投喂数据"
        case .revived: "满血复活！"
        case .relaxed: "额度充足，悠闲中"
        case .focused: "状态不错，认真工作"
        case .tired: "额度不多，有点累了"
        case .exhausted: "快没电了，需要休息"
        }
    }
}
