import SwiftUI

/// Home: the sections the config lists, as a grid of tiles. Content scrolls underneath; the only glass is the
/// floating control row at the bottom, where a thumb reaches it (the inbox chip and Settings).
struct HomeView: View {
    let model: AppModel
    @State private var path: [String] = []
    @State private var showSettings = false
    @State private var rising = RisingScale.shared
    @State private var left = false
    @Environment(\.scenePhase) private var scenePhase
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
    @AppStorage("pldev.theme") private var theme = "system"
    @AppStorage("pldev.themeId") private var themeId = ""
    @AppStorage("pldev.styleMark") private var mark = ""

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: AppModel) { self.model = model }

    private var reduce: Bool { systemReduce || motion == "reduce" }

    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Home"
    }

    /// Three across (both reviews 11-14: four cut "Colour Survey" and "Congregation" short); two at the accessibility text sizes.
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize ? Array(repeating: GridItem(.flexible()), count: 2) : Array(repeating: GridItem(.flexible(), spacing: PLSpace.pad), count: 3)
    }

    private var summary: String {
        let shown = model.sections.filter { $0.id != "status" }   // Status is a Today widget, not a tile (it read "12 sections" over 11)
        let count = shown.count
        let waiting = shown.filter { !$0.readiness.isReady }.count
        var line = count == 1 ? "1 section" : "\(count) sections"
        if waiting > 0 { line += ", \(waiting) not ready" }
        return line
    }

    @State private var showWidgetHelp = false
    @SceneStorage("home.page") private var page = HomeView.startPage   // opens on the apps, like the first Home Screen page
    private static var startPage: Int {
        #if targetEnvironment(simulator)
        if let p = UserDefaults.standard.object(forKey: "simHomePage") { return Int("\(p)") ?? 1 }   // screens workflow only
        #endif
        return 1
    }

    private var appsPage: some View {
        VStack(alignment: .leading, spacing: PLSpace.roomy) {
            header
            RisingPanel()
            if let line = model.configError ?? model.lastError {
                NoteLine(symbol: "exclamationmark.triangle.fill", tint: PLTone.warn, text: line)
            }
            if model.sections.isEmpty {
                EmptyNote(symbol: "square.grid.2x2", title: ThemeFeed.text("home.empty", "Nothing to show yet"),
                          detail: "Your config lists sections this build does not have. Settings and the probes still work.",
                          actionTitle: "Open Settings") { openSettings() }
                    .padding(.top, PLSpace.block)
            } else {
                LazyVGrid(columns: columns, spacing: PLSpace.roomy + PLSpace.pad) {
                    ForEach(model.sections.filter { $0.id != "status" }) { entry in tile(entry) }   // Status is a widget on the Today page
                }
                .animation(PLMotion.spring(reduce: reduce), value: model.sections.map(\.badge))
            }
            // the services he signs in to, as a row under the apps (his ruling 11-14: the Backend page folds in here)
            BackendPage(columns: columns, reduce: reduce, embedded: true)
        }
        .padding(.horizontal, PLSpace.margin).padding(.top, PLSpace.gap).padding(.bottom, PLSpace.block)
    }

    /// The Today page: the date the way the iPhone's Today View heads it, then the widgets (status, the PC, the house).
    private var todayPage: some View {
        VStack(alignment: .leading, spacing: PLSpace.roomy) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide)).plFont(.subhead, emphasized: true).foregroundStyle(Color.primary.opacity(0.85))
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                Text(Date.now, format: .dateTime.month(.wide).day()).plTitle(.largeTitle).accessibilityAddTraits(.isHeader)
            }
            .padding(.top, PLSpace.roomy)
            EarnedBackdrop(model: model)   // his own kept pieces on a panel under the date (his pick N13; his note 11-14: not faint, a panel)
            HomeDashboard(model: model)
            // Moonlitt's flow on Mobbin (11-13): the widget page ends by showing how to put them on your phone
            Button { showWidgetHelp = true } label: {
                HStack {
                    Label("Add PL DEV widgets", systemImage: "rectangle.3.group").plFont(.callout, emphasized: true)
                    Spacer()
                    Image(systemName: "chevron.right").font(Font.pl(.caption).weight(.bold)).foregroundStyle(.secondary)
                }
                .padding(14)
                .plGlass(in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showWidgetHelp) { WidgetHowTo() }
        }
        // room under the last card for the page dots and the Settings pill that float over it (his screenshot 11-14: the card sat cut off beneath them)
        .padding(.horizontal, PLSpace.margin).padding(.top, PLSpace.gap).padding(.bottom, 120)
    }

    /// The three pages' names; the feed's copy may rename them (config over the air, S353·7b1e).
    private static var pageNames: [String] {
        [ThemeFeed.text("home.page.today", "Today"), ThemeFeed.text("home.page.apps", "Apps"), ThemeFeed.text("home.page.pulse", "Pulse")]
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in   // named, not dots (Codex 11-14, his pick N6)
                Text(Self.pageNames[i]).font(Font.pl(.footnote).weight(page == i ? .bold : .regular))
                    .foregroundStyle(Color.primary.opacity(page == i ? 0.95 : 0.5))
                    .frame(minHeight: 32).contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy) { page = i } }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .accessibilityElement().accessibilityLabel("\(Self.pageNames[min(max(page, 0), 2)]), page \(min(max(page, 0), 2) + 1) of 3")
        .accessibilityAdjustableAction { d in withAnimation { page = min(max(page + (d == .increment ? 1 : -1), 0), 2) } }
    }

    private var blocked: SectionEntry? { model.sections.first { $0.id == blockedID } }

    var body: some View {
        NavigationStack(path: $path) {
            // Two pages, like the iPhone (his ask 11-13): the apps first, and to their left the Today page of widgets
            // (Apple's Today View: swipe right from the first page). Page dots sit above the controls.
            TabView(selection: $page) {
                ScrollView { todayPage }.scrollDismissesKeyboard(.interactively).tag(0)
                ScrollView { appsPage }.scrollDismissesKeyboard(.interactively).tag(1)
                ScrollView { PerformancePage(model: model) }.scrollDismissesKeyboard(.interactively).tag(2)   // Pulse (his ruling 11-14, Gemini's three pages): reach, money, the machine
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onAppear { if page > 2 { page = 2 } }   // a page remembered from the four-page Home (before 11-14) lands on Pulse
            .environment(\.colorScheme, themeId.isEmpty || theme != "light" ? .dark : .light)   // a light theme's Home is light too
            .background {
                ZStack {
                    Wallpaper(model: model)
                    if page == 2 { MoneyGround().transition(.opacity) }   // Pulse wears his money-goes-up glyph field (11-14)
                }
                .animation(.easeInOut(duration: 0.35), value: page)
            }
            .refreshable { await Poller.shared.refreshAll() }
            // one bar like the Home Screen dock (his note 11-14 with Aqara's tab bar on Cosmos: the dots and Settings floated apart and
            // cut through the screen, and sat high): dots left, Settings right, one glass bar, close to the home indicator
            .overlay(alignment: .bottomTrailing) { RisingBuddy() }   // above the bar below, which is inset outside this
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                destination(id)
            }
        }
        .task {
            await rising.firstWear()
            rising.asking = true
            if rising.reminds { _ = await NotificationHub.shared.authorize() }   // the system asks once; then the three are set
            rising.scheduleReminders()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { left = true }   // only a real leave counts, not Face ID or a pulled-down notification list
            if phase == .active, left {
                left = false
                rising.asking = true
                Task { await rising.wearIfDue(); rising.scheduleReminders() }
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
            HStack(spacing: PLSpace.gap) {
                Text(appName)
                    .plTitle(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                if !mark.isEmpty { PLIcon.symbol(mark).resizable().scaledToFit().frame(width: 30, height: 30).foregroundStyle(PLTone.accent).accessibilityHidden(true) }
            }
            .lineLimit(1).minimumScaleFactor(0.5).padding(.trailing, 170)   // wide pack faces shrink instead of running under the curve
            Text(summary)
                .plFont(.subhead, emphasized: true)
                .foregroundStyle(Color.primary.opacity(0.88))
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1)   // reads over the wallpaper's lines (Gemini review, checked 11-13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { RisingCurve() }   // his curve beside the title is the check-in (11-25)
        .padding(.top, PLSpace.roomy)
    }

    private func tile(_ entry: SectionEntry) -> some View {
        Button {
            open(entry)
        } label: {
            SectionTile(entry: entry)
        }
        .buttonStyle(PressableStyle(reduce: reduce))
        .accessibilityHint(entry.readiness.isReady ? "Opens the section" : "Says what the config is missing")
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.app") { open(entry) }
            Button("Probe this section", systemImage: "stethoscope") { probe(entry) }
        }
    }

    /// The floating control layer: the only glass on this screen.
    /// The floating control layer, drawn as the Home Screen's Dock: one glass container (so the pieces merge and morph),
    /// tinted with the iOS 27 kit's Dock fill, glass label colours on it. The only glass on this screen.
    private var controls: some View {
        GlassEffectContainer(spacing: PLSpace.pad) {
            HStack(spacing: PLSpace.pad) {
                pageDots
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
                        .foregroundStyle(IOS27.LabelsLiquidGlass.primary)
                        .padding(.horizontal, PLSpace.margin)
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(model.inboxCount) items waiting to send")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .plFont(.callout, emphasized: true)
                        .foregroundStyle(IOS27.LabelsLiquidGlass.primary)
                        .padding(.horizontal, PLSpace.pad)
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
            .plGlass(tint: IOS27.Glass.dock.tint, in: RoundedRectangle(cornerRadius: 30 * PLStyle.radius, style: .continuous))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, -14)   // nearer the home indicator, as the dock sits
        .animation(PLMotion.spring(reduce: reduce), value: model.inboxCount)
    }

    @ViewBuilder
    private func destination(_ id: String) -> some View {
        if let entry = model.sections.first(where: { $0.id == id }) {
            // the standard push: the zoom transition let a quick swipe down anywhere on the screen close the section (his report 11-13)
            entry.makeRoot().plGround()
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
                // a cold launch from a link can arrive before the config has made the section ready: wait up to 3 s, then
                // say why instead of landing on Home in silence (11-14: section/practice landed Home in the screens run)
                guard model.sections.contains(where: { $0.id == id }) else { return }
                Task { @MainActor in
                    for _ in 0..<6 {
                        try? await Task.sleep(for: .milliseconds(500))
                        if model.sections.first(where: { $0.id == id })?.readiness.isReady == true { model.route = link; return }
                    }
                    warnTick += 1; blockedID = id; showBlocked = true
                }
                return
            }
            _ = SectionRegistry.section(id)?.handle(link: link, model: model)
            // a link followed from inside another section stacks on it, so Back returns there (his note 11-14: Waiting's rows
            // opened House and Back went Home, not to Capture); never deeper than two
            if let here = path.last, here != entry.id { path = [here, entry.id] } else { path = [entry.id] }
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
                .font(Font.pl(.largeTitle))
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


/// How to put PL DEV's widgets on the Home Screen and the Lock Screen, in iOS 27's own steps (Apple's iPhone guide).
private struct WidgetHowTo: View {
    @State private var where_ = 0
    @Environment(\.dismiss) private var dismiss
    private let home = ["Touch and hold an empty part of the Home Screen until the apps jiggle.", "Tap Edit at the top, then Add Widget.",
                        "Search PL DEV, pick a widget (House, Snapshot, Practice and the rest) and a size, then Add Widget.",
                        "To see them all in one place, swipe right on your first Home Screen page: that is Today View."]
    private let lock = ["Touch and hold the Lock Screen until Customize shows, then tap Customize and Lock Screen.",
                        "Tap the space under the clock to open the widget tray.", "Search PL DEV and add House, Practice or the Status ring.",
                        "Tap Done. Live Activities (the shift, renders) show on the Lock Screen on their own."]
    var body: some View {
        NavigationStack {
            List {
                Picker("Where", selection: $where_) { Text("Home Screen").tag(0); Text("Lock Screen").tag(1) }.pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                ForEach(Array((where_ == 0 ? home : lock).enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)").font(Font.pl(.headline).monospacedDigit()).foregroundStyle(PLTone.accent).frame(width: 22)
                        Text(step)
                    }
                }
            }
            .navigationTitle("Add widgets")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
