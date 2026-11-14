import SwiftUI

/// The Psyched Study (`app/study/page.tsx`): the philosophy, the name, the mechanism, the practice, then the room: sixteen
/// concepts and the three beyond them, each opening to its reflection. A reflection is written and kept on this phone only
/// (the site keeps it in the browser: "Your reflections stay with you"), never sent anywhere. Then the Mirror, and the close.
struct StudyView: View {
    var jumpToMirror = false
    private let count = SiteArchiveCount.shared
    @State private var saved = StudyNotes.count()
    @Environment(\.colorScheme) private var scheme

    private static let how: [(String, String)] = [
        ("Identity Construction", "You decide who you are before the evidence supports it. Not who you hope to become. Who you already are."),
        ("Selective Perception", "The prepared mind sees what was always there. Attention is construction, not observation."),
        ("Behavioral Alignment", "Identity, once decided, shapes every decision made. The actions follow the position \u{2014} not the other way around."),
        ("Declaration as Commitment", "Wearing it publicly is not performance. It is the declaration that you have already decided on the destination."),
    ]
    private static let practice = ["Believe first", "Document", "Declare", "Hold the vision", "Persist", "Let the results speak"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("The Study opens with the philosophy").siteLabel()
                        SiteDisplay(parts: [("The philosophy did not\narrive from a ", false), ("book.", true)], size: 40)
                        Text("It arrived through fifteen years of lived practice. Tested against real conditions. Refined through pressure. Proven through existence. What follows is the position \u{2014} and then the room built to walk it.").siteBody(16)
                    }
                    .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 48)

                    SitePaper {
                        Text("The name is the first argument").siteLabel().padding(.bottom, 8)
                        (Text("Psyche").font(SiteFont.display(21, italic: true)).foregroundColor(Bone.ink(scheme))
                         + Text(" \u{2014} reaches into the Greek ") + Text("psyche").italic()
                         + Text(": the soul, the breath of life, the self as it truly exists beneath social performance. It does not mean excited. It means prepared."))
                            .siteBody(15)
                        (Text("Luxuries").font(SiteFont.display(21, italic: true)).foregroundColor(Bone.ink(scheme))
                         + Text(" \u{2014} not frivolity, not excess for its own sake. The radical act of treating your inner life, your imagination, your becoming, as something worthy of the highest investment."))
                            .siteBody(15)
                    }

                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How it works").siteLabel()
                            Text("The mechanism").font(SiteFont.display(38)).foregroundStyle(Bone.ink(scheme)).accessibilityAddTraits(.isHeader)
                        }
                        Rectangle().fill(Bone.gold).frame(width: 96, height: 1)
                        ForEach(Self.how, id: \.0) { h in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(h.0).font(SiteFont.display(24)).foregroundStyle(Bone.ink(scheme))
                                Text(h.1).siteBody(14)
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 64)

                    SiteBand {
                        Text("The Practice").siteTag(11, Bone.gold)
                        Text("The luxury is not a garment.").font(SiteFont.display(36)).foregroundStyle(Color(hex: 0xf1ece1))
                        Text("The garment is not the destination. It is the declaration that you have already decided on the destination.").siteBody(15)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
                            ForEach(Array(Self.practice.enumerated()), id: \.offset) { i, p in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(i + 1)").plHand(30).foregroundStyle(Bone.gold)
                                    Text(p).font(SiteFont.display(19)).foregroundStyle(Color(hex: 0xf1ece1))
                                }
                                .padding(22).frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading).background(Color(hex: 0x0e0c08))
                            }
                        }
                        .background(Color.white.opacity(0.1))
                    }

                    ZStack(alignment: .bottomLeading) {
                        GoldCurvesLayer(opacity: 0.8).frame(height: 460).clipped()
                        VStack(alignment: .leading, spacing: 22) {
                            Text("The Psyched Study \u{2014} the philosophy, given a room").siteLabel()
                            SiteDisplay(parts: [("The philosophy\nhas a ", false), ("room", true), (" now.", false)], size: 42)
                            Text("Sixteen concepts. Each one earned. Not advice \u{2014} architecture. Move through them in order, or wander. No account. Nothing collected. Your reflections stay with you.").siteBody(16)
                        }
                        .padding(.horizontal, 24).padding(.bottom, 32)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("The Curriculum").siteTag(11, Bone.gold)
                        Text("Sixteen concepts.").font(SiteFont.display(32)).foregroundStyle(Bone.ink(scheme))
                        if saved > 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("You have been here before").siteLabel()
                                Text("\(saved == 1 ? "One reflection is" : "\(saved) reflections are") still saved on this phone. They stay here \u{2014} they never reach us, and they do not travel to another device.").siteBody(14)
                            }
                            .siteCard(padding: 22, radius: 20).padding(.vertical, 16)
                        }
                        ForEach(Array(StudyCurriculum.concepts.enumerated()), id: \.element.id) { _, c in StudyConceptRow(concept: c) { saved = StudyNotes.count() } }
                        SiteRule()
                    }
                    .padding(.horizontal, 24).padding(.vertical, 48)

                    SitePaper {
                        Text("The Practice Continues").siteTag(11, Bone.gold)
                        Text("Beyond the sixteen.").font(SiteFont.display(32)).foregroundStyle(Bone.ink(scheme))
                        Text("Earned after the curriculum \u{2014} the structural foundation beneath all of it.").siteBody(14)
                        ForEach(StudyCurriculum.continuations) { c in StudyConceptRow(concept: c) { saved = StudyNotes.count() } }
                    }

                    StudyMirror().id("mirror")

                    SiteBand {
                        VStack(spacing: 24) {
                            Text("You are not what you think in your best moments. You are what you think when nothing is working and no one is watching.")
                                .plHand(28).foregroundStyle(Color(hex: 0xf1ece1)).multilineTextAlignment(.center)
                            NavigationLink { ArchiveView(model: .shared) } label: { Text("Seven years of that thinking \u{2192}").padding(.horizontal, 10) }.buttonStyle(SitePill(gold: true)).fixedSize()
                            Text("\(count.text) dated pieces. The archive, not the store.").font(SiteFont.body(12)).foregroundStyle(Color(hex: 0xf1ece1).opacity(0.5))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
            }
            .task {
                await count.load()
                if jumpToMirror { try? await Task.sleep(for: .milliseconds(400)); withAnimation { proxy.scrollTo("mirror", anchor: .top) } }
            }
        }
        .siteScreen()
        .plScreenTitle("The Psyched Study")
    }
}

