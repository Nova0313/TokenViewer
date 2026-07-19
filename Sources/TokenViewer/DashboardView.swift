import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: QuotaStore
    @State private var showingAddService = false
    @State private var showingAddAPIProvider = false
    @State private var editingProvider: LocalProvider?
    @State private var editingAPIProvider: APIProviderConfig?
    @State private var providerPendingRemoval: LocalProvider?
    @State private var apiProviderPendingRemoval: APIProviderConfig?

    var body: some View {
        VStack(spacing: 0) {
            header
            summaryCard
            content
            bottomBar
        }
        .frame(minWidth: 760, idealWidth: 920, minHeight: 600, idealHeight: 760)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.96, blue: 1.0),
                    Color(red: 0.96, green: 0.97, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task { store.start() }
        .onOpenURL { url in
            guard url.scheme == "tokenviewer" else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .sheet(isPresented: $showingAddService) {
            AddServiceView(store: store)
        }
        .sheet(isPresented: $showingAddAPIProvider) {
            AddAPIProviderView(store: store)
        }
        .sheet(item: $editingProvider) { provider in
            EditServiceView(store: store, provider: provider)
        }
        .sheet(item: $editingAPIProvider) { config in
            EditAPIProviderView(store: store, config: config)
        }
        .alert(
            "解绑 AI 服务？",
            isPresented: Binding(
                get: { providerPendingRemoval != nil },
                set: { if !$0 { providerPendingRemoval = nil } }
            ),
            presenting: providerPendingRemoval
        ) { provider in
            Button("解绑", role: .destructive) {
                store.remove(provider)
                providerPendingRemoval = nil
            }
            Button("取消", role: .cancel) {
                providerPendingRemoval = nil
            }
        } message: { provider in
            Text("只会移除 TokenViewer 中的 \(provider.name) 绑定，不会删除原 App 或日志。")
        }
        .alert(
            "删除 API 配置？",
            isPresented: Binding(
                get: { apiProviderPendingRemoval != nil },
                set: { if !$0 { apiProviderPendingRemoval = nil } }
            ),
            presenting: apiProviderPendingRemoval
        ) { config in
            Button("删除", role: .destructive) {
                store.removeAPIProvider(config)
                apiProviderPendingRemoval = nil
            }
            Button("取消", role: .cancel) {
                apiProviderPendingRemoval = nil
            }
        } message: { config in
            Text("将移除 \(config.name) 的 API 配置和保存在 Keychain 中的 API Key。")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 48, height: 48)
                .background(.blue.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("TokenViewer")
                    .font(.title2.weight(.bold))
                Text("额度总览")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 16) {
                // 最后更新时间
                if let lastRefresh = store.lastRefresh {
                    Text("最后更新：\(lastRefresh.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 自动刷新间隔选择器
                Menu {
                    ForEach(QuotaStore.supportedRefreshIntervals, id: \.self) { minutes in
                        Button(minutes == 60 ? "每1小时" : "每\(minutes)分钟") {
                            store.setRefreshInterval(minutes: minutes)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("自动刷新间隔：\(store.refreshIntervalMinutes == 60 ? "每1小时" : "每\(store.refreshIntervalMinutes)分钟")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)

                // 全部刷新按钮
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("全部刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var summaryCard: some View {
        let allProviders = store.providers
        let normalCount = allProviders.filter { provider in
            provider.lowestRemainingPercent.map { $0 >= 20 } ?? false
        }.count
        let lowCount = allProviders.filter { provider in
            provider.lowestRemainingPercent.map { $0 < 20 } ?? false
        }.count
        let pendingCount = allProviders.filter { $0.windows.isEmpty }.count

        return HStack(spacing: 0) {
            summaryStatus(
                color: .green,
                title: "正常服务",
                count: normalCount
            )

            summaryDivider

            summaryStatus(
                color: .orange,
                title: "低额度服务",
                count: lowCount
            )

            summaryDivider

            summaryStatus(
                color: .secondary,
                title: "待配置服务",
                count: pendingCount
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            Color(red: 0.96, green: 0.98, blue: 1.0),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(.separator.opacity(0.45))
            .frame(width: 1, height: 58)
            .padding(.horizontal, 22)
    }

    private func summaryStatus(color: Color, title: String, count: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.headline)
                Text("\(count)").font(.title2.weight(.bold)).foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryColor(_ value: Double) -> Color {
        if value < 20 { return .red }
        if value <= 50 { return .orange }
        return .green
    }

    @ViewBuilder
    private var content: some View {
        if store.bindings.isEmpty && store.apiProviders.isEmpty {
            ContentUnavailableView {
                Label("还没有绑定 AI 服务", systemImage: "square.stack.3d.up.slash")
            } description: {
                Text("添加本机已安装的 Claude Code 或 Codex，或填入 API 配置后即可查看额度。")
            } actions: {
                Button("添加本地 AI 服务") {
                    showingAddService = true
                }
                .buttonStyle(.borderedProminent)

                Button("添加 API 配置") {
                    showingAddAPIProvider = true
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 20) {
                // 左侧：服务列表
                ScrollView {
                    VStack(spacing: 20) {
                        // 本地服务区域
                        if !store.bindings.isEmpty {
                            serviceSection(
                                title: "本地服务",
                                color: .blue,
                                bindings: store.bindings
                            )
                        }

                        // API 服务区域
                        if !store.apiProviders.isEmpty {
                            apiProviderSection(
                                title: "API 服务",
                                color: .purple,
                                configs: store.apiProviders
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // 右侧：待配置服务详情
                if !pendingServices.isEmpty {
                    pendingServicesPanel
                        .frame(width: 320)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
    }

    private var pendingServices: [ProviderQuota] {
        store.providers.filter { $0.windows.isEmpty }
    }

    private var pendingServicesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(.secondary).frame(width: 8, height: 8)
                Text("待配置服务").font(.headline)
                Text("(\(pendingServices.count))").foregroundStyle(.secondary)
            }

            ForEach(pendingServices) { provider in
                PendingServiceCard(provider: provider)
            }

            // 状态信息
            statusInfo
        }
    }

    private var statusInfo: some View {
        let totalServices = store.bindings.count + store.apiProviders.count
        let availableServices = store.providers.filter { !$0.windows.isEmpty }.count

        return VStack(alignment: .leading, spacing: 8) {
            if availableServices == totalServices && pendingServices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("状态良好，暂无低额度服务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("共\(totalServices)个服务，全部运行正常")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            Color(red: 0.96, green: 0.98, blue: 1.0),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    @ViewBuilder
    private func serviceSection(
        title: String,
        color: Color,
        bindings: [ProviderBinding]
    ) -> some View {
        if !bindings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(title).font(.headline)
                    Text("(\(bindings.count))").foregroundStyle(.secondary)
                }

                ForEach(bindings) { binding in
                    ServiceCard(
                        binding: binding,
                        provider: store.providers.first { $0.id == binding.provider.id },
                        isRefreshing: store.isRefreshing(binding.provider),
                        onRefresh: { Task { await store.refresh(binding.provider) } },
                        onEdit: { editingProvider = binding.provider },
                        onRemove: { providerPendingRemoval = binding.provider }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func apiProviderSection(
        title: String,
        color: Color,
        configs: [APIProviderConfig]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.headline)
                Text("(\(configs.count))").foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingAddAPIProvider = true
                } label: {
                    Label("添加 API 配置", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if configs.isEmpty {
                Text("尚未添加 API 配置。借鉴 CC Switch 的设计，填入 API Key 与 Base URL 后即可拉取额度使用情况。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(configs) { config in
                    APIServiceCard(
                        config: config,
                        provider: store.providers.first { $0.id == config.quotaID },
                        isRefreshing: store.isRefreshing(config),
                        onRefresh: { Task { await store.refreshAPI(config) } },
                        onEdit: { editingAPIProvider = config },
                        onRemove: { apiProviderPendingRemoval = config }
                    )
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button {
                showingAddService = true
            } label: {
                Label("添加本地服务", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            Button {
                showingAddAPIProvider = true
            } label: {
                Label("添加 API 配置", systemImage: "network")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(red: 0.93, green: 0.96, blue: 0.99))
        .overlay(alignment: .top) { Divider() }
    }
}

private struct ServiceCard: View {
    let binding: ProviderBinding
    let provider: ProviderQuota?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: binding.provider.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(iconTint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 5) {
                    Text(binding.provider.name)
                        .font(.title3.weight(.bold))
                    connectionStatus
                }

                Spacer()

                if let remaining = provider?.lowestRemainingPercent {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(Int(remaining.rounded()))% 剩余")
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(color(for: remaining))
                        Text(provider?.windows.first.map { "关键周期 \($0.name)" } ?? "额度可用")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help("刷新")

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("编辑")

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("解绑")

                Image(systemName: serviceWindowsIconName)
                    .foregroundStyle(.tertiary)
            }

            if let provider {
                switch provider.state {
                case .available:
                    VStack(spacing: 0) {
                        ForEach(provider.windows) { window in
                            DashboardQuotaRow(window: window)
                            if window.id != provider.windows.last?.id {
                                Divider().padding(.vertical, 9)
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        Color(red: 0.93, green: 0.96, blue: 0.99),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.separator.opacity(0.35), lineWidth: 1)
                    }
                case .unavailable(let message):
                    HStack(spacing: 14) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.title2)
                            .foregroundStyle(.orange)
                            .frame(width: 46, height: 46)
                            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("暂无额度数据").font(.headline)
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("重新检测", action: onRefresh)
                    }
                    .padding(14)
                    .background(
                        Color(red: 1.0, green: 0.97, blue: 0.91),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.separator.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                }

                Label(
                    provider.updatedAt.map {
                        "最近记录时间 \($0.formatted(date: .omitted, time: .shortened))"
                    } ?? "最近记录时间未知",
                    systemImage: "clock"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            } else {
                ProgressView("正在读取额度…")
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            Color(red: 0.985, green: 0.99, blue: 1.0),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var iconTint: Color {
        binding.provider == .codex ? .blue : .orange
    }

    private var serviceWindowsIconName: String {
        if #available(macOS 15.0, *) {
            return "circle.grid.2x3.fill"
        }
        return "circle.grid.3x3.fill"
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if let provider {
            switch provider.state {
            case .available:
                Label("已连接", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .unavailable:
                Label("已绑定，暂无额度数据", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        } else {
            Label("连接中", systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }

    private func color(for remaining: Double) -> Color {
        if remaining <= 10 { return .red }
        if remaining <= 30 { return .orange }
        return .green
    }
}

private struct DashboardQuotaRow: View {
    let window: QuotaWindow

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
            GridRow {
                Text(window.name)
                    .font(.subheadline.weight(.medium))
                    .frame(width: 60, alignment: .leading)
                if window.displayMode == .balance {
                    // 余额模式：不显示进度条，只显示余额文本
                    HStack {
                        Text(window.displayText ?? "—")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(tint)
                        Spacer()
                    }
                } else {
                    ProgressView(value: window.remainingPercent, total: 100)
                        .tint(tint)
                        .frame(maxWidth: .infinity)
                    Text("\(Int(window.remainingPercent.rounded()))%")
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .frame(width: 48, alignment: .trailing)
                }
            }
            if window.displayMode != .balance {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    Label(resetText, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Color.clear.frame(width: 1, height: 1)
                }
            }
        }
    }

    private var resetText: String {
        guard let resetAt = window.resetAt else { return "重置时间未知" }
        if resetAt <= Date() { return "即将重置" }
        return "\(resetAt.formatted(date: .abbreviated, time: .shortened)) 重置"
    }

    private var tint: Color {
        if window.displayMode == .balance {
            return window.usedPercent >= 100 ? .red : .green
        }
        if window.remainingPercent <= 10 { return .red }
        if window.remainingPercent <= 30 { return .orange }
        return .accentColor
    }
}

private struct AddServiceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: QuotaStore
    @State private var showingPathPicker = false
    @State private var pendingProvider: LocalProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("添加本地 AI 服务")
                        .font(.title2.weight(.semibold))
                    Text("检测本机已安装的 Claude Code 或 Codex 日志")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
            }

            if store.unboundCandidates.isEmpty {
                ContentUnavailableView(
                    "没有可添加的服务",
                    systemImage: "checkmark.circle",
                    description: Text("所有检测到的服务都已绑定。")
                )
            } else {
                ForEach(store.unboundCandidates, id: \.id) { (candidate: LocalProviderCandidate) in
                    HStack(spacing: 14) {
                        Image(systemName: candidate.provider.symbol)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.provider.name)
                                .font(.headline)
                            Text(candidate.detectionDetail)
                                .font(.caption)
                                .foregroundStyle(
                                    candidate.isDetected
                                        ? AnyShapeStyle(.secondary)
                                        : AnyShapeStyle(.orange)
                                )
                        }
                        Spacer()
                        
                        if candidate.isDetected {
                            Button("添加") {
                                store.add(candidate.provider)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("手动指定路径") {
                                pendingProvider = candidate.provider
                                showingPathPicker = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(14)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            Spacer()

            Button {
                store.rescanLocalApps()
            } label: {
                Label("重新扫描本机", systemImage: "arrow.clockwise")
            }
        }
        .padding(24)
        .frame(width: 500, height: 360)
        .fileImporter(
            isPresented: $showingPathPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first,
               let provider = pendingProvider {
                store.add(provider, customDataPath: url.path)
                pendingProvider = nil
            }
        }
    }
}

private struct EditServiceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: QuotaStore
    let provider: LocalProvider
    @State private var showingPathPicker = false

    private var showInWidget: Binding<Bool> {
        Binding(
            get: {
                store.bindings.first { $0.provider == provider }?.showInWidget ?? false
            },
            set: {
                store.setShowInWidget($0, for: provider)
            }
        )
    }

    private var customDataPath: Binding<String?> {
        Binding(
            get: {
                store.bindings.first { $0.provider == provider }?.customDataPath
            },
            set: {
                store.setCustomDataPath($0, for: provider)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("编辑 \(provider.name)", systemImage: provider.symbol)
                .font(.title2.weight(.semibold))

            Toggle("显示在桌面小组件", isOn: showInWidget)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("自定义数据路径")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("选择文件夹") {
                        showingPathPicker = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let path = customDataPath.wrappedValue {
                    HStack {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button("清除") {
                            customDataPath.wrappedValue = nil
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(.red)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Text("使用默认路径（自动检测）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("额度来自本机日志；TokenViewer 不会上传日志或账号信息。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .fileImporter(
            isPresented: $showingPathPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                customDataPath.wrappedValue = url.path
            }
        }
    }
}

private struct APIServiceCard: View {
    let config: APIProviderConfig
    let provider: ProviderQuota?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: config.template.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(.blue.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(config.name)
                            .font(.title3.weight(.bold))
                        if let vendorName = provider?.vendorName {
                            Text("· \(vendorName)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.blue)
                        }
                    }
                    connectionStatus
                }

                Spacer()

                if let remaining = provider?.lowestRemainingPercent {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(Int(remaining.rounded()))% 剩余")
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(color(for: remaining))
                        Text(provider?.windows.first.map { "关键周期 \($0.name)" } ?? "额度可用")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help("刷新")

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("编辑")

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除")
            }

            VStack(alignment: .leading, spacing: 4) {
                // auto 模式下若 baseURL 是占位，则展示「自动识别」；否则展示用户填写的官网
                let displayURL = (config.template == .auto && config.baseURL.host == "auto.local")
                    ? "自动识别（未指定官网）"
                    : config.baseURL.absoluteString
                Label(displayURL, systemImage: "link")
                if config.template == .auto {
                    Label("\(config.template.displayName)", systemImage: "tag")
                } else {
                    Label(
                        "\(config.template.displayName) · \(config.format.displayName) · \(config.quotaPath)",
                        systemImage: "tag"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let provider {
                switch provider.state {
                case .available:
                    VStack(spacing: 0) {
                        ForEach(provider.windows) { window in
                            DashboardQuotaRow(window: window)
                            if window.id != provider.windows.last?.id {
                                Divider().padding(.vertical, 9)
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        Color(red: 0.93, green: 0.96, blue: 0.99),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.separator.opacity(0.35), lineWidth: 1)
                    }
                case .unavailable(let message):
                    HStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.orange)
                            .frame(width: 46, height: 46)
                            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("暂无额度数据").font(.headline)
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("重新拉取", action: onRefresh)
                    }
                    .padding(14)
                    .background(
                        Color(red: 1.0, green: 0.97, blue: 0.91),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.separator.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                }

                Label(
                    provider.updatedAt.map {
                        "最近拉取时间 \($0.formatted(date: .omitted, time: .shortened))"
                    } ?? "尚未拉取",
                    systemImage: "clock"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            } else {
                ProgressView("正在拉取额度…")
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            Color(red: 0.985, green: 0.99, blue: 1.0),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if let provider {
            switch provider.state {
            case .available:
                Label("已连接", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .unavailable:
                Label("已配置，拉取失败", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        } else {
            Label("准备拉取", systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }

    private func color(for remaining: Double) -> Color {
        if remaining <= 10 { return .red }
        if remaining <= 30 { return .orange }
        return .green
    }
}

struct AddAPIProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: QuotaStore
    @State private var template: APIProviderTemplate = .generic
    @State private var name: String = ""
    @State private var baseURLString: String = ""
    @State private var apiKey: String = ""
    @State private var format: APIFormat = .openAI
    @State private var quotaPath: String = "/v1/usage"
    @State private var useLocalOAuth: Bool = false
    @State private var validationError: String?
    @State private var hasAppliedTemplate: Bool = false

    private var trimmedBaseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://" + trimmed)
    }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return false }
        if trimmedKey.isEmpty { return false }
        // auto 模板需要名称 + 官网链接 + Key
        if template == .auto { return trimmedBaseURL != nil }
        // 其他内置模板也只需要名称 + Key（URL 由模板提供）
        if template.isBuiltin { return true }
        // 自定义类模板还需要 Base URL
        return trimmedBaseURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("添加 API 配置")
                        .font(.title2.weight(.semibold))
                    Text("借鉴 CC Switch 设计，选择模板并填入 API Key 即可拉取额度")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
            }

            warningBanner

            Form {
                Section("预设模板") {
                    Picker("模板", selection: $template) {
                        ForEach(APIProviderTemplate.allCases) { tpl in
                            Text(tpl.displayName).tag(tpl)
                        }
                    }
                    .onChange(of: template) { _, newValue in
                        applyTemplate(newValue)
                    }

                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("基础信息") {
                    TextField("名称", text: $name, prompt: Text("例如 Claude Code Club / 智谱 API"))

                    if template == .auto {
                        // 自动识别：必填官网 URL，用于精准匹配厂商
                        TextField(
                            "官网链接",
                            text: $baseURLString,
                            prompt: Text("例如 https://platform.deepseek.com")
                        )
                        Text("填写官网链接后，系统会按域名自动匹配对应厂商接口（如 DeepSeek、智谱、MiniMax）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        SecureField("API Key", text: $apiKey, prompt: Text("sk-... 或 cr_..."))
                    } else if template.isBuiltin {
                        SecureField("API Key", text: $apiKey, prompt: Text("sk-... 或 cr_..."))
                        // 内置模板的端点不可修改，仅展示，参考 CC Switch 的预设策略
                        LabeledContent("Base URL") {
                            Text(template.defaultBaseURL)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        LabeledContent("额度接口") {
                            Text(template.defaultQuotaPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        LabeledContent("协议格式") {
                            Text(template.defaultFormat.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        TextField("Base URL", text: $baseURLString, prompt: Text("https://api.example.com"))
                    }
                }

                if !template.isBuiltin && template != .auto {
                    Section("协议格式") {
                        Picker("API 格式", selection: $format) {
                            ForEach(APIFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Text(format.shortDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("额度接口路径", text: $quotaPath, prompt: Text("/v1/usage"))
                            .help("默认值由模板提供，可按服务商文档修改")
                    }
                }

                if template.showsExtractorDescription {
                    Section("提取器说明") {
                        Text(template.extractorDescription)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let validationError {
                    Section {
                        Label(validationError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("保存并拉取") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 560, height: 640)
        .onAppear {
            if !hasAppliedTemplate {
                applyTemplate(template, overrideEmpty: true)
                hasAppliedTemplate = true
            }
        }
    }

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("用量查询需要配置专用的查询脚本或 API 参数，请确保您已从供应商处获取相关信息。")
                    .font(.caption.weight(.medium))
                Text("如不确定如何配置，请先查阅供应商文档。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.orange.opacity(0.35), lineWidth: 1)
        }
    }

    private func applyTemplate(_ tpl: APIProviderTemplate, overrideEmpty: Bool = false) {
        if overrideEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = tpl.suggestedName
        }
        // 内置模板（含 auto）的端点是固定的，切换时强制覆盖用户可能填入的脏数据
        // 例如从 custom 切到 deepseek，要清掉 /anthropic、/v1 之类的子路径
        if tpl.isBuiltin {
            baseURLString = tpl.defaultBaseURL
            quotaPath = tpl.defaultQuotaPath
            format = tpl.defaultFormat
        } else if overrideEmpty || baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseURLString = tpl.defaultBaseURL
            quotaPath = tpl.defaultQuotaPath
            format = tpl.defaultFormat
        }
        useLocalOAuth = false
    }

    private func save() {
        // 内置模板（除 auto 外）忽略 UI 中的 Base URL/Path/Format，store 内部会用模板默认值
        let url: URL
        if template == .auto {
            // auto 模式：保存用户填写的官网 URL（若留空则用占位，读取时会回退到遍历所有厂商）
            if let trimmedURL = trimmedBaseURL {
                url = trimmedURL
            } else {
                url = URL(string: "https://auto.local")!
            }
        } else if template.isBuiltin {
            guard let builtinURL = URL(string: template.defaultBaseURL) else {
                validationError = "模板 Base URL 无效"
                return
            }
            url = builtinURL
        } else {
            guard let trimmedURL = trimmedBaseURL else {
                validationError = "Base URL 无效"
                return
            }
            url = trimmedURL
        }
        store.addAPIProvider(
            name: name,
            baseURL: url,
            apiKey: apiKey,
            format: format,
            quotaPath: quotaPath,
            template: template,
            useLocalOAuth: useLocalOAuth
        )
        dismiss()
    }
}

struct EditAPIProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: QuotaStore
    let config: APIProviderConfig
    @State private var template: APIProviderTemplate
    @State private var name: String
    @State private var baseURLString: String
    @State private var apiKey: String = ""
    @State private var format: APIFormat
    @State private var quotaPath: String
    @State private var useLocalOAuth: Bool
    @State private var showInWidget: Bool

    init(store: QuotaStore, config: APIProviderConfig) {
        self.store = store
        self.config = config
        _template = State(initialValue: config.template)
        _name = State(initialValue: config.name)
        _baseURLString = State(initialValue: config.baseURL.absoluteString)
        _format = State(initialValue: config.format)
        _quotaPath = State(initialValue: config.quotaPath)
        _useLocalOAuth = State(initialValue: config.useLocalOAuth)
        _showInWidget = State(initialValue: config.showInWidget)
    }

    private var trimmedBaseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://" + trimmed)
    }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return false }
        if template == .auto { return true }
        if template.isBuiltin { return true }
        return trimmedBaseURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("编辑 \(config.name)", systemImage: config.format.symbol)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            warningBanner

            Form {
                Section("预设模板") {
                    Picker("模板", selection: $template) {
                        ForEach(APIProviderTemplate.allCases) { tpl in
                            Text(tpl.displayName).tag(tpl)
                        }
                    }
                    .onChange(of: template) { _, newValue in
                        useLocalOAuth = false
                        if newValue.isBuiltin {
                            baseURLString = newValue.defaultBaseURL
                            quotaPath = newValue.defaultQuotaPath
                            format = newValue.defaultFormat
                        }
                    }

                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("基础信息") {
                    TextField("名称", text: $name)
                    SecureField("API Key（留空保持不变）", text: $apiKey, prompt: Text("••••••••"))

                    if template == .auto {
                        TextField(
                            "官网链接（可选）",
                            text: $baseURLString,
                            prompt: Text("例如 https://platform.deepseek.com")
                        )
                        Text("填写官网链接可加速识别：会优先按域名匹配对应厂商接口。留空则依次尝试已知供应商（DeepSeek、智谱）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if template.isBuiltin {
                        // 内置模板端点不可修改，仅展示
                        LabeledContent("Base URL") {
                            Text(template.defaultBaseURL)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        LabeledContent("额度接口") {
                            Text(template.defaultQuotaPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        LabeledContent("协议格式") {
                            Text(template.defaultFormat.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        TextField("Base URL", text: $baseURLString)
                    }
                }

                if !template.isBuiltin && template != .auto {
                    Section("协议格式") {
                        Picker("API 格式", selection: $format) {
                            ForEach(APIFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Text(format.shortDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("额度接口路径", text: $quotaPath)
                    }
                }

                if template.showsExtractorDescription {
                    Section("提取器说明") {
                        Text(template.extractorDescription)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section("显示") {
                    Toggle("显示在桌面小组件", isOn: $showInWidget)
                        .toggleStyle(.switch)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("保存") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 560, height: 640)
    }

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("用量查询需要配置专用的查询脚本或 API 参数，请确保您已从供应商处获取相关信息。")
                    .font(.caption.weight(.medium))
                Text("如不确定如何配置，请先查阅供应商文档。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.orange.opacity(0.35), lineWidth: 1)
        }
    }

    private func save() {
        let url: URL
        let effectiveFormat: APIFormat
        let effectivePath: String
        if template == .auto {
            // auto 模式：保存用户填写的官网 URL（若留空则用占位）
            if let trimmedURL = trimmedBaseURL {
                url = trimmedURL
            } else {
                url = URL(string: "https://auto.local")!
            }
            effectiveFormat = template.defaultFormat
            effectivePath = template.defaultQuotaPath
        } else if template.isBuiltin {
            guard let builtinURL = URL(string: template.defaultBaseURL) else { return }
            url = builtinURL
            effectiveFormat = template.defaultFormat
            effectivePath = template.defaultQuotaPath
        } else {
            guard let trimmedURL = trimmedBaseURL else { return }
            url = trimmedURL
            effectiveFormat = format
            effectivePath = quotaPath
        }
        store.updateAPIProvider(
            config,
            name: name,
            baseURL: url,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            format: effectiveFormat,
            quotaPath: effectivePath,
            template: template,
            useLocalOAuth: useLocalOAuth
        )
        if showInWidget != config.showInWidget {
            store.setShowInWidget(showInWidget, for: config)
        }
        dismiss()
    }
}

// MARK: - Pending Service Card

private struct PendingServiceCard: View {
    let provider: ProviderQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name)
                        .font(.headline)

                    if case .unavailable(let message) = provider.state {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }

            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("等待配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}
