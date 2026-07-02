import Combine
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var providers: [ProviderQuota] = []
    @Published private(set) var bindings: [ProviderBinding]
    @Published private(set) var candidates: [LocalProviderCandidate]
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshingProviderIDs: Set<String> = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var refreshIntervalMinutes: Int

    private static let bindingsKey = "localProviderBindings"
    private static let refreshIntervalKey = "refreshIntervalMinutes"
    static let supportedRefreshIntervals = [1, 5, 15, 30, 60]

    private let defaults: UserDefaults
    private let homeDirectory: URL
    private var refreshTask: Task<Void, Never>?
    private var refreshRequested = false

    init(
        defaults: UserDefaults = .standard,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.defaults = defaults
        self.homeDirectory = homeDirectory
        let storedInterval = defaults.integer(forKey: Self.refreshIntervalKey)
        self.refreshIntervalMinutes = Self.supportedRefreshIntervals.contains(storedInterval)
            ? storedInterval
            : 15
        let discovered = LocalAppDiscovery.candidates(homeDirectory: homeDirectory)
        self.candidates = discovered

        if let data = defaults.data(forKey: Self.bindingsKey),
           let stored = try? JSONDecoder().decode([ProviderBinding].self, from: data) {
            self.bindings = Self.normalized(stored)
        } else {
            self.bindings = discovered
                .filter(\.isDetected)
                .enumerated()
                .map {
                    ProviderBinding(
                        provider: $0.element.provider,
                        showInWidget: true,
                        sortOrder: $0.offset
                    )
                }
            persistBindings()
        }

        Task { [weak self] in
            self?.start()
        }
    }

    var unboundCandidates: [LocalProviderCandidate] {
        candidates.filter { candidate in
            !bindings.contains { $0.provider == candidate.provider }
        }
    }

    var menuBarTitle: String {
        guard let remaining = providers.compactMap(\.lowestRemainingPercent).min() else {
            return "--"
        }
        return "\(Int(remaining.rounded()))%"
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(refreshIntervalMinutes * 60))
                await refresh()
            }
        }
    }

    func setRefreshInterval(minutes: Int) {
        guard Self.supportedRefreshIntervals.contains(minutes) else { return }
        refreshIntervalMinutes = minutes
        defaults.set(minutes, forKey: Self.refreshIntervalKey)
        refreshTask?.cancel()
        refreshTask = nil
        start()
    }

    func refresh() async {
        guard !isRefreshing else {
            refreshRequested = true
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshRequested {
                refreshRequested = false
                Task { await self.refresh() }
            }
        }

        let currentBindings = bindings
        var valuesByID: [String: ProviderQuota] = [:]
        await withTaskGroup(of: ProviderQuota.self) { group in
            for binding in currentBindings {
                let reader = binding.provider.makeReader(homeDirectory: homeDirectory)
                group.addTask { await reader.read() }
            }
            for await provider in group {
                valuesByID[provider.id] = provider
            }
        }
        let activeProviderIDs = Set(bindings.map { $0.provider.id })
        providers = currentBindings
            .filter { activeProviderIDs.contains($0.provider.id) }
            .compactMap { valuesByID[$0.provider.id] }
        let refreshDate = Date()
        lastRefresh = refreshDate
        publishWidgetSnapshot(at: refreshDate)
    }

    func refresh(_ provider: LocalProvider) async {
        guard bindings.contains(where: { $0.provider == provider }),
              !refreshingProviderIDs.contains(provider.id) else {
            return
        }

        refreshingProviderIDs.insert(provider.id)
        defer { refreshingProviderIDs.remove(provider.id) }

        let value = await provider.makeReader(homeDirectory: homeDirectory).read()
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = value
        } else {
            providers.append(value)
        }
        providers = bindings.compactMap { binding in
            providers.first { $0.id == binding.provider.id }
        }
        let refreshDate = Date()
        lastRefresh = refreshDate
        publishWidgetSnapshot(at: refreshDate)
    }

    func isRefreshing(_ provider: LocalProvider) -> Bool {
        refreshingProviderIDs.contains(provider.id)
    }

    func add(_ provider: LocalProvider) {
        guard !bindings.contains(where: { $0.provider == provider }) else { return }
        bindings.append(
            ProviderBinding(
                provider: provider,
                showInWidget: true,
                sortOrder: bindings.count
            )
        )
        bindings = Self.normalized(bindings)
        bindingDidChange()
    }

    func remove(_ provider: LocalProvider) {
        bindings.removeAll { $0.provider == provider }
        bindings = Self.normalized(bindings)
        providers.removeAll { $0.id == provider.id }
        bindingDidChange()
    }

    func setShowInWidget(_ showInWidget: Bool, for provider: LocalProvider) {
        guard let index = bindings.firstIndex(where: { $0.provider == provider }) else {
            return
        }
        bindings[index].showInWidget = showInWidget
        bindingDidChange(refresh: false)
    }

    func move(_ provider: LocalProvider, by offset: Int) {
        guard let source = bindings.firstIndex(where: { $0.provider == provider }) else {
            return
        }
        let destination = source + offset
        guard bindings.indices.contains(destination) else { return }
        bindings.swapAt(source, destination)
        bindings = Self.reindexed(bindings)
        providers = bindings.compactMap { binding in
            providers.first { $0.id == binding.provider.id }
        }
        bindingDidChange(refresh: false)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let indexes = source.sorted()
        guard !indexes.isEmpty else { return }

        let moving = indexes.map { bindings[$0] }
        var reordered = bindings
        for index in indexes.reversed() {
            reordered.remove(at: index)
        }
        let removedBeforeDestination = indexes.filter { $0 < destination }.count
        let insertionIndex = max(0, min(reordered.count, destination - removedBeforeDestination))
        reordered.insert(contentsOf: moving, at: insertionIndex)

        bindings = Self.reindexed(reordered)
        providers = bindings.compactMap { binding in
            providers.first { $0.id == binding.provider.id }
        }
        bindingDidChange(refresh: false)
    }

    func candidate(for provider: LocalProvider) -> LocalProviderCandidate? {
        candidates.first { $0.provider == provider }
    }

    func rescanLocalApps() {
        candidates = LocalAppDiscovery.candidates(homeDirectory: homeDirectory)
    }

    private func bindingDidChange(refresh: Bool = true) {
        persistBindings()
        publishWidgetSnapshot(at: Date())
        if refresh {
            Task { await self.refresh() }
        }
    }

    private func publishWidgetSnapshot(at date: Date) {
        let widgetProviderIDs = Set(bindings.filter(\.showInWidget).map { $0.provider.id })
        let widgetContentChanged = SharedQuotaStorage.save(
            providers.filter { widgetProviderIDs.contains($0.id) },
            at: date
        )
#if canImport(WidgetKit)
        guard widgetContentChanged else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "TokenViewerSmallQuotaWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "TokenViewerMediumQuotaWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "TokenViewerPetWidget")
#endif
    }

    private func persistBindings() {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        defaults.set(data, forKey: Self.bindingsKey)
    }

    private static func normalized(_ values: [ProviderBinding]) -> [ProviderBinding] {
        reindexed(values.sorted { $0.sortOrder < $1.sortOrder })
    }

    private static func reindexed(_ values: [ProviderBinding]) -> [ProviderBinding] {
        values
            .enumerated()
            .map {
                ProviderBinding(
                    provider: $0.element.provider,
                    showInWidget: $0.element.showInWidget,
                    sortOrder: $0.offset
                )
            }
    }

    deinit {
        refreshTask?.cancel()
    }
}
