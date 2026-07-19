import Foundation

protocol QuotaReading: Sendable {
    func read() async -> ProviderQuota
}

extension LocalProvider {
    func makeReader(homeDirectory: URL, customDataPath: String? = nil) -> any QuotaReading {
        switch self {
        case .claude:
            ClaudeQuotaReader(homeDirectory: homeDirectory, customDataPath: customDataPath)
        case .codex:
            CodexQuotaReader(homeDirectory: homeDirectory, customDataPath: customDataPath)
        }
    }
}

struct CodexQuotaReader: QuotaReading {
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var customDataPath: String?

    func read() async -> ProviderQuota {
        // 优先使用自定义路径，否则使用默认路径
        let sessions: URL
        if let customPath = customDataPath, !customPath.isEmpty {
            sessions = URL(filePath: customPath).appending(path: "sessions")
        } else {
            sessions = homeDirectory.appending(path: ".codex/sessions")
        }
        
        guard let record = JSONLQuotaScanner.latestQuotaRecord(in: sessions) else {
            return ProviderQuota(
                id: "codex",
                name: "Codex",
                symbol: "terminal",
                windows: [],
                state: .unavailable("尚未找到 Codex 额度记录"),
                updatedAt: nil,
                source: .local
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
            updatedAt: record.timestamp,
            source: .local
        )
    }
}

struct ClaudeQuotaReader: QuotaReading {
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var customDataPath: String?

    func read() async -> ProviderQuota {
        // 优先使用自定义路径，否则使用默认路径
        let claudeDirectory: URL
        if let customPath = customDataPath, !customPath.isEmpty {
            claudeDirectory = URL(filePath: customPath)
        } else {
            claudeDirectory = homeDirectory.appending(path: ".claude")
        }
        
        guard let record = JSONLQuotaScanner.latestQuotaRecord(in: claudeDirectory) else {
            return ProviderQuota(
                id: "claude",
                name: "Claude",
                symbol: "sparkles",
                windows: [],
                state: .unavailable("Claude 本地日志未提供额度数据"),
                updatedAt: nil,
                source: .local
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
            updatedAt: record.timestamp,
            source: .local
        )
    }
}

struct APIQuotaReader: QuotaReading {
    let config: APIProviderConfig
    let apiKey: String?
    let homeDirectory: URL

    init(config: APIProviderConfig, apiKey: String?, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.config = config
        self.apiKey = apiKey
        self.homeDirectory = homeDirectory
    }

    func read() async -> ProviderQuota {
        guard let apiKey, !apiKey.isEmpty else {
            return unavailable(message: "未配置 API Key，请在 Keychain 中检查存储状态")
        }

        // 自动识别模式：依次尝试已知厂商的额度接口，命中即返回
        if config.template == .auto {
            return await readAutoDetect(apiKey: apiKey)
        }

        // 内置模板忽略用户在 UI 上可能残留的 Base URL/Path，始终使用模板预设值
        // 参考 CC Switch：内置预设的端点是不可变的，避免 /anthropic、/v1 之类的子路径污染额度查询
        let effectiveBaseURL: URL
        let effectivePath: String
        let effectiveFormat: APIFormat
        if config.template.isBuiltin {
            guard let url = URL(string: config.template.defaultBaseURL) else {
                return unavailable(message: "模板 Base URL 无效：\(config.template.defaultBaseURL)")
            }
            effectiveBaseURL = url
            effectivePath = config.template.defaultQuotaPath
            effectiveFormat = config.template.defaultFormat
        } else {
            effectiveBaseURL = config.baseURL
            effectivePath = config.quotaPath
            effectiveFormat = config.format
        }

        return await fetchSingle(
            baseURL: effectiveBaseURL,
            path: effectivePath,
            format: effectiveFormat,
            apiKey: apiKey,
            template: config.template
        )
    }

    /// 自动识别：根据用户填写的官网 URL 优先匹配厂商，匹配不到则依次尝试已知厂商
    private func readAutoDetect(apiKey: String) async -> ProviderQuota {
        // 如果用户填了官网 URL 且能匹配到已知厂商，优先只尝试该厂商（更快、更精准）
        let userURL: URL? = {
            // auto 模板保存时若用户没填 URL，会用占位 https://auto.local
            let url = config.baseURL
            guard let host = url.host?.lowercased(), host != "auto.local" else { return nil }
            return url
        }()

        // 1. 优先匹配用户填写的 URL
        if let userURL, let matched = AutoDetectVendor.allCases.first(where: { $0.matches(url: userURL) }) {
            let result = await fetchVendor(vendor: matched, apiKey: apiKey)
            if case .available = result.state {
                return result
            }
            // 用户填的 URL 没识别成功，给出明确错误，不再 fallback 浪费请求
            if case .unavailable(let message) = result.state {
                return unavailable(message: "已按官网（\(userURL.host ?? "")）识别为 \(matched.displayName)，但查询失败：\(message)")
            }
        }

        // 2. 用户没填 URL 或 URL 未命中已知厂商：依次尝试所有已知厂商
        var lastError: String = "未匹配到任何已知供应商"
        for vendor in AutoDetectVendor.allCases {
            let result = await fetchVendor(vendor: vendor, apiKey: apiKey)
            if case .available = result.state {
                return result
            }
            if case .unavailable(let message) = result.state {
                lastError = "\(vendor.displayName)：\(message)"
            }
        }
        return unavailable(message: "自动识别失败，已尝试已知供应商均未命中。最后错误：\(lastError)")
    }

