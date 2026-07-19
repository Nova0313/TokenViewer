import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: QuotaStore
    @State private var isManaging = false
    @State private var providerPendingRemoval: LocalProvider?
    @State private var apiProviderPendingRemoval: APIProviderConfig?

    var body: some View {
        VStack(spacing: 14) {
            header

            if isManaging {
                BindingManager(
                    store: store,
                    providerPendingRemoval: $providerPendingRemoval,
                    apiProviderPendingRemoval: $apiProviderPendingRemoval
                )
            } else {
                overview
            }

            footer
        }
        .padding(16)
        .frame(width: 370, height: 520, alignment: .top)
        .task { store.start() }
        .alert(
            "移除绑定？",
            isPresented: Binding(
                get: { providerPendingRemoval != nil },
                set: { if !$0 { providerPendingRemoval = nil } }
            ),
            presenting: providerPendingRemoval
        ) { provider in
            Button("移除", role: .destructive) {
                store.remove(provider)
                providerPendingRemoval = nil
            }
            Button("取消", role: .cancel) {
                providerPendingRemoval = nil
            }
        } message: { provider in
            Text("只会从 TokenViewer 移除 \(provider.name)，不会删除它的本地数据。")
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
            Text("将删除 \(config.name) 配置及其 Keychain 中的 API Key。")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Token Viewer")
                    .font(.headline)
                Text("AI 编程额度一眼看清")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isManaging {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(store.isRefreshing ? .degrees(360) : .zero)
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing)
                .help("刷新额度")
            }
            Button {
                isManaging.toggle()
            } label: {
                Image(systemName: isManaging ? "checkmark" : "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help(isManaging ? "完成" : "管理本地 AI App")
        }
    }

    @ViewBuilder
    private var overview: some View {
        if store.bindings.isEmpty && store.apiProviders.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("还没有配置 AI 服务")
                    .font(.subheadline.weight(.medium))
                Text("可检测本地 Codex 日志，或填入 API 配置拉取额度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("去配置") {
                    isManaging = true
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        } else if store.providers.isEmpty {
            ProgressView("正在读取额度…")
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.providers) { provider in
                        ProviderCard(provider: provider)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            if !isManaging, let date = store.lastRefresh {
                Text("更新于 \(date.formatted(date: .omitted, time: .shortened))")
            } else if isManaging {
                Text("\(store.bindings.count) 本地 · \(store.apiProviders.count) API")
            }
            Spacer()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct BindingManager: View {
    @ObservedObject var store: QuotaStore
    @Binding var providerPendingRemoval: LocalProvider?
    @Binding var apiProviderPendingRemoval: APIProviderConfig?
    @State private var showingAddAPIProvider = false
    @State private var editingAPIProvider: APIProviderConfig?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                boundSection
                availableSection
                apiProviderSection
            }
        }
        .frame(maxHeight: .infinity)
        .sheet(isPresented: $showingAddAPIProvider) {
            AddAPIProviderView(store: store)
        }
        .sheet(item: $editingAPIProvider) { config in
            EditAPIProviderView(store: store, config: config)
        }
    }

    private var apiProviderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API 配置")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingAddAPIProvider = true
                } label: {
                    Label("添加 API", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            if store.apiProviders.isEmpty {
                Text("尚未添加 API 配置，点击「添加 API」选择预设模板（通用/NewAPI/Token Plan/官方/智谱/DeepSeek）即可拉取额度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(store.apiProviders) { config in
                    apiProviderRow(config)
                }
            }
        }
    }

    private func apiProviderRow(_ config: APIProviderConfig) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: config.template.symbol)
                    .frame(width: 22)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 4) {
                        Text(config.template.displayName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.12), in: Capsule())
                        Text(config.baseURL.host ?? config.baseURL.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    Task { await store.refreshAPI(config) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing(config))
                .help("刷新")

                Button {
                    editingAPIProvider = config
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("编辑")

                Button(role: .destructive) {
                    apiProviderPendingRemoval = config
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除")
            }

            Toggle(
                "显示在桌面小组件",
                isOn: Binding(
                    get: { config.showInWidget },
                    set: { store.setShowInWidget($0, for: config) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var boundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已绑定")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if store.bindings.isEmpty {
                Text("暂无绑定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(Array(store.bindings.enumerated()), id: \.element.id) { index, binding in
                    boundRow(binding, index: index)
                }
            }
        }
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("可添加")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.rescanLocalApps()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            if store.unboundCandidates.isEmpty {
                Text("所有支持的本地 App 都已绑定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(store.unboundCandidates) { candidate in
                    HStack(spacing: 10) {
                        Image(systemName: candidate.provider.symbol)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.provider.name)
                                .font(.subheadline.weight(.medium))
                            Text(candidate.detectionDetail)
                                .font(.caption2)
                                .foregroundStyle(
                                    candidate.isDetected ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange)
                                )
                        }
                        Spacer()
                        Button("添加") {
                            store.add(candidate.provider)
                        }
                        .disabled(!candidate.isDetected)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func boundRow(_ binding: ProviderBinding, index: Int) -> some View {
        let candidate = store.candidate(for: binding.provider)

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: binding.provider.symbol)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(binding.provider.name)
                        .font(.subheadline.weight(.medium))
                    Text(candidate?.detectionDetail ?? "已绑定")
                        .font(.caption2)
                        .foregroundStyle(candidate?.isDetected == false ? .orange : .secondary)
                }
                Spacer()
                Button {
                    store.move(binding.provider, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help("上移")

                Button {
                    store.move(binding.provider, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == store.bindings.count - 1)
                .help("下移")

                Button(role: .destructive) {
                    providerPendingRemoval = binding.provider
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("移除绑定")
            }

            Toggle(
                "显示在桌面小组件",
                isOn: Binding(
                    get: { binding.showInWidget },
                    set: { store.setShowInWidget($0, for: binding.provider) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ProviderCard: View {
    let provider: ProviderQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(provider.name, systemImage: provider.symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let remaining = provider.lowestRemainingPercent {
                    Text("剩余 \(Int(remaining.rounded()))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(color(for: remaining))
                }
            }

            switch provider.state {
            case .available:
                ForEach(provider.windows) { window in
                    QuotaRow(window: window)
                }
            case .unavailable(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func color(for remaining: Double) -> Color {
        if remaining <= 10 { return .red }
        if remaining <= 30 { return .orange }
        return .green
    }
}

private struct QuotaRow: View {
    let window: QuotaWindow

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(window.name)
                Spacer()
                if window.displayMode == .balance {
                    Text(window.displayText ?? "—")
                        .foregroundStyle(tint)
                } else {
                    Text(resetText)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if window.displayMode == .balance {
                // 余额模式：用细线表示可用状态
                Divider().tint(tint.opacity(0.4))
            } else {
                ProgressView(value: window.remainingPercent, total: 100)
                    .tint(tint)
            }
        }
    }

    private var resetText: String {
        guard let resetAt = window.resetAt else { return "重置时间未知" }
        if resetAt <= Date() { return "即将重置" }
        return "重置 \(resetAt.formatted(.relative(presentation: .numeric)))"
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
