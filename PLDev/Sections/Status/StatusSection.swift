import SwiftUI
import UserNotifications

/// The placeholder section, and the pattern every later section follows: a manifest, a root view, and a refresh.
/// It shows each configured address as reachable or not and each key as Set or Not set. It needs no key itself.
@MainActor enum StatusSection: PLSection {
    static let manifest = SectionManifest(id: "status", title: "Status", symbol: "waveform.path.ecg")

    /// Address name -> a health path to GET. This build knows none, so every address is asked with a HEAD of its base.
    static let healthPaths: [String: String] = ["cron": "health"]

    static let state = StatusModel()

    static func makeRoot(model: AppModel) -> AnyView {
        AnyView(StatusView(model: model, state: state))
    }

    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }   // the shell already has one probe per address

    static func settingsRows(model: AppModel) -> AnyView? { nil }

    static func notificationCategories() -> Set<UNNotificationCategory> { [] }

    static func handle(link: DeepLink, model: AppModel) -> Bool { true }   // one screen: nothing deeper to open

    static func refresh(model: AppModel) async -> SectionRefresh {
        await state.check(model: model)
        return SectionRefresh(badge: state.downCount > 0 ? state.downCount : nil, notify: [])
    }
}

/// What the Status screen shows. The last answers stay on screen while new ones come in.
@MainActor @Observable final class StatusModel {
    private(set) var reach: [String: OriginReach] = [:]
    private(set) var checkedAt: Date?
    private(set) var checking = false

    var downCount: Int {
        reach.values.filter { if case .down = $0 { return true } else { return false } }.count
    }

    /// Asks every configured address at once. One slow address does not hold the others back.
    func check(model: AppModel) async {
        guard !checking, let config = model.config else { return }
        checking = true
        defer { checking = false }
        let names = config.origins.keys.sorted()
        for name in reach.keys where !names.contains(name) { reach[name] = nil }
        await withTaskGroup(of: (String, OriginReach).self) { group in
            for name in names {
                group.addTask { (name, await model.reach(name)) }
            }
            for await (name, answer) in group {
                reach[name] = answer
            }
        }
        checkedAt = Date()
    }
}

struct StatusView: View {
    let model: AppModel
    let state: StatusModel
    @State private var doneTick = 0

    init(model: AppModel, state: StatusModel) {
        self.model = model
        self.state = state
    }

    private var origins: [String] { model.config?.origins.keys.sorted() ?? [] }
    private var keyNames: [String] { model.config?.keys.keys.sorted() ?? [] }

    private var allDown: Bool {
        !origins.isEmpty && state.checkedAt != nil && state.downCount == origins.count
    }

    var body: some View {
        List {
            if allDown {
                Section {
                    NoteLine(symbol: "wifi.slash", tint: PLTone.warn, text: "Nothing answered. This iPhone may be offline. Pull down to try again.")
                }
            }
            Section {
                if origins.isEmpty {
                    EmptyNote(symbol: "network.slash", title: "No addresses", detail: "Your config names no address yet.")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(origins, id: \.self) { name in
                        if let answer = state.reach[name] {
                            originRow(name, answer)
                                .listRowBackground(rowWash(answer))
                        } else {
                            SkeletonRow()
                        }
                    }
                }
            } header: {
                Text("Addresses").plFont(.footnote)
            } footer: {
                Text(footer).plFont(.footnote)
            }
            Section {
                if keyNames.isEmpty {
                    Text("Your config holds no keys.")
                        .plFont(.body)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(keyNames, id: \.self) { name in
                        KeyRow(name: name, isSet: model.config?.key(name) != nil)
                            .listRowBackground(model.config?.key(name) != nil ? nil : PLTone.warn.opacity(0.10))   // a key the config lists but leaves empty
                    }
                }
            } header: {
                Text("Keys").plFont(.footnote)
            } footer: {
                Text("A key shows as Set when the config gives it a value. The value itself is never shown.")
                    .plFont(.footnote)
            }
        }
        .refreshable { await refresh() }
        .task {
            if state.checkedAt == nil { await refresh() }   // first visit: ask once; later visits show the last answers at once
        }
        .plScreenTitle("Status")
        .sensoryFeedback(PLHaptic.commit, trigger: doneTick)
    }

    private var footer: String {
        guard let at = state.checkedAt else { return "Asking each address for an answer. Only its name is shown, never where it is." }
        return "Checked at \(at.formatted(date: .omitted, time: .shortened)). Any answer counts as reachable. Pull down to ask again."
    }

    /// A faint wash of the row's state (his note 11-14): green when the address answers, red when it does not, none while unknown.
    private func rowWash(_ answer: OriginReach) -> Color? {
        switch answer { case .up: return PLTone.good.opacity(0.10); case .down: return PLTone.bad.opacity(0.12); case .unknown, .checking: return nil }
    }

    private func refresh() async {
        await state.check(model: model)
        model.setBadge(state.downCount > 0 ? state.downCount : nil, for: StatusSection.manifest.id)
        doneTick += 1
    }

    private func originRow(_ name: String, _ answer: OriginReach) -> some View {
        let (symbol, tint, words): (String, Color, String) = {
            switch answer {
            case .up(let status): return ("checkmark.circle.fill", PLTone.good, "Reachable (\(status))")
            case .down(let reason): return ("xmark.circle.fill", PLTone.bad, reason)
            case .unknown, .checking: return ("circle.dashed", PLTone.quiet, "Not asked yet")
            }
        }()
        return VStack(alignment: .leading, spacing: PLSpace.tight) {
            Text(name)
                .plFont(.body)
            NoteLine(symbol: symbol, tint: tint, text: words)
        }
        .padding(.vertical, PLSpace.hair)
        .accessibilityElement(children: .combine)
    }
}
