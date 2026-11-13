import SwiftUI

/// The archive: the seven-year body of work, browsed in pages of 24 as the site's stream serves it. A tap opens the piece in
/// full with its answers; requesting a piece is a vote that the site checks comes from a person, so it opens on the site.
struct ArchiveView: View {
    let model: AppModel
    @State private var stream = StreamModel(kind: "archive")
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SitePageHead(eyebrow: "The archive \u{2014} " + (stream.total > 0 ? "\(stream.total)" : "seven years of") + " pieces", lead: "The evidence,", accent: "unbroken.",
                             lede: "The archive is not the backstory. It is the evidence. Every piece, in the order it was made.")
                if stream.items.isEmpty {
                    if let f = stream.failure {
                        EmptyNote(symbol: "wifi.exclamationmark", title: "Could not load the archive", detail: f, actionTitle: "Try again") { Task { await stream.reload() } }
                    } else {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(0..<12, id: \.self) { _ in RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Bone.line(.light).opacity(0.4)).aspectRatio(1, contentMode: .fit) }
                        }
                        .redacted(reason: .placeholder).accessibilityLabel("Loading the archive")
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(stream.items) { item in
                            NavigationLink { StreamDetailView(stream: stream, itemID: item.id) } label: {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        AsyncImage(url: item.picture) { phase in
                                            switch phase {
                                            case .success(let i): i.resizable().scaledToFill()
                                            case .failure: Image(systemName: "photo").foregroundStyle(.tertiary)
                                            default: Color.clear
                                            }
                                        }
                                    }
                                    .background(Bone.line(.light).opacity(0.4))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .accessibilityLabel("\(item.title ?? item.cr ?? "Archive piece"), \(item.cr ?? "")")
                            }
                            .buttonStyle(.plain)
                            .onAppear { if item.id == stream.items.last?.id { Task { await stream.more() } } }
                        }
                    }
                    if stream.loading { ProgressView().padding() }
                    Text("\(stream.items.count) of \(stream.total) pieces").siteLabel(10).contentTransition(.numericText()).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 24)
        }
        .siteScreen()
        .refreshable { await stream.reload() }
        .task { if stream.items.isEmpty { await stream.reload() } }
        .sensoryFeedback(PLHaptic.commit, trigger: stream.tick)
    }
}
