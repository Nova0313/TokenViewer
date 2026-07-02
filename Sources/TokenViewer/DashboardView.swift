import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: QuotaStore
    @State private var showingAddService = false
    @State private var editingProvider: LocalProvider?
    @State private var providerPendingRemoval: LocalProvider?

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
        .sheet(item: $editingProvider) { provider in
            EditServiceView(store: store, provider: provider)
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
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 48, height: 48)
                .background(.blue.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("额度总览")
                    .font(.title.weight(.bold))
                Text("本地 AI 服务的剩余额度与重置时间")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let lastRefresh = store.lastRefresh {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("数据更新时间")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(lastRefresh.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.monospacedDigit())
                }
            }

            Picker(
                "自动刷新",
                selection: Binding(
                    get: { store.refreshIntervalMinutes },
                    set: { store.setRefreshInterval(minutes: $0) }
                )
            ) {
                ForEach(QuotaStore.supportedRefreshIntervals, id: \.self) { minutes in
                    Text(minutes == 60 ? "每小时" : "每 \(minutes) 分钟")
                        .tag(minutes)
                }
            }
            .frame(width: 130)
            .help("自动拉取本地额度的频率")

            Button {
                Task { await store.refresh() }
            } label: {
                Label("全部刷新", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var summaryCard: some View {
        let availableProviders = store.providers.filter { !$0.windows.isEmpty }
        let pendingCount = max(0, store.bindings.count - availableProviders.count)
        let overall = availableProviders.compactMap(\.lowestRemainingPercent).min()

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("总体剩余")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(overall.map { "\(Int($0.rounded()))%" } ?? "--")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(overall.map(summaryColor) ?? .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            summaryDivider

            summaryStatus(
                color: .green,
                title: "\(availableProviders.count) 个正常服务",
                subtitle: availableProviders.isEmpty ? "暂无可用额度数据" : "运行正常，额度已同步"
            )

            summaryDivider

            summaryStatus(
                color: .orange,
                title: "\(pendingCount) 个待配置服务",
                subtitle: pendingCount == 0 ? "所有服务均有数据" : "暂无额度数据"
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

    private func summaryStatus(color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
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
        if store.bindings.isEmpty {
            ContentUnavailableView {
                Label("还没有绑定 AI 服务", systemImage: "square.stack.3d.up.slash")
            } description: {
                Text("添加本机已安装的 Claude Code 或 Codex 后，即可查看额度。")
            } actions: {
                Button("添加 AI 服务") {
                    showingAddService = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    serviceSection(
                        title: "已激活服务",
                        color: .green,
                        bindings: store.bindings.filter { binding in
                            store.providers.first { provider in
                                provider.id == binding.provider.id
                            }?.windows.isEmpty == false
                        }
                    )
                    serviceSection(
                        title: "待配置 / 暂无数据",
                        color: .orange,
                        bindings: store.bindings.filter { binding in
                            store.providers.first { provider in
                                provider.id == binding.provider.id
                            }?.windows.isEmpty != false
                        }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
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

    private var bottomBar: some View {
        HStack {
            Text("\(store.bindings.count) 个已绑定服务")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showingAddService = true
            } label: {
                Label("添加 AI 服务", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
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

                Image(systemName: "circle.grid.2x3.fill")
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
                ProgressView(value: window.remainingPercent, total: 100)
                    .tint(tint)
                    .frame(maxWidth: .infinity)
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .frame(width: 48, alignment: .trailing)
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                Label(resetText, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    private var resetText: String {
        guard let resetAt = window.resetAt else { return "重置时间未知" }
        if resetAt <= Date() { return "即将重置" }
        return "\(resetAt.formatted(date: .abbreviated, time: .shortened)) 重置"
    }

    private var tint: Color {
        if window.remainingPercent <= 10 { return .red }
        if window.remainingPercent <= 30 { return .orange }
        return .accentColor
    }
}

private struct AddServiceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: QuotaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("添加 AI 服务")
                        .font(.title2.weight(.semibold))
                    Text("仅显示 TokenViewer 当前支持的本地服务")
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
                        Button("添加") {
                            store.add(candidate.provider)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!candidate.isDetected)
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
    }
}

private struct EditServiceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: QuotaStore
    let provider: LocalProvider

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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("编辑 \(provider.name)", systemImage: provider.symbol)
                .font(.title2.weight(.semibold))

            Toggle("显示在桌面小组件", isOn: showInWidget)
                .toggleStyle(.switch)

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
    }
}
