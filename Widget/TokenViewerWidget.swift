import AppIntents
import SwiftUI
import WidgetKit

struct SmallDashboardWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "配置 1×1 仪表盘"
    static let description = IntentDescription("选择一个额度量和显示风格。")

    @Parameter(title: "额度 1")
    var metric1: DashboardQuotaMetric?

    @Parameter(title: "显示风格")
    var style: DashboardDisplayStyle?

    init() {
        metric1 = nil
        style = .cleanCard
    }
}

struct MediumDashboardWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "配置 1×2 仪表盘"
    static let description = IntentDescription("最多配置四个额度量；每一项都可以留空。")

    @Parameter(title: "额度 1（可选）")
    var metric1: DashboardQuotaMetric?

    @Parameter(title: "额度 2（可选）")
    var metric2: DashboardQuotaMetric?

    @Parameter(title: "额度 3（可选）")
    var metric3: DashboardQuotaMetric?

    @Parameter(title: "额度 4（可选）")
    var metric4: DashboardQuotaMetric?

    @Parameter(title: "显示风格")
    var style: DashboardDisplayStyle?

    init() {
        metric1 = nil
        metric2 = nil
        metric3 = nil
        metric4 = nil
        style = .cleanCard
    }
}

struct DashboardConfiguration {
    let metrics: [DashboardQuotaMetric?]
    let style: DashboardDisplayStyle?
}

enum DashboardDisplayStyle: String, AppEnum {
    case cleanCard
    case immersiveDark
    case softGradient

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "显示风格")
    static let caseDisplayRepresentations: [DashboardDisplayStyle: DisplayRepresentation] = [
        .cleanCard: DisplayRepresentation(title: "清爽卡片风"),
        .immersiveDark: DisplayRepresentation(title: "深色沉浸风"),
        .softGradient: DisplayRepresentation(title: "渐变柔和风")
    ]
}

struct DashboardQuotaMetric: AppEntity {
    let id: String
    let providerID: String
    let providerName: String
    let windowID: String
    let windowName: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "额度量")
    static let defaultQuery = DashboardQuotaMetricQuery()

    var displayRepresentation: DisplayRepresentation {
        return DisplayRepresentation(title: "\(providerName)（\(windowName)）")
    }
}

struct DashboardQuotaMetricQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DashboardQuotaMetric] {
        let allMetrics = await loadAvailableMetrics()
        return allMetrics.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DashboardQuotaMetric] {
        return await loadAvailableMetrics()
    }

    private func loadAvailableMetrics() async -> [DashboardQuotaMetric] {
        let snapshot = SharedQuotaStorage.load()
        var metrics: [DashboardQuotaMetric] = []

        for provider in snapshot.providers where provider.isAvailable {
            for window in provider.windows {
                let metric = DashboardQuotaMetric(
                    id: "\(provider.id)_\(window.id)",
                    providerID: provider.id,
                    providerName: provider.name,
                    windowID: window.id,
                    windowName: window.name
                )
                metrics.append(metric)
            }
            // 如果 provider 没有 windows，创建一个默认的
            if provider.windows.isEmpty {
                let metric = DashboardQuotaMetric(
                    id: "\(provider.id)_default",
                    providerID: provider.id,
                    providerName: provider.name,
                    windowID: "default",
                    windowName: provider.periodName ?? "额度"
                )
                metrics.append(metric)
            }
        }
        return metrics
    }
}

struct DashboardQuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaSnapshot
    let configuration: DashboardConfiguration

    /// 解析后的指标列表，每项对应一个配置槽位（可能为 nil）
    var resolvedMetrics: [(provider: QuotaSnapshot.Provider, window: QuotaSnapshot.Provider.Window?)?] {
        return configuration.metrics.map { metric -> (QuotaSnapshot.Provider, QuotaSnapshot.Provider.Window?)? in
            guard let metric else { return nil }

            // 根据 providerID 查找对应的 provider
            guard let provider = snapshot.providers.first(where: { $0.id == metric.providerID }) else { return nil }

            // 根据 windowID 查找对应的 window
            let window: QuotaSnapshot.Provider.Window?
            if metric.windowID == "default" {
                // 默认窗口：选择剩余百分比最低的窗口
                window = provider.windows.min {
                    ($0.remainingPercent ?? 100) < ($1.remainingPercent ?? 100)
                } ?? provider.windows.first
            } else {
                window = provider.window(id: metric.windowID)
            }

            return (provider, window)
        }
    }
}

