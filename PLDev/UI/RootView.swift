import LocalAuthentication
import SwiftUI

/// The front door: no config shows "Load your config" and nothing else; with a config, Face ID (or the passcode)
/// opens Home. A failed check stays closed, with Unlock to try again.
struct RootView: View {
    let model: AppModel
    @State private var unlocked = false
    @State private var checking = false
    @State private var askedThisVisit = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @AppStorage("pldev.motion") private var motion = "full"
    @AppStorage("pldev.theme") private var theme = "system"

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: AppModel) { self.model = model }

    private var hasConfig: Bool { model.config != nil }
    private var reduce: Bool { systemReduce || motion == "reduce" }

    var body: some View {
        ZStack {
            Backdrop()
            if model.restoring {
                // the saved config is still being read back: show nothing rather than a "Load your config" flash
                Color.clear
            } else if !hasConfig {
                ConfigGateView(model: model)
                    .transition(.opacity)
            } else if unlocked {
                HomeView(model: model)
                    .transition(.opacity)
            } else {
                lockedView
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) { OfflineLine() }   // every app: says when it is showing saved copies
        .animation(PLMotion.standard(reduce: reduce), value: unlocked)
        .animation(PLMotion.standard(reduce: reduce), value: hasConfig)
        .tint(PLTone.accent)
        .preferredColorScheme(PLAppearance.scheme(theme))
        .task(id: hasConfig) {
            guard hasConfig else {
                unlocked = false   // a forgotten config locks the door again
                return
            }
            Poller.shared.start()
            Task { await Poller.shared.refreshAll() }   // the timer may have started before the config was there
            await unlockIfDue()
        }
        .onChange(of: scenePhase) { _, phase in
            // a launch in the background (a refresh, a notification) cannot show Face ID: ask when the app is opened.
            // Face ID's own sheet only makes the scene inactive, so a cancel does not bring the prompt straight back.
            if phase == .background {
                askedThisVisit = false
                Poller.shared.stop()
            }
            if phase == .active {
                Poller.shared.start()   // does nothing until a config is loaded
                Task { await unlockIfDue() }
            }
        }
    }

    /// One automatic ask per visit to the foreground; Unlock asks again by hand.
    private func unlockIfDue() async {
        guard hasConfig, !unlocked, !askedThisVisit, scenePhase == .active else { return }
        askedThisVisit = true
        await unlock()
    }

    private var lockedView: some View {
        VStack(spacing: PLSpace.margin) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Locked")
                .plTitle(.largeTitle)
                .accessibilityAddTraits(.isHeader)
            Text("This app holds your keys. Unlock to open it.")
                .plFont(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await unlock() }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .plFont(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 28)
                    .frame(minHeight: 50)
                    .contentShape(Capsule())
            }
            .glassControl(tint: PLTone.accent)
            .opacity(checking ? 0 : 1)   // kept in the layout so nothing jumps when the system sheet closes
            .disabled(checking)
        }
        .padding(PLSpace.margin * 2)
    }

    private func unlock() async {
        if checking { return }
        checking = true
        unlocked = await authenticate()
        checking = false
    }

    /// Face ID, Touch ID or the passcode. A device with no passcode has nothing to check, so it opens.
    private func authenticate() async -> Bool {
        let context = LAContext()
        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else { return true }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open the app") { passed, _ in
                continuation.resume(returning: passed)
            }
        }
    }
}
