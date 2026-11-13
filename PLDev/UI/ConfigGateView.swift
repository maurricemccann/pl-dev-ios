import SwiftUI
import UniformTypeIdentifiers

/// No config yet: one title, one sentence, one button, the error line. No network request of any kind happens from here.
struct ConfigGateView: View {
    let model: AppModel
    @State private var picking = false
    @State private var loading = false
    @State private var importError: String? = nil
    @State private var errorTick = 0
    @State private var pickTick = 0

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: AppModel) { self.model = model }

    private var errorLine: String? { importError ?? model.configError }

    var body: some View {
        VStack(spacing: PLSpace.margin) {
            Image(systemName: "doc.badge.gearshape")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(PLTone.accent)
                .accessibilityHidden(true)
            Text("Load your config")
                .plTitle(.largeTitle)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("One file tells this app where your services are and holds your keys. It is kept in this iPhone\u{2019}s Keychain. Nothing is contacted until it is loaded.")
                .plFont(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                pickTick += 1
                picking = true
            } label: {
                Label(loading ? "Reading the file" : "Choose the file", systemImage: "folder")
                    .plFont(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 28)
                    .frame(minHeight: 50)
                    .contentShape(Capsule())
            }
            .glassControl(tint: PLTone.accent)
            .disabled(loading)
            .accessibilityHint("Opens Files to pick your config, a JSON file")
            if let line = errorLine {
                NoteLine(symbol: "exclamationmark.triangle.fill", tint: PLTone.bad, text: line)
                    .transition(.opacity)
            }
        }
        .padding(PLSpace.margin * 2)
        .frame(maxWidth: 520)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importError = nil
                load(url)
            case .failure(let error):
                importError = error.localizedDescription
                errorTick += 1
            }
        }
        .onChange(of: model.configError) { _, new in
            if new != nil { errorTick += 1 }
        }
        .sensoryFeedback(PLHaptic.error, trigger: errorTick)
        .sensoryFeedback(PLHaptic.select, trigger: pickTick)
    }

    private func load(_ url: URL) {
        loading = true
        Task {
            await model.loadConfig(from: url)   // the store opens and closes the picked file's security scope itself
            loading = false
        }
    }
}
