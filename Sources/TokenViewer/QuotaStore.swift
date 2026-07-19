import Combine
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var providers: [ProviderQuota] = []
    @Published private(set) var bindings: [ProviderBinding]
    @Published private(set) var apiProviders: [APIProviderConfig]
    @Published private(set) var candidates: [LocalProviderCandidate]
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshingProviderIDs: Set<String> = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var refreshIntervalMinutes: Int
    @Published private(set) var localDataAccessEnabled: Bool

    private static let bindingsKey = "localProviderBindings"
    private static let apiProvidersKey = "apiProviderConfigs"
    private static let refreshIntervalKey = "refreshIntervalMinutes"
    private static let localDataAccessEnabledKey = "localDataAccessEnabled"
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
        let localDataAccessEnabled = defaults.bool(forKey: Self.localDataAccessEnabledKey)
        self.localDataAccessEnabled = localDataAccessEnabled
        let discovered = localDataAccessEnabled
            ? LocalAppDiscovery.candidates(homeDirectory: homeDirectory)
            : LocalProvider.allCases.map {
                LocalProviderCandidate(
                    provider: $0,
                    isDetected: false,
                    detectionDetail: "本地数据访问已关闭"
                )
            }
        self.candidates = discovered

        var needsInitialBindingsPersist = false
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
            needsInitialBindingsPersist = true
        }

        if let data = defaults.data(forKey: Self.apiProvidersKey),
           let stored = try? JSONDecoder().decode([APIProviderConfig].self, from: data) {
            self.apiProviders = Self.normalizedAPI(stored)
        } else {
            self.apiProviders = []
        }

        if needsInitialBindingsPersist {
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
        guard localDataAccessEnabled || !apiProviders.isEmpty else { return }
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

    func setLocalDataAccessEnabled(_ enabled: Bool) {
        guard localDataAccessEnabled != enabled else { return }
        localDataAccessEnabled = enabled
        defaults.set(enabled, forKey: Self.localDataAccessEnabledKey)

        if enabled {
            rescanLocalApps()
            start()
            Task { await refresh() }
        } else {
            providers = providers.filter { $0.source == .api }
            candidates = LocalProvider.allCases.map {
                LocalProviderCandidate(
                    provider: $0,
                    isDetected: false,
                    detectionDetail: "本地数据访问已关闭"
                )
            }
            if apiProviders.isEmpty {
                refreshTask?.cancel()
                refreshTask = nil
            }
            publishWidgetSnapshot(at: Date())
        }
    }

    func refresh() async {
        guard localDataAccessEnabled || !apiProviders.isEmpty else { return }
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

        var valuesByID: [String: ProviderQuota] = [:]
        await withTaskGroup(of: ProviderQuota.self) { group in
            if localDataAccessEnabled {
                for binding in bindings {
                    let reader = binding.provider.makeReader(homeDirectory: homeDirectory, customDataPath: binding.customDataPath)
                    group.addTask { await reader.read() }
                }
            }
            for config in apiProviders {
                let apiKey = KeychainHelper.get(config.apiKeyID)
                let reader = APIQuotaReader(config: config, apiKey: apiKey)
                group.addTask { await reader.read() }
            }
            for await provider in group {
                valuesByID[provider.id] = provider
            }
        }

        var merged: [ProviderQuota] = []
        if localDataAccessEnabled {
            for binding in bindings {
                if let value = valuesByID[binding.provider.id] {
                    merged.append(value)
                }
            }
        }
        for config in apiProviders {
            if let value = valuesByID[config.quotaID] {
                merged.append(value)
            }
        }
        providers = merged
        let refreshDate = Date()
        lastRefresh = refreshDate
        publishWidgetSnapshot(at: refreshDate)
    }

    func refresh(_ provider: LocalProvider) async {
        guard localDataAccessEnabled,
              bindings.contains(where: { $0.provider == provider }),
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

    func refreshAPI(_ config: APIProviderConfig) async {
        guard apiProviders.contains(where: { $0.id == config.id }),
              !refreshingProviderIDs.contains(config.quotaID) else {
            return
        }

        refreshingProviderIDs.insert(config.quotaID)
        defer { refreshingProviderIDs.remove(config.quotaID) }

        let apiKey = KeychainHelper.get(config.apiKeyID)
        let value = await APIQuotaReader(config: config, apiKey: apiKey).read()
        if let index = providers.firstIndex(where: { $0.id == config.quotaID }) {
            providers[index] = value
        } else {
            providers.append(value)
        }
        providers = reorderBySource()
        let refreshDate = Date()
        lastRefresh = refreshDate
        publishWidgetSnapshot(at: refreshDate)
    }

    func isRefreshing(_ config: APIProviderConfig) -> Bool {
        refreshingProviderIDs.contains(config.quotaID)
    }

    func isRefreshing(_ provider: LocalProvider) -> Bool {
        refreshingProviderIDs.contains(provider.id)
    }

    func add(_ provider: LocalProvider, customDataPath: String? = nil) {
        guard !bindings.contains(where: { $0.provider == provider }) else { return }
        bindings.append(
            ProviderBinding(
                provider: provider,
                showInWidget: true,
                sortOrder: bindings.count,
                customDataPath: customDataPath
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

    func setCustomDataPath(_ customDataPath: String?, for provider: LocalProvider) {
        guard let index = bindings.firstIndex(where: { $0.provider == provider }) else {
            return
        }
        bindings[index].customDataPath = customDataPath
        bindingDidChange()
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
        guard localDataAccessEnabled else { return }
        candidates = LocalAppDiscovery.candidates(homeDirectory: homeDirectory)
    }

    // MARK: - API Providers

    func addAPIProvider(
        name: String,
        baseURL: URL,
        apiKey: String,
        format: APIFormat,
        quotaPath: String,
        template: APIProviderTemplate,
        useLocalOAuth: Bool
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = quotaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let keyID = "apikey.\(UUID().uuidString)"
        KeychainHelper.set(apiKey, for: keyID)

        let config = APIProviderConfig(
            name: trimmedName,
            baseURL: baseURL,
            apiKeyID: keyID,
            format: format,
            quotaPath: trimmedPath.isEmpty ? "/v1/usage" : trimmedPath,
            template: template,
            useLocalOAuth: false,
            showInWidget: true,
            sortOrder: apiProviders.count
        )
        apiProviders.append(config)
        apiProviders = Self.normalizedAPI(apiProviders)
        apiProviderDidChange()
        start()
    }

    func updateAPIProvider(
        _ config: APIProviderConfig,
        name: String,
        baseURL: URL,
        apiKey: String?,
        format: APIFormat,
        quotaPath: String,
        template: APIProviderTemplate,
        useLocalOAuth: Bool
    ) {
        guard let index = apiProviders.firstIndex(where: { $0.id == config.id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = quotaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var updated = config
        updated.name = trimmedName
        updated.baseURL = baseURL
        updated.format = format
        updated.quotaPath = trimmedPath.isEmpty ? "/v1/usage" : trimmedPath
        updated.template = template
        updated.useLocalOAuth = false

        if let newKey = apiKey, !newKey.isEmpty {
            KeychainHelper.set(newKey, for: config.apiKeyID)
        }

        apiProviders[index] = updated
        apiProviders = Self.normalizedAPI(apiProviders)
        apiProviderDidChange()
    }

    func removeAPIProvider(_ config: APIProviderConfig) {
        apiProviders.removeAll { $0.id == config.id }
        providers.removeAll { $0.id == config.quotaID }
        KeychainHelper.delete(config.apiKeyID)
        apiProviders = Self.normalizedAPI(apiProviders)
        apiProviderDidChange()
    }

    func setShowInWidget(_ showInWidget: Bool, for config: APIProviderConfig) {
        guard let index = apiProviders.firstIndex(where: { $0.id == config.id }) else { return }
        apiProviders[index].showInWidget = showInWidget
        apiProviderDidChange(refresh: false)
    }

    func moveAPIProvider(_ config: APIProviderConfig, by offset: Int) {
        guard let source = apiProviders.firstIndex(where: { $0.id == config.id }) else { return }
        let destination = source + offset
        guard apiProviders.indices.contains(destination) else { return }
        apiProviders.swapAt(source, destination)
        apiProviders = Self.reindexedAPI(apiProviders)
        providers = reorderBySource()
        apiProviderDidChange(refresh: false)
    }

    func apiProvider(withID id: UUID) -> APIProviderConfig? {
        apiProviders.first { $0.id == id }
    }

    private func apiProviderDidChange(refresh: Bool = true) {
        persistAPIProviders()
        publishWidgetSnapshot(at: Date())
        if refresh {
            Task { await self.refresh() }
        }
    }

    private func reorderBySource() -> [ProviderQuota] {
        var reordered: [ProviderQuota] = []
        if localDataAccessEnabled {
            for binding in bindings {
                if let value = providers.first(where: { $0.id == binding.provider.id }) {
                    reordered.append(value)
                }
            }
        }
        for config in apiProviders {
            if let value = providers.first(where: { $0.id == config.quotaID }) {
                reordered.append(value)
            }
        }
        return reordered
    }

    private func bindingDidChange(refresh: Bool = true) {
        persistBindings()
        publishWidgetSnapshot(at: Date())
        if refresh {
            Task { await self.refresh() }
        }
    }

    private func publishWidgetSnapshot(at date: Date) {
        let localWidgetIDs = Set(bindings.filter(\.showInWidget).map { $0.provider.id })
        let apiWidgetIDs = Set(apiProviders.filter(\.showInWidget).map { $0.quotaID })
        let widgetIDs = localWidgetIDs.union(apiWidgetIDs)
        let widgetContentChanged = SharedQuotaStorage.save(
            providers.filter { widgetIDs.contains($0.id) },
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

    private func persistAPIProviders() {
        guard let data = try? JSONEncoder().encode(apiProviders) else { return }
        defaults.set(data, forKey: Self.apiProvidersKey)
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

    private static func normalizedAPI(_ values: [APIProviderConfig]) -> [APIProviderConfig] {
        reindexedAPI(values.sorted { $0.sortOrder < $1.sortOrder })
    }

    private static func reindexedAPI(_ values: [APIProviderConfig]) -> [APIProviderConfig] {
        values
            .enumerated()
            .map { index, config in
                var updated = config
                updated.sortOrder = index
                return updated
            }
    }

    deinit {
        refreshTask?.cancel()
    }
}