/// The reflections, kept on this phone under the site's own keys (`pl-study-<roman>`).
enum StudyNotes {
    static func key(_ roman: String) -> String { "pl-study-" + roman }
    static func count() -> Int {
        (StudyCurriculum.concepts + StudyCurriculum.continuations).filter { !(UserDefaults.standard.string(forKey: key($0.roman)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
}

/// `Concept`: the numeral in his hand, the law, the title; open, the body, the reflection prompt and a private field.
struct StudyConceptRow: View {
    let concept: StudyConcept
    var changed: () -> Void = {}
    @State private var open = false
    @State private var note = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(open ? Bone.gold.opacity(0.4) : Bone.line(scheme)).frame(height: 0.6)
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(concept.roman).plHand(36).foregroundStyle(open ? Bone.gold : Bone.inkFaint(scheme)).frame(width: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(concept.law).siteLabel(10)
                        Text(concept.title).font(SiteFont.display(24)).foregroundStyle(open ? Bone.gold : Bone.ink(scheme)).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Text(open ? "\u{2212}" : "+").font(SiteFont.display(24, italic: true)).foregroundStyle(open ? Bone.gold : Bone.inkFaint(scheme))
                }
                .padding(.vertical, 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Open" : "Closed")
            if open {
                VStack(alignment: .leading, spacing: 20) {
                    Text(concept.body).siteBody(15)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("The Reflection").siteTag(11, Bone.gold)
                        Text(concept.prompt).font(SiteFont.body(14)).italic().foregroundStyle(Bone.ink(scheme)).lineSpacing(4)
                        TextField("Write here. This stays on your phone \u{2014} no account, nothing collected.", text: $note, axis: .vertical)
                            .lineLimit(4...12).font(SiteFont.body(14)).padding(14)
                            .background(Bone.raised(scheme)).overlay { Rectangle().strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
                            .accessibilityLabel("Reflection on \(concept.title), stays on your phone")
                    }
                    .padding(.leading, 18).overlay(alignment: .leading) { Rectangle().fill(Bone.gold.opacity(0.4)).frame(width: 2) }
                    if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(concept.acknowledgment).font(SiteFont.body(14)).italic().foregroundStyle(Bone.inkFaint(scheme)).lineSpacing(4)
                    }
                }
                .padding(.bottom, 28).transition(.opacity)
            }
        }
        .onAppear { note = UserDefaults.standard.string(forKey: StudyNotes.key(concept.roman)) ?? "" }
        .onChange(of: note) { _, v in UserDefaults.standard.set(v, forKey: StudyNotes.key(concept.roman)); changed() }
    }
}

/// `MirrorShowcase`: the philosophy rendered, each reflection with its numeral, what it carries and its technique.
private struct StudyMirror: View {
    var body: some View {
        SiteBand {
            Text("The philosophy, rendered \u{2014} the house watching itself think").siteTag(11, Bone.gold)
            SiteDisplay(parts: [("The ", false), ("Mirror.", true)], size: 38)
            Text("Seven reflections of one self \u{2014} a heart drawn with an arrow pointed back at itself. The same self in seven motions: the breath, the hand, the seed, the mend. One gold, one void. The house, watching itself think.").siteBody(15)
            VStack(spacing: 1) {
                ForEach(MirrorDoor.all) { d in
                    NavigationLink { LabHost(page: d.page, model: .shared) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(d.numeral).plHand(28).foregroundStyle(Bone.gold)
                                Text(d.name).font(SiteFont.display(22)).foregroundStyle(Color(hex: 0xf1ece1))
                            }
                            if let m = d.page.mirror {
                                Text(m.carries).siteBody(14).multilineTextAlignment(.leading)
                                Text(m.technique).siteLabel(9)
                            }
                        }
                        .padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0x0e0c08))
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.white.opacity(0.06))
            .overlay { Rectangle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.6) }
        }
    }
}
