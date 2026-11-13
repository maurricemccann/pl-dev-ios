import QuickLook
import SwiftUI

/// One file from the private vault, opened natively. The file comes down through the gallery door with the vault key (the same
/// request every other vault read makes), is kept in the temporary folder under its own name, and is shown by Apple's own
/// previewer (images, video, audio, PDF, text, Office files), with Share beside it. No web view.
struct VaultFileView: View {
    let model: AppModel
    let key: String
    let name: String
    @State private var file: URL?
    @State private var problem: String?
    @State private var loading = true

    var body: some View {
        Group {
            if let file {
                VaultPreview(url: file).ignoresSafeArea(edges: .bottom)
            } else if let problem {
                ContentUnavailableView {
                    Label("Could not open it", systemImage: "exclamationmark.triangle")
                } description: { Text(problem) } actions: {
                    Button("Try again") { Task { await fetch() } }.buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 12) { ProgressView(); Text("Bringing it down\u{2026}").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if let file { ShareLink(item: file) { Image(systemName: "square.and.arrow.up") } } }
        .task { await fetch() }
    }

    private func fetch() async {
        loading = true; problem = nil
        defer { loading = false }
        guard let http = model.http else { problem = "The gallery is not set up on this phone."; return }
        let path = "api/vault/" + (key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key)
        do {
            let data = try await http.send(RequestPlan(origin: "gallery", path: path), timeout: 180, cache: false)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let safe = name.isEmpty ? (key as NSString).lastPathComponent : name
            let url = dir.appendingPathComponent(safe.replacingOccurrences(of: "/", with: "-"))
            try data.write(to: url, options: .atomic)
            file = url
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// Apple's Quick Look previewer for one local file.
private struct VaultPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ c: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
