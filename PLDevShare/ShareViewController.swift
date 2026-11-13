import ImageIO
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The one thing being shared, already read out of the host app's item.
struct SharePayload: Sendable {
    var kind: String        // "text" | "url" | "image"
    var text: String?
    var url: String?
    var title: String?
    var image: Data?        // a JPEG no larger than 2048 px on its long side
}

@MainActor @Observable final class ShareModel {
    enum Phase {
        case loading
        case ready(SharePayload)
        case saved
        case failed(String)
    }

    var phase: Phase = .loading
    var note = ""
}

/// The share sheet's entry point. It reads the shared item, shows it with a note field, and on Save writes
/// one item into the shared inbox. It never opens the network: the app sends the item the next time it opens.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let sheet = ShareSheet(
            model: model,
            save: { [weak self] in self?.save() },
            cancel: { [weak self] in self?.cancel() }
        )
        let host = UIHostingController(rootView: sheet)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { model.phase = await load() }
    }

    // MARK: Reading the shared item

    private func load() async -> ShareModel.Phase {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let title = items.first?.attributedContentText?.string
        let providers = items.flatMap { $0.attachments ?? [] }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            guard let raw = await loadData(provider, type: UTType.image.identifier) else {
                return .failed("That image could not be read.")
            }
            // Decoding a large photo is slow and heavy, so it happens off the main thread.
            let jpeg = await Task.detached { ShareImage.downscaledJPEG(raw, maxPixel: 2048) }.value
            guard let jpeg else { return .failed("That image could not be read.") }
            return .ready(SharePayload(kind: "image", text: nil, url: nil, title: title, image: jpeg))
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }),
           let url = await loadURL(provider), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return .ready(SharePayload(kind: "url", text: nil, url: url.absoluteString, title: title, image: nil))
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }),
           let text = await loadText(provider), !text.isEmpty {
            return .ready(SharePayload(kind: "text", text: text, url: nil, title: nil, image: nil))
        }
        if let title, !title.isEmpty {
            return .ready(SharePayload(kind: "text", text: title, url: nil, title: nil, image: nil))
        }
        return .failed("There is nothing here that can be saved.")
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { done in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                done.resume(returning: (item as? URL) ?? (item as? String).flatMap { URL(string: $0) })
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { done in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                done.resume(returning: (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) })
            }
        }
    }

    private func loadData(_ provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { done in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                done.resume(returning: data)
            }
        }
    }

    // MARK: Save and Cancel

    private func save() {
        guard case .ready(let payload) = model.phase else { return }
        let note = model.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = SharedInbox.Item(
            id: UUID().uuidString,
            createdAt: Date(),
            source: "share",
            kind: payload.kind,
            text: payload.text,
            url: payload.url,
            title: payload.title,
            fileName: payload.image == nil ? nil : "image.jpg",
            note: note.isEmpty ? nil : note
        )
        do {
            try SharedInbox.add(item, file: payload.image)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            model.phase = .failed(error.localizedDescription)
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        model.phase = .saved
        Task {
            // Long enough to read the one line, then the sheet closes itself.
            try? await Task.sleep(for: .milliseconds(1400))
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}

/// Shrinks an image with ImageIO, which never holds the full-size bitmap in memory (an extension has little).
enum ShareImage {
    static func downscaledJPEG(_ data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let quality: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, quality as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}

/// The sheet: what is being saved, a note, Save and Cancel.
struct ShareSheet: View {
    @Bindable var model: ShareModel
    let save: () -> Void
    let cancel: () -> Void

    private var canSave: Bool {
        if case .ready = model.phase { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("PL DEV")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(!canSave)
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Reading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let payload):
            Form {
                Section("Saving") {
                    preview(payload)
                }
                Section("Note") {
                    TextField("Add a note", text: $model.note, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityLabel("Note")
                }
            }
        case .saved:
            ContentUnavailableView(
                "Saved",
                systemImage: "checkmark.circle.fill",
                description: Text("PL DEV sends it next time it opens.")
            )
        case .failed(let message):
            ContentUnavailableView(
                "Not saved",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
    }

    @ViewBuilder private func preview(_ payload: SharePayload) -> some View {
        if let data = payload.image, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("The image being saved")
        }
        if let title = payload.title, !title.isEmpty {
            Text(title)
                .font(.headline)
                .lineLimit(2)
        }
        if let url = payload.url {
            Label(url, systemImage: "link")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        if let text = payload.text {
            Text(text)
                .font(.body)
                .lineLimit(8)
        }
    }
}
