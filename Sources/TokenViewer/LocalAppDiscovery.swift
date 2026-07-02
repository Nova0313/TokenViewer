import Foundation

enum LocalAppDiscovery {
    static func candidates(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [LocalProviderCandidate] {
        LocalProvider.allCases.map { provider in
            let evidence = detectionPaths(for: provider, homeDirectory: homeDirectory)
                .first { fileManager.fileExists(atPath: $0.path) }

            return LocalProviderCandidate(
                provider: provider,
                isDetected: evidence != nil,
                detectionDetail: evidence.map(detail(for:)) ?? "未在常见位置检测到"
            )
        }
    }

    private static func detectionPaths(
        for provider: LocalProvider,
        homeDirectory: URL
    ) -> [URL] {
        switch provider {
        case .claude:
            [
                homeDirectory.appending(path: ".claude"),
                homeDirectory.appending(path: ".local/bin/claude"),
                URL(filePath: "/opt/homebrew/bin/claude"),
                URL(filePath: "/usr/local/bin/claude"),
                URL(filePath: "/Applications/Claude.app")
            ]
        case .codex:
            [
                homeDirectory.appending(path: ".codex"),
                homeDirectory.appending(path: ".local/bin/codex"),
                URL(filePath: "/opt/homebrew/bin/codex"),
                URL(filePath: "/usr/local/bin/codex"),
                URL(filePath: "/Applications/Codex.app")
            ]
        }
    }

    private static func detail(for url: URL) -> String {
        if url.pathExtension == "app" {
            return "已检测到本地 App"
        }
        if url.lastPathComponent.hasPrefix(".") {
            return "已检测到本地数据"
        }
        return "已检测到命令行工具"
    }
}