    /// 请求某个自动识别厂商的额度接口并用其专用解析器处理响应
    private func fetchVendor(vendor: AutoDetectVendor, apiKey: String) async -> ProviderQuota {
        guard let url = endpointURL(base: vendor.baseURL, path: vendor.path) else {
            return unavailable(message: "\(vendor.displayName) URL 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return unavailable(message: "\(vendor.displayName)：服务器返回了无效响应")
            }
            guard (200..<300).contains(http.statusCode) else {
                let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
                let snippetPart = snippet.isEmpty ? "" : "：\(snippet)"
                return unavailable(message: "\(vendor.displayName)：HTTP \(http.statusCode)（\(url.absoluteString)）\(snippetPart)")
            }

            guard let object = try? JSONSerialization.jsonObject(with: data) else {
                let snippet = String(data: data.prefix(200), encoding: .utf8) ?? "<空响应>"
                return unavailable(message: "\(vendor.displayName)：响应不是合法的 JSON（\(url.absoluteString)）：\(snippet)")
            }

            let windows = vendor.parse(object: object)
            guard !windows.isEmpty else {
                let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
                let snippetPart = snippet.isEmpty ? "" : "：\(snippet)"
                return unavailable(message: "\(vendor.displayName)：响应未包含可识别的额度字段\(snippetPart)")
            }

            return ProviderQuota(
                id: config.quotaID,
                name: config.name,
                symbol: vendor.symbol,
                windows: windows,
                state: .available,
                updatedAt: Date(),
                source: .api,
                vendorName: vendor.displayName
            )
        } catch {
            return unavailable(message: "\(vendor.displayName)：请求失败（\(url.absoluteString)）：\(error.localizedDescription)")
        }
    }

    /// 单次请求 + 解析（用于非 auto 模板）
    private func fetchSingle(
        baseURL: URL,
        path: String,
        format: APIFormat,
        apiKey: String,
        template: APIProviderTemplate
    ) async -> ProviderQuota {
        guard let url = endpointURL(base: baseURL, path: path) else {
            return unavailable(message: "Base URL 或额度路径无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        switch format {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAI:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return unavailable(message: "服务器返回了无效响应")
            }
            guard (200..<300).contains(http.statusCode) else {
                let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
                let snippetPart = snippet.isEmpty ? "" : "：\(snippet)"
                return unavailable(message: "HTTP \(http.statusCode)（\(url.absoluteString)）\(snippetPart)")
            }

            guard let object = try? JSONSerialization.jsonObject(with: data) else {
                let snippet = String(data: data.prefix(200), encoding: .utf8) ?? "<空响应>"
                return unavailable(message: "响应不是合法的 JSON（\(url.absoluteString)）：\(snippet)")
            }

            let windows = windows(for: template, from: object)
            guard !windows.isEmpty else {
                let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
                let snippetPart = snippet.isEmpty ? "" : "：\(snippet)"
                return unavailable(message: "响应未包含可识别的额度字段\(snippetPart)")
            }

            return ProviderQuota(
                id: config.quotaID,
                name: config.name,
                symbol: template.symbol,
                windows: windows,
                state: .available,
                updatedAt: Date(),
                source: .api
            )
        } catch {
            return unavailable(message: "请求失败（\(url.absoluteString)）：\(error.localizedDescription)")
        }
    }

    /// 根据模板选择不同的响应解析逻辑
    /// 注意：自动识别模式（auto）不会走到这里，它在 readAutoDetect 中已分发给具体厂商解析器
    private func windows(for template: APIProviderTemplate, from object: Any) -> [QuotaWindow] {
        switch template {
        case .custom, .generic, .newAPI, .auto:
            return percentWindows(from: object)
        }
    }

    /// 百分比模式解析（适用于 rate_limits / usage_limits 结构）
    private func percentWindows(from object: Any) -> [QuotaWindow] {
        guard let limits = QuotaLimitsFinder.find(in: object) else { return [] }
        let record = QuotaRecord(timestamp: Date(), rateLimits: limits)
        return [
            record.window(key: "primary", fallbackName: "当前周期"),
            record.window(key: "secondary", fallbackName: "长期周期")
        ].compactMap { $0 }
    }

