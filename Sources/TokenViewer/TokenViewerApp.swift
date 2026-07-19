import SwiftUI
import AppKit

/// 全局通知：AppDelegate 收到 URL scheme 后通知 SwiftUI 打开窗口
extension Notification.Name {
    static let openOverviewFromWidget = Notification.Name("TokenViewer.openOverviewFromWidget")
}

@main
struct TokenViewerApp: App {
    @StateObject private var store = QuotaStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // 使用 WindowGroup 确保启动时就有一个窗口存在
        WindowGroup("TokenViewer", id: "overview") {
            DashboardView(store: store)
                .onOpenURL { url in
                    // 处理 Widget 点击的 URL
                    if url.scheme == "tokenviewer" {
                        // 激活应用并显示窗口
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
        }
        .defaultSize(width: 780, height: 680)

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

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 注册 URL scheme 处理器，处理 Widget 点击
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // 启动后隐藏主窗口（WindowGroup 会自动创建一个窗口）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApplication.shared.windows {
                if window.title == "TokenViewer" || window.title.contains("TokenViewer") {
                    window.orderOut(nil)
                    break
                }
            }
        }
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        // 激活应用
        NSApplication.shared.activate(ignoringOtherApps: true)
        // 发送通知，让 SwiftUI 视图响应
        NotificationCenter.default.post(name: .openOverviewFromWidget, object: nil)
        // 显示窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                if window.title == "TokenViewer" || window.title.contains("TokenViewer") {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
        }
    }
}
