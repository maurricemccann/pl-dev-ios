import SwiftUI

/// Home: the sections the config lists, as a grid of tiles. Content scrolls underneath; the only glass is the
/// floating control row at the bottom, where a thumb reaches it (the inbox chip and Settings).
struct HomeView: View {
    let model: AppModel
    @State private var path: [String] = []
    @State private var showSettings = false
    @State private var showProbes = false
    @State private var showInbox = false
    @State private var showBlocked = false
    @State private var blockedID = ""
    @State private var openTick = 0
    @State private var warnTick = 0
    @State private var sheetTick = 0
    @Namespace private var zoom
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("pldev.motion") private var motion = "full"

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: AppModel) { self.model = model }

    private var reduce: Bool { systemReduce || motion == "reduce" }

    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Home"
    }

    /// Four apps across, as on the Home Screen; two at the accessibility text sizes, where a name needs the room.
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize ? Array(repeating: GridItem(.flexible()), count: 2) : Array(repeating: GridItem(.flexible(), spacing: PLSpace.pad), count: 4)   // the Home Screen's four across
    }

    private var summary: String {
        let count = model.sections.count
        let waiting = model.sections.filter { !$0.readiness.isReady }.count
        var line = count == 1 ? "1 section" : "\(count) sections"
        if waiting > 0 { line += ", \(waiting) not ready" }
        return line
    }

    private var blocked: SectionEntry? { model.sections.first { $0.id == blockedID } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: PLSpace.roomy) {
                    header
                    if let line = model.configError ?? model.lastError {
                        NoteLine(symbol: "exclamationmark.triangle.fill", tint: PLTone.warn, text: line)
                    }
                    if model.sections.isEmpty {
                        EmptyNote(symbol: "square.grid.2x2", title: "Nothing to show yet",
                                  detail: "Your config lists sections this build does not have. Settings and the probes still work.",
                                  actionTitle: "Open Settings") { openSettings() }
                            .padding(.top, PLSpace.block)
                    } else {
                        LazyVGrid(columns: columns, spacing: PLSpace.roomy + PLSpace.pad) {
                            ForEach(model.sections) { entry in
                                tile(entry)
                            }
                        }
                        .animation(PLMotion.spring(reduce: reduce), value: model.sections.map(\.badge))
                    }
                }
                .padding(.horizontal, PLSpace.margin)
                .padding(.top, PLSpace.gap)
                .padding(.bottom, PLSpace.block)
                .environment(\.colorScheme, .dark)   // light text on the wallpaper, as on the Home Screen; pushed screens keep his setting
            }
            .background(Wallpaper(model: model))
            .refreshable { await Poller.shared.refreshAll() }
            .safeAreaInset(edge: .bottom) { controls }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                destination(id)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        .sheet(isPresented: $showProbes) {
            NavigationStack {
                ProbeView(probe: model.probes, showsDone: true)
            }
            .tint(PLTone.accent)
        }
        .sheet(isPresented: $showInbox) {
            InboxSheet(model: model)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert(blocked?.manifest.title ?? "Not ready", isPresented: $showBlocked) {
            Button("Open Settings") { openSettings() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(blocked?.readiness.plDetail ?? "This section cannot open yet.")
        }
        .onChange(of: model.route, initial: true) { _, link in
            follow(link)
        }
        .sensoryFeedback(PLHaptic.open, trigger: openTick)
        .sensoryFeedback(PLHaptic.warning, trigger: warnTick)
        .sensoryFeedback(PLHaptic.select, trigger: sheetTick)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PLSpace.tight) {
            Text(appName)
                .plTitle(.largeTitle)
                .accessibilityAddTraits(.isHeader)
            Text(summary)
                .plFont(.subhead)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, PLSpace.roomy)
    }

    private func tile(_ entry: SectionEntry) -> some View {
        Button {
            open(entry)
        } label: {
            SectionTile(entry: entry)
        }
        .buttonStyle(PressableStyle(reduce: reduce))
        .matchedTransitionSource(id: entry.id, in: zoom)
        .accessibilityHint(entry.readiness.isReady ? "Opens the section" : "Says what the config is missing")
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.app") { open(entry) }
            Button("Probe this section", systemImage: "stethoscope") { probe(entry) }
        }
    }

    /// The floating control layer: the only glass on this screen.
    private var controls: some View {
        HStack(spacing: PLSpace.pad) {
            if model.inboxCount > 0 {
                Button {
                    sheetTick += 1
                    showInbox = true
                } label: {
                    HStack(spacing: PLSpace.gap) {
                        Image(systemName: "tray.full")
                        Text("\(model.inboxCount) waiting")
                            .plFont(.callout, emphasized: true)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, PLSpace.margin)
                    .frame(minHeight: 50)
                    .contentShape(Capsule())
                }
                .glassControl()
                .accessibilityLabel("\(model.inboxCount) items waiting to send")
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .plFont(.callout, emphasized: true)
                    .padding(.horizontal, PLSpace.margin)
                    .frame(minHeight: 50)
                    .contentShape(Capsule())
            }
            .glassControl()
        }
        .padding(.horizontal, PLSpace.margin)
        .padding(.bottom, PLSpace.gap)
        .animation(PLMotion.spring(reduce: reduce), value: model.inboxCount)
    }

    @ViewBuilder
    private func destination(_ id: String) -> some View {
        if let entry = model.sections.first(where: { $0.id == id }) {
            if reduce {
                entry.makeRoot()
            } else {
                entry.makeRoot()
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
            }
        } else {
            EmptyNote(symbol: "questionmark.square.dashed", title: "Not here", detail: "This build does not have that section.")
        }
    }

    // MARK: actions

    private func open(_ entry: SectionEntry) {
        if entry.readiness.isReady {
            openTick += 1
            path = [entry.id]
        } else {
            warnTick += 1
            blockedID = entry.id
            showBlocked = true
        }
    }

    private func openSettings() {
        sheetTick += 1
        showSettings = true
    }

    private func probe(_ entry: SectionEntry) {
        sheetTick += 1
        showProbes = true
        Task { await model.probes.run(section: entry.id) }
    }

    /// Where a link, an intent or a notification wants to go. A section this build lacks (or that is not ready) lands on Home.
    private func follow(_ link: DeepLink?) {
        guard let link else { return }
        model.route = nil
        showProbes = false
        showInbox = false
        switch link {
        case .home:
            showSettings = false
            path = []
        case .settings:
            path = []
            showSettings = true
        case .section(let id, _, _):
            showSettings = false
            guard let entry = model.sections.first(where: { $0.id == id }), entry.readiness.isReady else {
                path = []
                return
            }
            _ = SectionRegistry.section(id)?.handle(link: link, model: model)
            path = [entry.id]
        }
    }
}

/// What is waiting to be sent, said plainly. The items came from the share sheet, Safari or a widget.
struct InboxSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel) { self.model = model }

    var body: some View {
        VStack(spacing: PLSpace.margin) {
            Image(systemName: "tray.full")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(PLTone.accent)
                .accessibilityHidden(true)
            Text(model.inboxCount == 1 ? "1 item waiting" : "\(model.inboxCount) items waiting")
                .plTitle(.title2)
                .accessibilityAddTraits(.isHeader)
            Text(InboxDrain.sendItem == nil
                 ? "They are saved on this iPhone. This build has nowhere to send them yet; they go out when the section that sends them arrives."
                 : "They are saved on this iPhone and go out the next time the connection allows.")
                .plFont(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .plFont(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(PLSpace.margin * 2)
        .tint(PLTone.accent)
        .task {   // the sender exists as soon as Capture can run, not only after its first refresh
            if model.sections.contains(where: { $0.id == "capture" && $0.readiness.isReady }) {
                CaptureSection.install(model: model)
                await model.drainInbox()
            }
        }
    }
}
