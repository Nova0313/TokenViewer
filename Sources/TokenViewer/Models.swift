import Foundation

enum LocalProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "terminal"
        }
    }

}

struct ProviderBinding: Codable, Equatable, Identifiable, Sendable {
    let provider: LocalProvider
    var showInWidget: Bool
    var sortOrder: Int

    var id: String { provider.id }
}

struct LocalProviderCandidate: Identifiable, Equatable, Sendable {
    let provider: LocalProvider
    let isDetected: Bool
    let detectionDetail: String

    var id: String { provider.id }
}

struct QuotaWindow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let usedPercent: Double
    let resetAt: Date?

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct ProviderQuota: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case available
        case unavailable(String)
    }

    let id: String
    let name: String
    let symbol: String
    let windows: [QuotaWindow]
    let state: State
    let updatedAt: Date?

    var lowestRemainingPercent: Double? {
        windows.map(\.remainingPercent).min()
    }
}
