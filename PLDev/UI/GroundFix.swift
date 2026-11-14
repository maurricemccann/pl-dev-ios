import SwiftUI
import UIKit

// THE WHITE FLASH (his note 11-14: "There is a white flash when switching pages in light mode").
//
// A pushed section is a UIHostingController whose SwiftUI ground (HouseGround, a skin's own ground) draws one frame AFTER UIKit has
// already shown the container behind it: the window, and the navigation controller's own view, both the system's background, which in
// Light Appearance is white. The root `Backdrop` was also Apple's grouped grey. So the push and pop slid a white card over nothing.
// Every container now has a ground from the first frame: the window and each navigation controller take the house ground (the chosen
// palette's, or the carry's, following light and dark), `Backdrop` draws it, and `plGround()` also sets it as the navigation container's
// background. Nothing here changes what a section draws on top.

extension HouseKit {
    /// The ground UIKit paints behind everything, the colour HouseGround draws: dark = the palette's ground; light = Apple's grouped
    /// background washed with the palette's text colour (a chosen pack: its pale or deep ground, whichever way the palette runs).
    func groundUIColor() -> UIColor {
        let p = palette
        let text = UIColor(p.textColor), ground = UIColor(p.groundColor)
        let fallback = UIColor { trait in
            if trait.userInterfaceStyle == .dark { return ground.resolvedColor(with: trait) }
            let base = UIColor.systemGroupedBackground.resolvedColor(with: trait), wash = text.resolvedColor(with: trait)
            var b: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0), w: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            base.getRed(&b.0, green: &b.1, blue: &b.2, alpha: &b.3); wash.getRed(&w.0, green: &w.1, blue: &w.2, alpha: &w.3)
            return UIColor(red: b.0 * 0.55 + w.0 * 0.45, green: b.1 * 0.55 + w.1 * 0.45, blue: b.2 * 0.55 + w.2 * 0.45, alpha: 1)
        }
        return PLCarry.uiGround(fallback: fallback)
    }
}

/// A one-point view that, once it is in a window, paints the window and its navigation controller with the house ground.
struct WindowGround: UIViewRepresentable {
    func makeUIView(context: Context) -> GroundProbe { GroundProbe() }
    func updateUIView(_ v: GroundProbe, context: Context) { _ = PLCarry.epoch.n; _ = HouseKit.shared.paletteName; v.paint() }   // read, so a new palette repaints the window
}

final class GroundProbe: UIView {
    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; backgroundColor = .clear; isAccessibilityElement = false }
    required init?(coder: NSCoder) { fatalError("not from a nib") }
    override func didMoveToWindow() { super.didMoveToWindow(); paint() }

    @MainActor func paint() {
        let ground = HouseKit.shared.groundUIColor()
        window?.backgroundColor = ground
        var r: UIResponder? = self
        while let n = r {
            if let vc = n as? UIViewController, let nav = vc.navigationController ?? (vc as? UINavigationController) { nav.view.backgroundColor = ground; break }
            r = n.next
        }
    }
}