    private func endpointURL(base: URL, path: String) -> URL? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return base }
        let pathComponent = trimmedPath.hasPrefix("/") ? trimmedPath : "/" + trimmedPath

        var baseString = base.absoluteString
        // 避免出现 //path 之类的双斜杠
        if baseString.hasSuffix("/"), pathComponent.hasPrefix("/") {
            baseString.removeLast()
        }
        return URL(string: baseString + pathComponent)
    }

    private func unavailable(message: String) -> ProviderQuota {
        ProviderQuota(
            id: config.quotaID,
            name: config.name,
            symbol: config.template.symbol,
            windows: [],
            state: .unavailable(message),
            updatedAt: nil,
            source: .api
        )
    }
}

/// 读取本机 CLI 的 OAuth 凭据（默认关闭，仅在用户启用时调用）
enum LocalOAuthReader {
    static func readToken(homeDirectory: URL) -> String? {
        let candidates: [URL] = [
            homeDirectory.appending(path: ".claude/.credentials.json"),
            homeDirectory.appending(path: ".claude/credentials.json"),
            homeDirectory.appending(path: ".codex/auth.json")
        ]
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let token = object["accessToken"] as? String, !token.isEmpty {
                return token
            }
            if let token = object["access_token"] as? String, !token.isEmpty {
                return token
            }
            if let token = object["token"] as? String, !token.isEmpty {
                return token
            }
        }
        return nil
    }
}

enum QuotaLimitsFinder {
    static func find(in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            for key in ["rate_limits", "rateLimits", "usage_limits", "usageLimits"] {
                if let limits = dictionary[key] as? [String: Any] {
                    return limits
                }
            }
            for child in dictionary.values {
                if let result = find(in: child) { return result }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let result = find(in: child) { return result }
            }
        }
        return nil
    }
}

/// 自动识别模式下依次尝试的已知厂商列表
/// 每个厂商有自己的额度接口端点、图标和响应解析器
enum AutoDetectVendor: String, CaseIterable, Sendable {
    case deepseek
    case zhipu
    case minimax

    var displayName: String {
        switch self {
        case .deepseek: "DeepSeek"
        case .zhipu: "智谱 AI"
        case .minimax: "MiniMax"
        }
    }

    var symbol: String {
        switch self {
        case .deepseek: "waveform.path.ecg"
        case .zhipu: "brain.head.profile"
        case .minimax: "cube.fill"
        }
    }

    var baseURL: URL {
        switch self {
        case .deepseek: URL(string: "https://api.deepseek.com")!
        case .zhipu: URL(string: "https://open.bigmodel.cn")!
        case .minimax: URL(string: "https://api.minimax.chat")!
        }
    }

    var path: String {
        switch self {
        case .deepseek: "/user/balance"
        case .zhipu: "/paas/v4/usage"
        case .minimax: "/v1/balance"
        }
    }

    /// 厂商官网域名（用于和用户填写的 URL 做 host 匹配）
    var officialHost: String {
        switch self {
        case .deepseek: "deepseek.com"
        case .zhipu: "bigmodel.cn"
        case .minimax: "minimax.chat"
        }
    }

    /// 判断用户填写的 URL 是否指向该厂商（host 后缀匹配，支持 api.deepseek.com / platform.deepseek.com 等子域）
    func matches(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == officialHost || host.hasSuffix("." + officialHost)
    }

    /// 用厂商专属解析器从响应对象中提取额度窗口
    func parse(object: Any) -> [QuotaWindow] {
        switch self {
        case .deepseek:
            return DeepSeekBalanceParser.parse(object: object)
        case .zhipu:
            // 智谱目前与通用 percent 模式一致；如官方推出余额接口可在此扩展
            return AutoDetectVendor.percentWindows(from: object)
        case .minimax:
            return MiniMaxBalanceParser.parse(object: object)
        }
    }

    /// 百分比模式解析（适用于 rate_limits / usage_limits 结构）
    private static func percentWindows(from object: Any) -> [QuotaWindow] {
        guard let limits = QuotaLimitsFinder.find(in: object) else { return [] }
        let record = QuotaRecord(timestamp: Date(), rateLimits: limits)
        return [
            record.window(key: "primary", fallbackName: "短周期（5小时窗口）"),
            record.window(key: "secondary", fallbackName: "长周期（7天窗口）")
        ].compactMap { $0 }
    }
}

