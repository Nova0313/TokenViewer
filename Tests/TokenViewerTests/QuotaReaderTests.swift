import Foundation
import XCTest
@testable import TokenViewer

final class QuotaReaderTests: XCTestCase {
    @MainActor
    func testBindingChangesPersistAcrossStoreInstances() throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: home.appending(path: ".codex"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appending(path: ".claude"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let suiteName = "TokenViewerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = QuotaStore(defaults: defaults, homeDirectory: home)
        XCTAssertEqual(firstStore.bindings.map(\.provider), [.claude, .codex])

        firstStore.remove(.claude)
        firstStore.setShowInWidget(false, for: .codex)

        let restoredStore = QuotaStore(defaults: defaults, homeDirectory: home)
        XCTAssertEqual(restoredStore.bindings.map(\.provider), [.codex])
        XCTAssertEqual(restoredStore.bindings.first?.showInWidget, false)
    }

    func testDiscoversLocalProvidersFromDataDirectories() throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: home.appending(path: ".codex"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let candidates = LocalAppDiscovery.candidates(homeDirectory: home)
        let codex = try XCTUnwrap(candidates.first { $0.provider == .codex })
        let claude = try XCTUnwrap(candidates.first { $0.provider == .claude })

        XCTAssertTrue(codex.isDetected)
        XCTAssertFalse(claude.isDetected)
    }

    func testProviderBindingsRoundTrip() throws {
        let bindings = [
            ProviderBinding(provider: .codex, showInWidget: true, sortOrder: 0),
            ProviderBinding(provider: .claude, showInWidget: false, sortOrder: 1)
        ]

        let data = try JSONEncoder().encode(bindings)
        let decoded = try JSONDecoder().decode([ProviderBinding].self, from: data)

        XCTAssertEqual(decoded, bindings)
    }

    func testParsesCodexQuotaFromJSONL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appending(path: "session.jsonl")
        let json = """
        {"timestamp":"2026-06-11T03:47:32Z","payload":{"rate_limits":{"primary":{"used_percent":25,"window_minutes":300,"resets_at":1781167621},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1781754421}}}}
        """
        try json.write(to: file, atomically: true, encoding: .utf8)

        let record = try XCTUnwrap(JSONLQuotaScanner.latestQuotaRecord(in: directory))
        let primary = try XCTUnwrap(record.window(key: "primary", fallbackName: "fallback"))
        let secondary = try XCTUnwrap(record.window(key: "secondary", fallbackName: "fallback"))

        XCTAssertEqual(primary.name, "5 小时")
        XCTAssertEqual(primary.remainingPercent, 75)
        XCTAssertEqual(secondary.name, "7 天")
        XCTAssertEqual(secondary.remainingPercent, 60)
    }

    func testClampsRemainingPercentage() {
        XCTAssertEqual(
            QuotaWindow(id: "a", name: "A", usedPercent: 120, resetAt: nil).remainingPercent,
            0
        )
        XCTAssertEqual(
            QuotaWindow(id: "b", name: "B", usedPercent: -5, resetAt: nil).remainingPercent,
            100
        )
    }

    func testPetMoodTracksRemainingQuotaAndRecentReset() {
        let now = Date()

        XCTAssertEqual(provider(remaining: 90).petMood(at: now), .relaxed)
        XCTAssertEqual(provider(remaining: 55).petMood(at: now), .focused)
        XCTAssertEqual(provider(remaining: 20).petMood(at: now), .tired)
        XCTAssertEqual(provider(remaining: 5).petMood(at: now), .exhausted)
        XCTAssertEqual(provider(remaining: nil).petMood(at: now), .disconnected)
        XCTAssertEqual(
            provider(
                remaining: 88,
                resetDetectedAt: now.addingTimeInterval(-60)
            ).petMood(at: now),
            .revived
        )
    }

    private func provider(
        remaining: Double?,
        resetDetectedAt: Date? = nil
    ) -> QuotaSnapshot.Provider {
        QuotaSnapshot.Provider(
            id: "codex",
            name: "Codex",
            symbol: "terminal",
            remainingPercent: remaining,
            isAvailable: remaining != nil,
            periodName: "5 小时",
            resetAt: nil,
            resetDetectedAt: resetDetectedAt
        )
    }

    func testDeepSeekBalanceParserParsesStandardResponse() throws {
        let json = """
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "9.99",
              "granted_balance": "0.00",
              "topped_up_balance": "9.99"
            }
          ]
        }
        """.data(using: .utf8)!

        let object = try JSONSerialization.jsonObject(with: json)
        let windows = DeepSeekBalanceParser.parse(object: object)

        XCTAssertEqual(windows.count, 2) // 总余额 + 充值
        XCTAssertEqual(windows[0].name, "总余额")
        XCTAssertEqual(windows[0].displayText, "¥9.99")
        XCTAssertEqual(windows[0].displayMode, .balance)
        XCTAssertEqual(windows[0].usedPercent, 0) // 可用 → 0% 已用

        XCTAssertEqual(windows[1].name, "充值")
        XCTAssertEqual(windows[1].displayText, "¥9.99")
    }

    func testDeepSeekBalanceParserHandlesUnavailable() throws {
        let json = """
        {
          "is_available": false,
          "balance_infos": [
            { "currency": "USD", "total_balance": "0.00", "granted_balance": "0.00", "topped_up_balance": "0.00" }
          ]
        }
        """.data(using: .utf8)!

        let object = try JSONSerialization.jsonObject(with: json)
        let windows = DeepSeekBalanceParser.parse(object: object)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].displayText, "$0.00")
        XCTAssertEqual(windows[0].usedPercent, 100) // 不可用 → 100% 已用
    }

    func testDeepSeekBalanceParserRejectsMalformedInput() {
        let windows1 = DeepSeekBalanceParser.parse(object: "not a dict")
        XCTAssertTrue(windows1.isEmpty)

        let windows2 = DeepSeekBalanceParser.parse(object: ["is_available": true])
        XCTAssertTrue(windows2.isEmpty)

        let windows3 = DeepSeekBalanceParser.parse(object: [
            "is_available": true,
            "balance_infos": [["currency": "CNY"]] // 缺 total_balance
        ])
        XCTAssertTrue(windows3.isEmpty)
    }
}
