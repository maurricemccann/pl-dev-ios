import SwiftUI
import RealityKit

/// The play screen: the engine's view, the touch layer, a caption line and the debug panel. Leaving the app saves.
struct PLWView: View {
    let store: PLWSaveStore
    var quiet = false
    var overview = false
    @State private var runtime: PLWRuntime
    @Environment(\.scenePhase) private var phase

    init(store: PLWSaveStore, quiet: Bool = false, overview: Bool = false) {
        self.store = store; self.quiet = quiet; self.overview = overview
        _runtime = State(initialValue: PLWRuntime(store: store, quiet: quiet, overview: overview))
    }

    var body: some View {
        let rt = runtime
        ZStack {
            WorldView(engine: rt.engine, background: .world(PLWRing.pageHex[0])) { _ in await rt.start() }.ignoresSafeArea()
            if !quiet { PLWControls(input: rt.input) }
            if !quiet { WorldCaption(data: rt.caption.map { WorldCaptionData(title: $0, year: "") }) }
            if !quiet { PLWOverlay(runtime: rt) }
            if let n = rt.notice { VStack { Text(n).font(.caption2).padding(.horizontal, 10).padding(.vertical, 5).background(.thinMaterial, in: Capsule()).padding(.top, 6); Spacer() } }
        }
        .background(Color.black)
        .onChange(of: phase) { _, p in if p != .active { store.flush() } }   // the save is also written on every moment; this covers a kill from the switcher
        .onDisappear { rt.stop() }
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden()
    }
}

/// The corner key (like PL Paint's Debug mode) and what it opens: the frame counter and the two speed tunables.
private struct PLWOverlay: View {
    let runtime: PLWRuntime
    @Bindable private var tuning = PLWTuning.shared
    init(runtime: PLWRuntime) { self.runtime = runtime }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { tuning.debug.toggle() } label: {
                    Image(systemName: tuning.debug ? "speedometer" : "gauge.with.dots.needle.0percent").font(.system(size: 15, weight: .medium))
                        .frame(width: 36, height: 36).background(.black.opacity(0.35), in: Circle()).foregroundStyle(.white.opacity(0.85))
                }
                .accessibilityLabel(tuning.debug ? "Hide debug" : "Show debug")
                Spacer()
            }
            if tuning.debug {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(runtime.fps) fps   \(String(format: "%.1f", runtime.frameMS)) ms   worst \(String(format: "%.0f", runtime.worstMS)) ms").font(.system(.caption, design: .monospaced))
                    Text(runtime.readout).font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                    HStack { Text("Walk \(String(format: "%.1f", tuning.walk))").font(.caption2).frame(width: 64, alignment: .leading); Slider(value: $tuning.walk, in: 3...10) }
                    HStack { Text("Run \(String(format: "%.1f", tuning.run))").font(.caption2).frame(width: 64, alignment: .leading); Slider(value: $tuning.run, in: 6...16) }
                    Button("Reset speeds") { tuning.reset() }.font(.caption2)
                }
                .padding(10).frame(maxWidth: 300).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
            }
            Spacer()
        }
        .onChange(of: tuning.walk) { _, _ in tuning.persist() }
        .onChange(of: tuning.run) { _, _ in tuning.persist() }
        .onChange(of: tuning.debug) { _, _ in tuning.persist() }
        .padding(.leading, 12).padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            if runtime.loadFailed {
                Text("This room did not load.").font(.footnote).padding(12).background(.thinMaterial, in: Capsule())
            } else if !runtime.ready {
                ProgressView().tint(.white)
            }
        }
    }
}
