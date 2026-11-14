import SwiftUI

/// TEMPORARY (site lane): opens one piece of a page alone, so a screenshot run can show which piece misbehaves. Removed before DONE.
struct SiteDebugView: View {
    let name: String
    var body: some View {
        ScrollView {
            switch name {
            case "cn-head": CurveHeadline()
            case "cn-glyph": GlyphSolo(look: .gold, clip: .wave).frame(height: 300)
            case "cn-seals": StampSeals()
            case "cn-depth": CurveDepthGlyphs().frame(height: 400)
            case "cn-logo": SiteLogoMark().frame(width: 200, height: 200)
            case "sys-flow": SystemFlow().padding()
            case "sys-plate": SiteFleetPlate(url: Site.page("fleet/athena.svg") ?? URL(string: "https://example.com")!).frame(width: 120, height: 160)
            case "sys-inner": InnerVeilView()
            case "sys-veil": SystemVeil(value: "1,950", label: "commits", size: 60).padding()
            case "sys-tele": TelemetryFigure(archive: 1347, fragments: 466, conversations: 86).padding()
            default: Text(name)
            }
        }
        .background(Color(hex: 0x0e0c08)).environment(\.colorScheme, .dark)
    }
}
