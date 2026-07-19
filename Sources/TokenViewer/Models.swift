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
    /// 用户手动指定的数据目录路径（如果自动检测失败）
    var customDataPath: String?

    var id: String { provider.id }
}

struct LocalProviderCandidate: Identifiable, Equatable, Sendable {
    let provider: LocalProvider
    let isDetected: Bool
    let detectionDetail: String

    var id: String { provider.id }
}

struct QuotaWindow: Identifiable, Equatable, Sendable {
    /// 显示模式：百分比（默认）或余额文本
    enum DisplayMode: Equatable, Sendable {
        case percent
        case balance
    }

    let id: String
    let name: String
    let usedPercent: Double
    let resetAt: Date?
    /// 余额模式下的展示文本（如 "¥9.99"）；为 nil 时按百分比模式展示
    let displayText: String?
    let displayMode: DisplayMode

    init(
        id: String,
        name: String,
        usedPercent: Double,
        resetAt: Date? = nil,
        displayText: String? = nil,
        displayMode: DisplayMode = .percent
    ) {
        self.id = id
        self.name = name
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.displayText = displayText
        self.displayMode = displayMode
    }

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct ProviderQuota: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case available
        case unavailable(String)
    }

    enum Source: Equatable, Sendable {
        case local
        case api
    }

    let id: String
    let name: String
    let symbol: String
    let windows: [QuotaWindow]
    let state: State
    let updatedAt: Date?
    let source: Source
    /// 自动识别模式下命中到的厂商名（如 "DeepSeek"）；其他模式为 nil
    let vendorName: String?

    var lowestRemainingPercent: Double? {
        windows.map(\.remainingPercent).min()
    }

    init(
        id: String,
        name: String,
        symbol: String,
        windows: [QuotaWindow],
        state: State,
        updatedAt: Date?,
        source: Source = .local,
        vendorName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.windows = windows
        self.state = state
        self.updatedAt = updatedAt
        self.source = source
        self.vendorName = vendorName
    }
}

enum APIFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic 原生"
        case .openAI: "OpenAI 兼容"
        }
    }

    var symbol: String {
        switch self {
        case .anthropic: "sparkles"
        case .openAI: "network"
        }
    }

    var shortDescription: String {
        switch self {
        case .anthropic: "x-api-key 鉴权，适合 Claude API 中转"
        case .openAI: "Bearer 鉴权，适合 OpenAI 兼容接口"
        }
    }
}

/// API 配置预设模板（参考 CC Switch 设计）
enum APIProviderTemplate: String, CaseIterable, Identifiable, Sendable {
    case custom
    case generic
    case newAPI
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .custom: "自定义"
        case .generic: "通用模板"
        case .newAPI: "NewAPI"
        case .auto: "自动识别"
        }
    }

    var symbol: String {
        switch self {
        case .custom: "slider.horizontal.3"
        case .generic: "globe"
        case .newAPI: "server.rack"
        case .auto: "wand.and.stars"
        }
    }

    var description: String {
        switch self {
        case .custom: "完全自定义 URL、Key、协议格式与额度接口路径"
        case .generic: "适用于大多数 OpenAI 兼容中转服务"
        case .newAPI: "适配 NewAPI / One-API 风格的中转后台"
        case .auto: "自动使用供应商的 API Key 查询账户余额（依次尝试 DeepSeek、智谱等已知厂商接口）"
        }
    }

    /// 模板默认 Base URL（custom/generic/newapi 为空，需用户填写；auto 不使用单一 Base URL）
    var defaultBaseURL: String {
        switch self {
        case .custom: ""
        case .generic: ""
        case .newAPI: ""
        case .auto: ""
        }
    }

    var defaultQuotaPath: String {
        switch self {
        case .custom: "/v1/usage"
        case .generic: "/v1/usage"
        case .newAPI: "/api/user/self"
        case .auto: ""
        }
    }

    var defaultFormat: APIFormat {
        switch self {
        case .generic, .newAPI, .auto, .custom: .openAI
        }
    }

    /// 是否为内置模板：内置模板的 Base URL、路径、协议均被锁定，参考 CC Switch 的预设设计
    /// 内置模板仅允许用户填写 API Key，避免误填 /anthropic、/v1 之类的子路径导致额度接口 404
    var isBuiltin: Bool {
        switch self {
        case .auto: true
        case .custom, .generic, .newAPI: false
        }
    }

    /// 是否在 UI 中展示提取器说明（即响应格式约定）
    /// 自定义 / 通用 / NewAPI 由用户自行接入 API，需要明确告诉它响应字段如何被解析
    var showsExtractorDescription: Bool {
        switch self {
        case .custom, .generic, .newAPI: true
        case .auto: false
        }
    }

    /// 提取器说明：展示当前模板期望的响应结构与字段路径，便于用户对照供应商文档
    var extractorDescription: String {
        switch self {
        case .custom, .generic:
            return """
            期望响应结构（百分比模式）：
            {
              "rate_limits": {
                "primary": {
                  "used_percent": 45.2,        // 0-100，本周期已用百分比
                  "resets_at": 1717200000,     // Unix 时间戳，重置时间
                  "window_minutes": 300         // 窗口长度（5 小时 / 7 天等）
                },
                "secondary": { ... }
              }
            }

            字段名兼容：rate_limits / rateLimits / usage_limits / usageLimits
            字段名兼容：used_percent / usedPercent
            字段名兼容：resets_at / reset_at / resetsAt
            字段名兼容：window_minutes / windowMinutes

            缺失字段会被忽略；至少需要返回 used_percent。
            """
        case .newAPI:
            return """
            NewAPI / One-API 风格响应（百分比模式）：
            调用 GET /api/user/self 返回当前用户信息，本应用从以下字段提取：
            - rate_limits.primary.used_percent   （0-100，已用百分比）
            - rate_limits.primary.resets_at       （Unix 时间戳）
            - rate_limits.primary.window_minutes  （窗口长度）

            若您的 NewAPI 后台返回结构不同，请改用「自定义」模板并填写正确的额度接口路径，
            或在中转后台中开启 /api/user/self 返回 rate_limits 字段的扩展。
            """
        case .auto:
            return ""
        }
    }

    var suggestedName: String {
        switch self {
        case .custom: "自定义 API"
        case .generic: "通用 API"
        case .newAPI: "NewAPI"
        case .auto: "自动识别"
        }
    }
}

extension APIProviderTemplate: Codable {
    /// 自定义解码：把已废弃的 zhipu / deepseek / tokenPlan / official 统一迁移到 .auto
    /// 这样旧版本的配置文件在新版本中仍可正常加载
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "custom", "generic", "newAPI", "auto":
            self = APIProviderTemplate(rawValue: raw) ?? .auto
        // 已废弃的模板，统一迁移到自动识别
        case "zhipu", "deepseek", "tokenPlan", "official":
            self = .auto
        default:
            self = .auto
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct APIProviderConfig: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var baseURL: URL
    var apiKeyID: String
    var format: APIFormat
    var quotaPath: String
    var template: APIProviderTemplate
    var useLocalOAuth: Bool
    var showInWidget: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        apiKeyID: String,
        format: APIFormat,
        quotaPath: String = "/v1/usage",
        template: APIProviderTemplate = .custom,
        useLocalOAuth: Bool = false,
        showInWidget: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKeyID = apiKeyID
        self.format = format
        self.quotaPath = quotaPath
        self.template = template
        self.useLocalOAuth = useLocalOAuth
        self.showInWidget = showInWidget
        self.sortOrder = sortOrder
    }

    var quotaID: String { "api.\(id.uuidString)" }
}
