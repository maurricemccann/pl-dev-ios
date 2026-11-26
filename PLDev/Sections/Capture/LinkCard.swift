import LinkPresentation
import SwiftUI

/// The system's own card for a link: its picture and title, read on the phone. No title found = the bare address stays.
struct LinkCard: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> LPMetadataProvider { LPMetadataProvider() }   // kept alive while it fetches

    func makeUIView(context: Context) -> LPLinkView {
        let view = LPLinkView(url: url)
        context.coordinator.startFetchingMetadata(for: url) { data, _ in
            // LPLinkMetadata is not Sendable; it is only handed to the view, on the main queue
            nonisolated(unsafe) let found = data
            DispatchQueue.main.async {
                guard let found else { return }
                view.metadata = found
                view.sizeToFit()
            }
        }
        return view
    }

    func updateUIView(_ view: LPLinkView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LPLinkView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: uiView.sizeThatFits(CGSize(width: width, height: 280)).height)
    }
}
