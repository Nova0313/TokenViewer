import SwiftUI

@main
struct TokenViewerApp: App {
    @StateObject private var store = QuotaStore()

    var body: some Scene {
        Window("TokenViewer", id: "overview") {
            DashboardView(store: store)
        }
        .defaultSize(width: 780, height: 680)
        .handlesExternalEvents(matching: ["overview"])

        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text(store.menuBarTitle)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: QuotaStore

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("TokenViewer")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing)
            }

            ForEach(store.providers) { provider in
                HStack {
                    Label(provider.name, systemImage: provider.symbol)
                    Spacer()
                    Text(provider.lowestRemainingPercent.map {
                        "\(Int($0.rounded()))%"
                    } ?? "--")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            if store.providers.isEmpty {
                Text("暂无额度数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }

            Divider()

            Button {
                openWindow(id: "overview")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("打开额度总览", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button("退出 TokenViewer") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(16)
        .frame(width: 320)
        .task { store.start() }
    }
}