struct SmallDashboardTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DashboardQuotaEntry {
        DashboardQuotaEntry(
            date: .now,
            snapshot: .placeholder,
            configuration: DashboardConfiguration(metrics: [nil], style: .cleanCard)
        )
    }

    func snapshot(
        for configuration: SmallDashboardWidgetIntent,
        in context: Context
    ) async -> DashboardQuotaEntry {
        DashboardQuotaEntry(
            date: .now,
            snapshot: SharedQuotaStorage.load(),
            configuration: DashboardConfiguration(
                metrics: [configuration.metric1],
                style: configuration.style
            )
        )
    }

    func timeline(
        for configuration: SmallDashboardWidgetIntent,
        in context: Context
    ) async -> Timeline<DashboardQuotaEntry> {
        let now = Date()
        let entry = DashboardQuotaEntry(
            date: now,
            snapshot: SharedQuotaStorage.load(),
            configuration: DashboardConfiguration(
                metrics: [configuration.metric1],
                style: configuration.style
            )
        )
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

struct MediumDashboardTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DashboardQuotaEntry {
        DashboardQuotaEntry(
            date: .now,
            snapshot: .placeholder,
            configuration: DashboardConfiguration(
                metrics: [nil, nil, nil, nil],
                style: .cleanCard
            )
        )
    }

    func snapshot(
        for configuration: MediumDashboardWidgetIntent,
        in context: Context
    ) async -> DashboardQuotaEntry {
        makeEntry(configuration, at: .now)
    }

    func timeline(
        for configuration: MediumDashboardWidgetIntent,
        in context: Context
    ) async -> Timeline<DashboardQuotaEntry> {
        let now = Date()
        return Timeline(
            entries: [makeEntry(configuration, at: now)],
            policy: .after(Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now)
        )
    }

    private func makeEntry(
        _ configuration: MediumDashboardWidgetIntent,
        at date: Date
    ) -> DashboardQuotaEntry {
        DashboardQuotaEntry(
            date: date,
            snapshot: SharedQuotaStorage.load(),
            configuration: DashboardConfiguration(
                metrics: [
                    configuration.metric1,
                    configuration.metric2,
                    configuration.metric3,
                    configuration.metric4
                ],
                style: configuration.style
            )
        )
    }
}