/// DeepSeek `/user/balance` 响应解析器
/// 响应示例：
/// ```
/// {
///   "is_available": true,
///   "balance_infos": [
///     { "currency": "CNY", "total_balance": "9.99", "granted_balance": "0.00", "topped_up_balance": "9.99" }
///   ]
/// }
/// ```
/// 字段说明：
/// - total_balance: 总余额（账户当前可用的总金额，包含赠送和充值）
/// - granted_balance: 赠送额度（平台赠送的免费额度，不可提现，通常有有效期）
/// - topped_up_balance: 充值余额（用户实际充值的金额）
/// 关系：total_balance = granted_balance + topped_up_balance
enum DeepSeekBalanceParser {
    static func parse(object: Any) -> [QuotaWindow] {
        guard let dict = object as? [String: Any] else { return [] }
        let isAvailable = dict["is_available"] as? Bool ?? true
        guard let infos = dict["balance_infos"] as? [[String: Any]], !infos.isEmpty else {
            return []
        }

        var windows: [QuotaWindow] = []
        for (index, info) in infos.enumerated() {
            let currency = (info["currency"] as? String) ?? "CNY"
            let total = stringValue(info["total_balance"])
            let granted = stringValue(info["granted_balance"])
            let toppedUp = stringValue(info["topped_up_balance"])
            guard let total else { continue }

            let symbol = currencySymbol(for: currency)
            let window = QuotaWindow(
                id: "balance_\(index)",
                name: windowName(index: index, total: infos.count, currency: currency),
                usedPercent: isAvailable ? 0 : 100,
                resetAt: nil,
                displayText: "\(symbol)\(total)",
                displayMode: .balance
            )
            windows.append(window)

            // 把赠送 / 充值明细作为附加窗口（仅在非零时显示）
            if let granted, let grantedValue = Double(granted), grantedValue > 0 {
                windows.append(QuotaWindow(
                    id: "granted_\(index)",
                    name: "赠送额度（免费）",
                    usedPercent: 0,
                    resetAt: nil,
                    displayText: "\(symbol)\(granted)",
                    displayMode: .balance
                ))
            }
            if let toppedUp, let toppedUpValue = Double(toppedUp), toppedUpValue > 0 {
                windows.append(QuotaWindow(
                    id: "topped_\(index)",
                    name: "充值余额（付费）",
                    usedPercent: 0,
                    resetAt: nil,
                    displayText: "\(symbol)\(toppedUp)",
                    displayMode: .balance
                ))
            }
        }
        return windows
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func currencySymbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "CNY": return "¥"
        case "USD": return "$"
        default: return ""
        }
    }

    private static func windowName(index: Int, total: Int, currency: String) -> String {
        // 单币种：直接显示"总余额（可用）"
        // 多币种：显示"总余额（CNY）（可用）"以区分币种
        if total == 1 { return "总余额（可用）" }
        return "总余额（\(currency.uppercased())）（可用）"
    }
}

/// MiniMax `/v1/balance` 响应解析器
/// 响应示例：
/// ```
/// {
///   "balance": 1000.50,
///   "credit_balance": 200.00,
///   "cash_balance": 800.50
/// }
/// ```
/// 字段说明：
/// - balance: 总余额（账户当前可用的总金额，包含赠送和充值）
/// - credit_balance: 赠送额度（平台赠送的免费额度，不可提现）
/// - cash_balance: 充值余额（用户实际充值的金额）
/// 关系：balance = credit_balance + cash_balance
enum MiniMaxBalanceParser {
    static func parse(object: Any) -> [QuotaWindow] {
        guard let dict = object as? [String: Any] else { return [] }

        var windows: [QuotaWindow] = []

        // 解析总余额
        if let balance = numericValue(dict["balance"]) {
            windows.append(QuotaWindow(
                id: "balance_total",
                name: "总余额（可用）",
                usedPercent: 0,
                resetAt: nil,
                displayText: "¥\(String(format: "%.2f", balance))",
                displayMode: .balance
            ))

            // 解析赠送额度
            if let credit = numericValue(dict["credit_balance"]), credit > 0 {
                windows.append(QuotaWindow(
                    id: "balance_credit",
                    name: "赠送额度（免费）",
                    usedPercent: 0,
                    resetAt: nil,
                    displayText: "¥\(String(format: "%.2f", credit))",
                    displayMode: .balance
                ))
            }

            // 解析充值余额
            if let cash = numericValue(dict["cash_balance"]), cash > 0 {
                windows.append(QuotaWindow(
                    id: "balance_cash",
                    name: "充值余额（付费）",
                    usedPercent: 0,
                    resetAt: nil,
                    displayText: "¥\(String(format: "%.2f", cash))",
                    displayMode: .balance
                ))
            }
        }

        return windows
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        if let double = value as? Double { return double }
        return nil
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
                  let limits = QuotaLimitsFinder.find(in: dictionary) else {
                continue
            }
            return QuotaRecord(
                timestamp: parseDate(dictionary["timestamp"]),
                rateLimits: limits
            )
        }
        return nil
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
}
