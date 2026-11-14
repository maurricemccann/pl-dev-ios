import SwiftUI

/// Settings: how the app looks, when it may notify, which keys the sections need, each section's own rows,
/// the debug log, the probes, forget the config, about. Every switch says in plain words what it does.
struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pldev.theme") private var theme = "system"
    @AppStorage("pldev.font") private var font = "system"
    @AppStorage("pldev.glassBlur") private var glassBlur = true
    @AppStorage("pldev.glassClear") private var glassClear = false
    @AppStorage("pldev.tileStrength") private var tileStrength = 0.5
    @AppStorage("pldev.textSize") private var textSize = 100.0
    @AppStorage("pldev.motion") private var motion = "full"
    @AppStorage("pldev.notify") private var notify = false
    @AppStorage("pldev.quietFrom") private var quietFrom = ""
    @AppStorage("pldev.quietTo") private var quietTo = ""
    @AppStorage("pldev.debug") private var debug = false
    @State private var confirmForget = false
    @State private var notifyRefused = false
    @State private var typeTick = 0
    @State private var warnTick = 0

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: AppModel) { self.model = model }

    private var version: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return (value ?? "1") + " (" + (build ?? "?") + ")"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: PLSpace.pad) {
                        Image(systemName: "circle.circle")
                            .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PL DEV").font(.title3.weight(.semibold))
                            Text(model.config == nil ? "No config loaded" : "\(model.sections.filter { $0.readiness.isReady }.count) of \(model.sections.count) apps ready")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("Version \(version)").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                HouseRows()
                appearance
                notifications
                keys
                sections
                diagnostics
                forget
                about
            }
            .plScreenTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done").plFont(.body, emphasized: true)
                    }
                }
            }
            .confirmationDialog("Forget this config?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget config", role: .destructive) {
                    model.forgetConfig()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every address and key is removed from this iPhone. Load the config file again to use the app. Items waiting to send are kept.")
            }
        }
        .tint(PLTone.accent)
        .preferredColorScheme(PLAppearance.scheme(theme))
        .sensoryFeedback(PLHaptic.select, trigger: [theme, font, motion])
        .sensoryFeedback(PLHaptic.select, trigger: [glassBlur, glassClear, notify, debug])
        .sensoryFeedback(PLHaptic.select, trigger: typeTick)
        .sensoryFeedback(PLHaptic.warning, trigger: warnTick)
    }

    // MARK: Appearance

    private var appearance: some View {
        Section {
            Picker(selection: $theme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            } label: {
                SettingsLabel("Theme", "circle.lefthalf.filled", IOS27.SystemColors.indigo)
            }
            Picker(selection: $font) {
                Text("System").tag("system")
                Text("Jost").tag("jost")
                Text("Courier Prime").tag("courier")
            } label: {
                SettingsLabel("Text face", "textformat", IOS27.SystemColors.blue)
            }
            VStack(alignment: .leading, spacing: PLSpace.tight) {
                SettingsLabel("Text size: \(Int(textSize)) %", "textformat.size", IOS27.SystemColors.blue)
                Slider(value: $textSize, in: 90...130, step: 5) {
                    Text("Text size")
                } minimumValueLabel: {
                    Image(systemName: "textformat.size.smaller").accessibilityHidden(true)
                } maximumValueLabel: {
                    Image(systemName: "textformat.size.larger").accessibilityHidden(true)
                }
                .accessibilityValue("\(Int(textSize)) percent")
            }
            toggleRow("Glass controls", "The floating buttons use Apple\u{2019}s glass. Off draws them solid.", isOn: $glassBlur, icon: ("drop.halffull", IOS27.SystemColors.cyan))
            toggleRow("See-through glass", "A clearer glass that shows more of what is behind it.", isOn: $glassClear, icon: ("circle.dotted", IOS27.SystemColors.teal))
                .disabled(!glassBlur)
            VStack(alignment: .leading, spacing: PLSpace.tight) {
                SettingsLabel("Wallpaper curves", "scribble.variable", IOS27.SystemColors.orange)
                Slider(value: $tileStrength, in: 0...1) {
                    Text("Tile strength")
                }
                .accessibilityValue("\(Int(tileStrength * 100)) percent")
            }
            Picker(selection: $motion) {
                Text("Full").tag("full")
                Text("Reduced").tag("reduce")
            } label: {
                SettingsLabel("Motion", "figure.walk.motion", IOS27.SystemColors.green)
            }
            Button {
                ThemePack.shared.load()
                typeTick += 1
            } label: {
                LabeledContent { Text(ThemePack.shared.isLoaded ? "Loaded" : "None") } label: { SettingsLabel("Theme pack", "paintpalette", IOS27.SystemColors.pink) }
            }
            .accessibilityHint("Reads the theme pack from the app\u{2019}s folder again")
        } header: {
            Text("Appearance").plFont(.footnote)
        } footer: {
            Text(themeFooter).plFont(.footnote)
        }
    }

    private var themeFooter: String {
        var text = "Text size multiplies on top of the iPhone\u{2019}s own text size. Wallpaper curves is how strongly his curve tile shows behind Home. Reduced motion swaps springs and the zoom for short fades; the iPhone\u{2019}s Reduce Motion setting does the same. A theme pack is optional: put theme.json (and the font or tile it names) in this app\u{2019}s folder in Files, then tap Theme pack."
        if let problem = ThemePack.shared.problem { text += " " + problem }
        return text
    }

    // MARK: Notifications

    private var notifications: some View {
        Section {
            toggleRow("Notifications", "Sections may show a notice when something needs you. Off by default.", isOn: $notify, icon: ("bell.badge.fill", IOS27.SystemColors.red))
                .onChange(of: notify) { _, on in
                    guard on else { return }
                    Task {
                        if await NotificationHub.shared.authorize() {
                            notifyRefused = false
                        } else {
                            notify = false
                            notifyRefused = true
                            warnTick += 1
                        }
                    }
                }
            if notify {
                ForEach(NotificationHub.types, id: \.self) { type in
                    Toggle(isOn: typeSwitch(type)) {
                        Text(AppleWatch.label(for: type)).plFont(.body)
                    }
                }
                toggleRow("Quiet hours", "No notices between the two times. They are not kept for later.", isOn: quietOn, icon: ("moon.fill", IOS27.SystemColors.indigo))
                if quietOn.wrappedValue {
                    DatePicker(selection: time($quietFrom, fallback: "22:00"), displayedComponents: .hourAndMinute) {
                        Text("From").plFont(.body)
                    }
                    DatePicker(selection: time($quietTo, fallback: "07:00"), displayedComponents: .hourAndMinute) {
                        Text("To").plFont(.body)
                    }
                }
            }
        } header: {
            Text("Notifications").plFont(.footnote)
        } footer: {
            Text(notifyRefused
                 ? "Notifications are off for this app in the iPhone\u{2019}s Settings. Turn them on there first."
                 : "Notices are made on this iPhone when the app refreshes; nothing is pushed to it. Each section adds its own kinds here.")
                .plFont(.footnote)
        }
    }

    /// A per-type switch. Unset means on.
    private func typeSwitch(_ type: String) -> Binding<Bool> {
        let key = "pldev.notify." + type
        return Binding(
            get: {
                _ = typeTick
                return UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
            },
            set: { on in
                UserDefaults.standard.set(on, forKey: key)
                typeTick += 1
            })
    }

    private var quietOn: Binding<Bool> {
        Binding(
            get: { Quiet.minutes(quietFrom) != nil && Quiet.minutes(quietTo) != nil },
            set: { on in
                quietFrom = on ? "22:00" : ""
                quietTo = on ? "07:00" : ""
            })
    }

    /// "HH:mm" in the settings store, shown and set as a time of day.
    private func time(_ stored: Binding<String>, fallback: String) -> Binding<Date> {
        Binding(
            get: {
                let minutes = Quiet.minutes(stored.wrappedValue) ?? Quiet.minutes(fallback) ?? 0
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                stored.wrappedValue = Quiet.text((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            })
    }

    // MARK: Keys and sections

    private var keys: some View {
        Section {
            let names = model.neededKeys
            if names.isEmpty {
                Text("No section in this build needs a key.")
                    .plFont(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(names, id: \.self) { name in
                    KeyRow(name: name, isSet: model.config?.key(name) != nil)
                }
            }
        } header: {
            Text("Keys").plFont(.footnote)
        } footer: {
            Text("Keys come from your config file and stay in this iPhone\u{2019}s Keychain. Their values are never shown. To change one, edit the file and load it again.")
                .plFont(.footnote)
        }
    }

    private var sections: some View {
        Section {
            ForEach(SectionRegistry.all.map { $0.manifest }) { manifest in
                let readiness = model.config.map { manifest.readiness(in: $0) } ?? .notListed
                HStack(spacing: PLSpace.pad) {
                    Image(systemName: manifest.symbol)
                        .foregroundStyle(readiness.isReady ? PLTone.accent : PLTone.quiet)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    ValueRow(label: manifest.title, value: readiness.plNote ?? "Ready")
                }
                if let rows = SectionRegistry.section(manifest.id)?.settingsRows(model: model) {
                    rows
                }
            }
        } header: {
            Text("Sections").plFont(.footnote)
        } footer: {
            Text("Which sections show on Home, and in what order, is set by the list in your config.")
                .plFont(.footnote)
        }
    }

    // MARK: Debug and probes

    private var diagnostics: some View {
        Section {
            toggleRow("Debug", "Sends what the app does (never a key or an address) to your own log. Off by default.", isOn: $debug, icon: ("ladybug.fill", Color(uiColor: .systemGray)))
            NavigationLink {
                DebugLogView(log: model.debug)
            } label: {
                LabeledContent { Text(model.debug.lines.isEmpty ? "Empty" : "\(model.debug.lines.count) lines") } label: { SettingsLabel("Log", "text.alignleft", IOS27.SystemColors.brown) }
            }
            NavigationLink {
                ProbeView(probe: model.probes, showsDone: false)
            } label: {
                SettingsLabel("Probes", "stethoscope", IOS27.SystemColors.mint)
            }
        } header: {
            Text("Debug").plFont(.footnote)
        } footer: {
            Text("The log keeps the last 40 lines on this iPhone whether Debug is on or off. The probes try each thing this install may or may not be allowed to do, and say why when one fails.")
                .plFont(.footnote)
        }
    }

    private var forget: some View {
        Section {
            Button(role: .destructive) {
                warnTick += 1
                confirmForget = true
            } label: {
                Text("Forget config")
                    .plFont(.body)
                    .frame(minHeight: 28)
            }
        } footer: {
            Text("Removes every address and key from this iPhone.")
                .plFont(.footnote)
        }
    }

    private var about: some View {
        Section {
            ValueRow(label: "Version", value: version)
            Text("Optional text faces: Jost and Courier Prime, under the SIL Open Font License 1.1.")
                .plFont(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("About").plFont(.footnote)
        }
    }

    private func toggleRow(_ title: String, _ detail: String, isOn: Binding<Bool>, icon: (String, Color)? = nil) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: PLSpace.pad) {
                if let icon { SettingsIcon(symbol: icon.0, color: icon.1).padding(.top, 2) }
                VStack(alignment: .leading, spacing: PLSpace.hair) {
                    Text(title)
                        .plFont(.body)
                    Text(detail)
                        .plFont(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The last 40 things the app noted, newest first, already scrubbed of anything that looks like a key.
struct DebugLogView: View {
    let log: DebugLog
    @State private var clearTick = 0

    init(log: DebugLog) { self.log = log }

    var body: some View {
        List {
            if log.lines.isEmpty {
                EmptyNote(symbol: "text.alignleft", title: "Nothing noted yet", detail: "What the app does shows here as it happens.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(log.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .plFont(.footnote)
                        .textSelection(.enabled)
                }
                Button(role: .destructive) {
                    log.clear()
                    clearTick += 1
                } label: {
                    Text("Clear the log")
                        .plFont(.body)
                        .frame(minHeight: 28)
                }
            }
        }
        .plScreenTitle("Log")
        .sensoryFeedback(PLHaptic.commit, trigger: clearTick)
    }
}

/// The iOS Settings app's row icon: a 29 pt continuous squircle in a system colour with a white symbol.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A Settings row label: the icon, then the words.
struct SettingsLabel: View {
    let title: String
    let symbol: String
    let color: Color
    init(_ title: String, _ symbol: String, _ color: Color) { self.title = title; self.symbol = symbol; self.color = color }
    var body: some View {
        HStack(spacing: PLSpace.pad) {
            SettingsIcon(symbol: symbol, color: color)
            Text(title).plFont(.body)
        }
    }
}

/// The PL remix in Settings: which of his palettes the whole app wears (accent, wallpaper, glass wash, grounds, widgets),
/// and which app icon sits on the Home Screen.
struct HouseRows: View {
    @State private var kit = HouseKit.shared
    @State private var icon = UIApplication.shared.alternateIconName
    private let icons: [(String?, String)] = [(nil, "Plain"), ("AppIcon-HomeScreen", "Your Home Screen"), ("AppIcon-ObsidianGold", "Obsidian gold"),
                                              ("AppIcon-VoidEmber", "Void ember"), ("AppIcon-DeepIndigo", "Deep indigo"), ("AppIcon-BoneOxblood", "Bone oxblood")]
    var body: some View {
        Section {
            NavigationLink { ThemePacksView() } label: { SettingsLabel("Theme packs", "square.stack.3d.up.fill", kit.palette.keyColor) }
            NavigationLink { ColourwaysView() } label: {
                LabeledContent { Text(kit.palette.name == "home-screen" ? "Your Home Screen" : kit.palette.title) } label: { SettingsLabel("Colourways", "swatchpalette.fill", kit.palette.keyColor) }
            }
            Picker(selection: $kit.titleFace) {
                Text("Your hand (V1)").tag("v1"); Text("Your hand (V2)").tag("v2"); Text("Ransom").tag("ransom"); Text("Ledger").tag("ledger")
            } label: { SettingsLabel("Title face", "textformat", kit.palette.keyColor) }
            Picker(selection: $kit.paletteName) {
                ForEach(kit.palettes) { p in
                    HStack {
                        HStack(spacing: 0) { ForEach([p.groundColor, p.keyColor, p.accentColor, p.textColor], id: \.self) { Rectangle().fill($0) } }
                            .frame(width: 44, height: 18).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Text(p.name == "home-screen" ? "Your Home Screen" : p.title)
                    }
                    .tag(p.name)
                }
            } label: { SettingsLabel("House palette", "paintpalette.fill", kit.palette.keyColor) }
            .pickerStyle(.navigationLink)
            Picker(selection: Binding(get: { icon }, set: { name in
                UIApplication.shared.setAlternateIconName(name) { err in if err == nil { Task { @MainActor in icon = name } } }
            })) {
                ForEach(icons, id: \.1) { Text($0.1).tag($0.0) }
            } label: { SettingsLabel("App icon", "app.badge", kit.palette.keyColor) }
            LabeledContent { Text(kit.titleFont == nil ? "Loading" : "Your hand") } label: { SettingsLabel("Titles", "signature", kit.palette.keyColor) }
        } header: { Text("The house") } footer: {
            Text("Your palettes and your hand come from the Design Kit on the gallery and stay on this iPhone; none of it ships in the app's public code. Status colours stay Apple's.")
        }
    }
}


/// The colourway gallery: his 13 house palettes, his archive's 24, his works' 36 families, and the harmonies of the one he wears.
struct ColourwaysView: View {
    @State private var kit = HouseKit.shared
    var body: some View {
        List {
            group("House", kit.palettes)
            let h = kit.harmonies(of: kit.palette.name)
            if !h.isEmpty {
                Section("Harmonies of \(kit.palette.title)") {
                    ForEach(h, id: \.palette.name) { m in row(m.palette, label: m.rule.replacingOccurrences(of: "-", with: " ").capitalized) }
                }
            }
            group("From the archive", kit.archivePalettes)
            group("Families of your works", kit.familyPalettes)
            if kit.archivePalettes.isEmpty { Text("Open the app online once and the archive palettes, families and harmonies arrive from your Design Kit.").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Colourways")
    }

    @ViewBuilder private func group(_ title: String, _ list: [HousePalette]) -> some View {
        if !list.isEmpty { Section(title) { ForEach(list) { row($0, label: nil) } } }
    }

    private func row(_ p: HousePalette, label: String?) -> some View {
        Button { withAnimation(.snappy) { kit.paletteName = p.name } } label: {
            HStack(spacing: 12) {
                HStack(spacing: 0) { ForEach([p.groundColor, p.keyColor, p.accentColor, p.textColor], id: \.self) { Rectangle().fill($0) } }
                    .frame(width: 64, height: 28).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name == "home-screen" ? "Your Home Screen" : p.title)
                    if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if kit.paletteName == p.name { Image(systemName: "checkmark").foregroundStyle(p.keyColor) }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(kit.paletteName == p.name ? .isSelected : [])
    }
}

/// Built-in theme packs: a palette and a title face in one tap. A pack dropped in through Files (theme.json) still wins.
struct ThemePacksView: View {
    @State private var kit = HouseKit.shared
    var body: some View {
        List {
            ForEach(PLThemePreset.all) { t in
                let p = kit.allPalettes.first { $0.name == t.palette }
                Button { withAnimation(.snappy) { kit.paletteName = t.palette; kit.titleFace = t.face } } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p?.groundColor ?? .black)
                            .overlay { Text("Aa").font(.custom(face(t.face), size: 20)).foregroundStyle(p?.keyColor ?? .orange) }
                            .frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 2) { Text(t.title).font(.headline); Text(t.note).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if kit.paletteName == t.palette && kit.titleFace == t.face { Image(systemName: "checkmark.circle.fill").foregroundStyle(p?.keyColor ?? .orange) }
                    }
                }
                .foregroundStyle(.primary)
                .disabled(p == nil)
            }
        }
        .navigationTitle("Theme packs")
    }
    private func face(_ f: String) -> String { switch f { case "v2": return PLFace.handV2; case "ransom": return PLFace.ransom; case "ledger": return PLFace.ledger; default: return PLFace.handV1 } }
}