struct TokenViewerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DashboardQuotaEntry

    private var style: DashboardDisplayStyle {
        entry.configuration.style ?? .cleanCard
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                smallLayout
            } else {
                mediumLayout
            }
        }
        .containerBackground(for: .widget) {
            dashboardBackground
        }
        .widgetURL(URL(string: "tokenviewer://overview"))
    }

    private var smallLayout: some View {
        return Group {
            if let resolved = entry.resolvedMetrics.first ?? nil {
                DashboardCard(
                    provider: resolved.provider,
                    window: resolved.window,
                    style: style
                )
            } else {
                EmptyDashboardSlot(compact: true, style: style)
            }
        }
        .padding(12)
    }

    private var mediumLayout: some View {
        let resolvedMetrics = Array(entry.resolvedMetrics.prefix(4))
        return VStack(spacing: 5) {
            HStack(alignment: .center, spacing: resolvedMetrics.count >= 4 ? 8 : 18) {
                ForEach(Array(resolvedMetrics.enumerated()), id: \.offset) { _, resolved in
                    if let resolved {
                        QuotaRing(
                            name: resolved.provider.name,
                            symbol: resolved.provider.symbol,
                            windowName: resolved.window?.name,
                            remaining: resolved.window?.remainingPercent,
                            resetAt: resolved.window?.resetAt,
                            isAvailable: resolved.provider.isAvailable,
                            compact: false,
                            style: style,
                            showsCountdown: true,
                            displayText: resolved.window?.displayText,
                            displayMode: resolved.window?.displayMode
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        EmptyDashboardSlot(compact: false, style: style)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var dashboardBackground: some View {
        switch style {
        case .cleanCard:
            Color(red: 0.97, green: 0.98, blue: 1.0)
        case .immersiveDark:
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.20, blue: 0.27),
                         Color(red: 0.08, green: 0.15, blue: 0.21)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .softGradient:
            LinearGradient(
                colors: [Color(red: 0.80, green: 0.95, blue: 1.0),
                         Color(red: 0.96, green: 0.99, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct DashboardCard: View {
    let provider: QuotaSnapshot.Provider
    let window: QuotaSnapshot.Provider.Window?
    let style: DashboardDisplayStyle

    private var isBalanceMode: Bool {
        window?.displayMode == .balance
    }

    private var remaining: Double {
        max(0, min(100, window?.remainingPercent ?? 0))
    }

    private var progress: Double {
        isBalanceMode ? 1 : remaining / 100
    }

    private var foreground: Color {
        style == .immersiveDark ? .white : Color(red: 0.06, green: 0.14, blue: 0.22)
    }

    private var secondary: Color {
        foreground.opacity(0.56)
    }

    private var accent: Color {
        guard provider.isAvailable else {
            return foreground.opacity(0.25)
        }
        if isBalanceMode {
            return style == .cleanCard
                ? Color(red: 0.20, green: 0.50, blue: 0.96)
                : Color(red: 0.13, green: 0.77, blue: 0.37)
        }
        guard window?.remainingPercent != nil else {
            return foreground.opacity(0.25)
        }
        if remaining < 20 { return Color(red: 0.94, green: 0.27, blue: 0.27) }
        if remaining <= 50 { return Color(red: 0.98, green: 0.59, blue: 0.05) }
        return style == .cleanCard
            ? Color(red: 0.20, green: 0.50, blue: 0.96)
            : Color(red: 0.13, green: 0.77, blue: 0.37)
    }

    private var displayValue: String {
        guard provider.isAvailable else { return "--" }
        if isBalanceMode, let text = window?.displayText {
            return text
        }
        return "\(Int(remaining.rounded()))%"
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: provider.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 25, height: 25)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(foreground.opacity(0.68), lineWidth: 1.4)
                        )

                    Text(provider.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.16), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(displayValue)
                            .font(.system(size: isBalanceMode ? 14 : 18, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(isBalanceMode ? "余额" : "剩余额度")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(secondary)
                    }
                }
                .frame(width: 58, height: 58)
            }

            HStack(spacing: 9) {
                if isBalanceMode {
                    stat(title: "类型", value: window?.name ?? "余额")
                } else {
                    stat(title: "已用", value: "\(Int((100 - remaining).rounded()))%")
                }
                Rectangle().fill(foreground.opacity(0.13)).frame(width: 1, height: 24)
                stat(title: "窗口", value: window?.name ?? "未配置")
            }
            .padding(.top, 6)
            .padding(.horizontal, style == .softGradient ? 7 : 0)
            .padding(.vertical, style == .softGradient ? 5 : 0)
            .background {
                if style == .softGradient {
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.78))
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                }
            }

            if !isBalanceMode {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                    if let resetAt = window?.resetAt {
                        Text(formatNextReset(resetAt))
                    } else {
                        Text("重置时间未知")
                    }
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 1)
            }
        }
        .foregroundStyle(foreground)
    }

    /// 格式化下次刷新时间：统一显示为"月-日"
    private func formatNextReset(_ resetAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return "下次 \(formatter.string(from: resetAt))"
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuotaRing: View {
    let name: String
    let symbol: String
    var windowName: String?
    let remaining: Double?
    let resetAt: Date?
    let isAvailable: Bool
    let compact: Bool
    let style: DashboardDisplayStyle
    let showsCountdown: Bool
    var displayText: String?
    var displayMode: QuotaSnapshot.Provider.WindowDisplayMode?

    private var progress: Double {
        max(0, min(1, (remaining ?? 0) / 100))
    }

    var body: some View {
        VStack(spacing: compact ? 3 : 10) {
            ZStack {
                Circle()
                    .stroke(primaryColor.opacity(0.13), lineWidth: compact ? 7 : 6)

                Circle()
                    .trim(from: 0, to: displayMode == .balance ? 1 : progress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: compact ? 7 : 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Image(systemName: symbol)
                        .font(.system(size: compact ? 14 : 13, weight: .semibold))
                    Text(valueText)
                        .font(.system(size: compact ? 11 : 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(primaryColor.opacity(isAvailable ? 0.92 : 0.42))
            }
            .frame(width: compact ? 72 : 54, height: compact ? 72 : 54)

            VStack(spacing: compact ? 1 : 3) {
                Text(name)
                    .font(.system(size: compact ? 10 : 9, weight: .semibold))

                if let windowName {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                        Text(windowName)
                    }
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(primaryColor.opacity(0.62))
                }

                if showsCountdown, let resetAt, isAvailable {
                    Text("\(formatNextReset(resetAt))")
                        .font(.system(size: compact ? 9 : 8, weight: .medium, design: .rounded))
                        .foregroundStyle(primaryColor.opacity(0.56))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(primaryColor.opacity(0.78))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityLabel("\(name) \(windowName ?? "") 剩余 \(valueText)，\(accessibilityResetText)")
    }

    private var valueText: String {
        guard isAvailable else { return "--" }
        // 余额模式：显示余额文本
        if displayMode == .balance, let text = displayText {
            return text
        }
        // 百分比模式
        guard let remaining else { return "--" }
        return "\(Int(remaining.rounded()))%"
    }

    private var ringColor: Color {
        guard let remaining, isAvailable else { return .white.opacity(0.18) }
        if remaining < 20 { return Color(red: 0.94, green: 0.27, blue: 0.27) }
        if remaining <= 50 { return Color(red: 0.98, green: 0.59, blue: 0.05) }
        return Color(red: 0.13, green: 0.77, blue: 0.37)
    }

    private var statusColor: Color {
        ringColor
    }

    private var primaryColor: Color {
        style == .immersiveDark ? .white : Color(red: 0.06, green: 0.14, blue: 0.22)
    }

    private var accessibilityResetText: String {
        guard let resetAt, isAvailable else { return "等待刷新时间" }
        if resetAt <= .now { return "额度即将刷新" }
        return "距离刷新还剩 \(resetAt.formatted(.relative(presentation: .named)))"
    }

    /// 格式化下次刷新时间：统一显示为"月-日"
    private func formatNextReset(_ resetAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return "下次 \(formatter.string(from: resetAt))"
    }
}

private struct EmptyQuotaRing: View {
    let compact: Bool

    var body: some View {
        Circle()
            .stroke(.white.opacity(0.08), lineWidth: compact ? 8 : 10)
            .frame(width: compact ? 72 : 54, height: compact ? 72 : 54)
            .accessibilityHidden(true)
    }
}

private struct EmptyDashboardSlot: View {
    let compact: Bool
    let style: DashboardDisplayStyle

    private var foreground: Color {
        style == .immersiveDark ? .white : Color(red: 0.06, green: 0.14, blue: 0.22)
    }

    var body: some View {
        VStack(spacing: 7) {
            Circle()
                .stroke(
                    foreground.opacity(0.25),
                    style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                )
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: compact ? 18 : 14, weight: .medium))
                        .foregroundStyle(foreground.opacity(0.45))
                }
                .frame(width: compact ? 64 : 54, height: compact ? 64 : 54)
            Text("未配置")
                .font(.system(size: compact ? 10 : 8, weight: .medium))
                .foregroundStyle(foreground.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@main
struct TokenViewerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenViewerSmallQuotaWidget()
        TokenViewerMediumQuotaWidget()
        TokenViewerPetWidget()
    }
}

struct TokenViewerSmallQuotaWidget: Widget {
    let kind = "TokenViewerSmallQuotaWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SmallDashboardWidgetIntent.self,
            provider: SmallDashboardTimelineProvider()
        ) { entry in
            TokenViewerWidgetView(entry: entry)
        }
        .configurationDisplayName("模型额度 · 1×1")
        .description("绑定一个额度量。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct TokenViewerMediumQuotaWidget: Widget {
    let kind = "TokenViewerMediumQuotaWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: MediumDashboardWidgetIntent.self,
            provider: MediumDashboardTimelineProvider()
        ) { entry in
            TokenViewerWidgetView(entry: entry)
        }
        .configurationDisplayName("模型额度 · 1×2")
        .description("最多配置四个额度量，每项均可留空。")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

enum PetAIService: String, AppEnum {
    case codex
    case claude

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "AI 服务")
    static let caseDisplayRepresentations: [PetAIService: DisplayRepresentation] = [
        .codex: DisplayRepresentation(title: "Codex"),
        .claude: DisplayRepresentation(title: "Claude Code")
    ]
}

enum PetQuotaPeriod: String, AppEnum {
    case shortTerm
    case weekly

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "额度周期")
    static let caseDisplayRepresentations: [PetQuotaPeriod: DisplayRepresentation] = [
        .shortTerm: DisplayRepresentation(title: "短期额度"),
        .weekly: DisplayRepresentation(title: "周额度")
    ]

    var windowID: String {
        switch self {
        case .shortTerm: "primary"
        case .weekly: "secondary"
        }
    }
}

struct PetWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "绑定 AI 服务"
    static let description = IntentDescription("选择宠物要关注的 AI 服务和额度周期。")

    @Parameter(title: "AI 服务")
    var service: PetAIService?

    @Parameter(title: "额度周期")
    var period: PetQuotaPeriod?

    init() {
        service = .codex
        period = .shortTerm
    }

    init(service: PetAIService, period: PetQuotaPeriod = .shortTerm) {
        self.service = service
        self.period = period
    }
}

struct PetQuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaSnapshot
    let configuration: PetWidgetIntent

    var provider: QuotaSnapshot.Provider? {
        let selectedID = configuration.service?.rawValue ?? PetAIService.codex.rawValue
        return snapshot.providers.first { $0.id == selectedID }
    }

    var selectedWindow: QuotaSnapshot.Provider.Window? {
        if let window = provider?.window(id: selectedPeriod.windowID) {
            return window
        }

        guard selectedPeriod == .shortTerm,
              let provider else {
            return nil
        }

        return QuotaSnapshot.Provider.Window(
            id: selectedPeriod.windowID,
            name: provider.periodName ?? "短期额度",
            remainingPercent: provider.remainingPercent,
            resetAt: provider.resetAt,
            resetDetectedAt: provider.resetDetectedAt
        )
    }

    var selectedPeriod: PetQuotaPeriod {
        configuration.period ?? .shortTerm
    }
}

struct PetQuotaTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PetQuotaEntry {
        PetQuotaEntry(
            date: .now,
            snapshot: .placeholder,
            configuration: PetWidgetIntent(service: .codex, period: .shortTerm)
        )
    }

    func snapshot(
        for configuration: PetWidgetIntent,
        in context: Context
    ) async -> PetQuotaEntry {
        PetQuotaEntry(
            date: .now,
            snapshot: SharedQuotaStorage.load(),
            configuration: configuration
        )
    }

    func timeline(
        for configuration: PetWidgetIntent,
        in context: Context
    ) async -> Timeline<PetQuotaEntry> {
        let now = Date()
        let snapshot = SharedQuotaStorage.load()
        var entries = [
            PetQuotaEntry(date: now, snapshot: snapshot, configuration: configuration)
        ]

        let selectedID = configuration.service?.rawValue ?? PetAIService.codex.rawValue
        let selectedPeriod = configuration.period ?? .shortTerm
        if let resetDetectedAt = snapshot.providers
            .first(where: { $0.id == selectedID })?
            .window(id: selectedPeriod.windowID)?
            .resetDetectedAt {
            let revivalEndsAt = resetDetectedAt.addingTimeInterval(10 * 60)
            if revivalEndsAt > now {
                entries.append(
                    PetQuotaEntry(
                        date: revivalEndsAt,
                        snapshot: snapshot,
                        configuration: configuration
                    )
                )
            }
        }

        let nextRefresh = Calendar.current.date(
            byAdding: .minute,
            value: 5,
            to: now
        ) ?? now.addingTimeInterval(5 * 60)
        return Timeline(entries: entries, policy: .after(nextRefresh))
    }
}

struct TokenViewerPetWidget: Widget {
    let kind = "TokenViewerPetWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: PetWidgetIntent.self,
            provider: PetQuotaTimelineProvider()
        ) { entry in
            PetQuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("额度宠物")
        .description("绑定一个 AI 服务和额度周期，让宠物用状态展示剩余额度。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct PetQuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PetQuotaEntry

    private var provider: QuotaSnapshot.Provider? { entry.provider }
    private var selectedWindow: QuotaSnapshot.Provider.Window? { entry.selectedWindow }
    private var mood: QuotaPetMood {
        guard provider?.isAvailable == true else { return .disconnected }
        if let selectedWindow {
            return selectedWindow.petMood(at: entry.date)
        }
        return .disconnected
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .padding(family == .systemSmall ? 14 : 18)
        .containerBackground(for: .widget) {
            PetBackground(mood: mood)
        }
        .widgetURL(URL(string: "tokenviewer://overview"))
    }

    private var smallLayout: some View {
        VStack(spacing: 5) {
            header
            Spacer(minLength: 0)
            QuotaPetView(mood: mood)
                .frame(width: 82, height: 82)
            Spacer(minLength: 0)
            Text(mood.statusText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.9))
            if let resetAt = selectedWindow?.resetAt {
                Text(formatNextReset(resetAt))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 20) {
            QuotaPetView(mood: mood)
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 8) {
                header
                Text(mood.statusText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let periodName = selectedWindow?.name ?? fallbackPeriodName {
                    Label(periodName, systemImage: "clock")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }

                if let resetAt = selectedWindow?.resetAt {
                    Text(formatNextReset(resetAt))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: provider?.symbol ?? "questionmark")
                .font(.caption.weight(.bold))
            Text(provider?.name ?? selectedServiceName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(remainingText)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
    }

    private var selectedServiceName: String {
        switch entry.configuration.service ?? .codex {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }

    private var remainingText: String {
        guard provider?.isAvailable == true,
              let remaining = selectedWindow?.remainingPercent else {
            return "--"
        }
        return "\(Int(remaining.rounded()))%"
    }

    private var fallbackPeriodName: String? {
        switch entry.selectedPeriod {
        case .shortTerm: "短期额度"
        case .weekly: "周额度"
        }
    }

    /// 格式化下次刷新时间：统一显示为"月-日"
    private func formatNextReset(_ resetAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return "下次 \(formatter.string(from: resetAt))"
    }
}

private struct ResetCountdownText: View {
    let resetAt: Date?
    let prefix: String
    let expiredText: String
    let compact: Bool

    var body: some View {
        if let resetAt {
            if resetAt > .now {
                HStack(spacing: compact ? 1 : 3) {
                    if !prefix.isEmpty {
                        Text(prefix)
                    }
                    Text(resetAt, style: .timer)
                        .monospacedDigit()
                }
            } else {
                Text(expiredText)
            }
        } else {
            Text("等待刷新时间")
        }
    }
}

private struct PetBackground: View {
    let mood: QuotaPetMood

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 150, height: 150)
                .offset(x: 70, y: -70)
            Circle()
                .fill(.black.opacity(0.08))
                .frame(width: 130, height: 130)
                .offset(x: -80, y: 80)
        }
    }

    private var colors: [Color] {
        switch mood {
        case .revived:
            [Color(red: 0.19, green: 0.66, blue: 0.47),
             Color(red: 0.15, green: 0.43, blue: 0.73)]
        case .relaxed:
            [Color(red: 0.24, green: 0.49, blue: 0.75),
             Color(red: 0.31, green: 0.28, blue: 0.62)]
        case .focused:
            [Color(red: 0.20, green: 0.42, blue: 0.62),
             Color(red: 0.17, green: 0.28, blue: 0.45)]
        case .tired:
            [Color(red: 0.66, green: 0.37, blue: 0.22),
             Color(red: 0.38, green: 0.24, blue: 0.33)]
        case .exhausted:
            [Color(red: 0.48, green: 0.21, blue: 0.24),
             Color(red: 0.22, green: 0.18, blue: 0.27)]
        case .disconnected:
            [Color(red: 0.28, green: 0.31, blue: 0.36),
             Color(red: 0.16, green: 0.18, blue: 0.22)]
        }
    }
}

private struct QuotaPetView: View {
    let mood: QuotaPetMood

    var body: some View {
        GeometryReader { proxy in
            Image(imageName)
                .resizable()
                .renderingMode(.original)
                .interpolation(.none)
                .widgetFullColorRendering()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(imageScale)
                .opacity(mood == .disconnected ? 0.48 : 1)
                .clipped()
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
        }
        .accessibilityLabel(mood.statusText)
    }

    private var imageName: String {
        switch mood {
        case .revived, .relaxed: "high"
        case .focused, .disconnected: "normal"
        case .tired, .exhausted: "low"
        }
    }

    private var imageScale: CGFloat {
        switch mood {
        case .revived, .relaxed: 1.8
        case .focused, .disconnected, .tired, .exhausted: 2.25
        }
    }
}

private extension Image {
    @ViewBuilder
    func widgetFullColorRendering() -> some View {
        if #available(macOS 15.0, *) {
            self.widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}
