import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// The panels the canvas can open (each is a sheet over it).
enum NativePanel: String, Identifiable {
    case colour, layers, brushes, studio, adjust, works, settings, gestures, quickEditor, handbook, sync, exportPicture, send, newCanvas, rename, assists, lift, timelapse, study, bringIn, tweak, repeatCheck, tools2, shareFiles, actions
    var id: String { rawValue }
}

/// The days he drew: the laptop's `daily.json` (a count of finished strokes per day), kept on the phone and merged with the laptop's in Sync.
@MainActor enum NativeDaily {
    private static var url: URL { NativeStore.dir.appendingPathComponent("daily.json") }
    static var days: [String: Int] = load()
    private static var pending: Task<Void, Never>?
    static func key(_ d: Date = .now) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
    static func load() -> [String: Int] {
        guard let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return (o["days"] as? [String: Int]) ?? [:]
    }
    static func bump() {
        days[key(), default: 0] += 1
        pending?.cancel()
        pending = Task { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { save() } }
    }
    static func save() {
        if let d = try? JSONSerialization.data(withJSONObject: ["v": 1, "days": days]) { try? d.write(to: url, options: .atomic) }
    }
    /// The larger count per day wins.
    static func merge(_ remote: [String: Int]) {
        for (k, v) in remote { days[k] = max(days[k] ?? 0, v) }
        save()
    }
    static var streak: Int {
        var d = Date(), n = 0
        if days[key(d)] == nil { d = d.addingTimeInterval(-86400) }
        while days[key(d)] != nil { n += 1; d = d.addingTimeInterval(-86400) }
        return n
    }
}

extension NativeCanvasModel {
    /// The action names the Quick menu and Gesture controls choose from (the laptop's `QM_ACTIONS`).
    static let actionNames: [String] = [
        "Undo", "Redo", "Fit to screen", "Eyedropper", "Eraser (toggle)", "New layer", "Duplicate layer", "Merge down", "Clear layer", "Colour panel", "Layers panel", "Brush Studio",
        "Selection", "Transform", "Symmetry (cycle)", "Guide (cycle)", "Move vanishing points", "Assisted drawing", "QuickShape", "Adjustments", "Add / paint mask", "Clip to layer below",
        "Adjust last stroke", "Study (record how I draw)", "Lift (ink off a photo)", "Timelapse", "Ghost copy of the layer", "Corner copies", "Check the repeat (3 by 3)", "Gallery", "Gesture controls", "Copy", "Cut", "Paste", "Transparent background", "Make tile (slide half way round)", "ColorDrop", "Smudge (toggle)", "Hide interface", "Settings", "Handbook",
        "Facet next stroke", "Facet (toggle)", "Echo Fill", "Node mode", "Lights off", "Light one", "Other ground", "Hand trace", "Seam mode (toggle)", "Save print files (seam mode)", "Tile (cycle)", "Show the tiles around", "Tangent Lock", "Export alive (breathe)", "More tools",
    ]

    func run(action name: String) {
        switch name {
        case "None", "": break
        case "Undo": undoStroke()
        case "Redo": redoStroke()
        case "Fit to screen": stage?.fit()
        case "Eyedropper": setMode(mode == .eyedrop ? .draw : .eyedrop)
        case "Eraser (toggle)":
            if tool == .erase { tool = toolBeforeErase } else { toolBeforeErase = tool == .smudge ? .smudge : .paint; tool = .erase }
            say(tool == .erase ? "Eraser." : "Brush.")
        case "Smudge (toggle)": tool = tool == .smudge ? .paint : .smudge; say(tool == .smudge ? "Smudge." : "Brush.")
        case "New layer": addLayer()
        case "Duplicate layer": duplicateLayer()
        case "Merge down": mergeDown()
        case "Clear layer": clearLayer()
        case "Colour panel": panel = .colour
        case "Layers panel": panel = .layers
        case "Brush Studio": panel = .studio
        case "Selection": setMode(mode == .select ? .draw : .select)
        case "Transform": toggleTransform()
        case "Symmetry (cycle)": cycleSymmetry()
        case "Guide (cycle)": cycleGuide()
        case "Move vanishing points": vpEdit.toggle(); say(vpEdit ? "The vanishing points can be dragged." : "Vanishing points locked."); stage?.updateOverlay()
        case "Assisted drawing": assist.toggle(); say("Assisted drawing \(assist ? "on" : "off")."); prefsSoon()
        case "QuickShape": quickShape.toggle(); say("QuickShape \(quickShape ? "on" : "off")."); prefsSoon()
        case "Adjustments": panel = .adjust
        case "Add / paint mask": maskButton()
        case "Clip to layer below": toggleClip()
        case "Adjust last stroke": panel = .tweak
        case "Study (record how I draw)": panel = .study
        case "Lift (ink off a photo)": panel = .lift
        case "Timelapse": panel = .timelapse
        case "Ghost copy of the layer": ghostBelow()
        case "Corner copies": cornerCopies()
        case "Check the repeat (3 by 3)": panel = .repeatCheck
        case "Gallery": panel = .works
        case "Gesture controls": panel = .gestures
        case "Copy": clipCopy(cut: false)
        case "Cut": clipCopy(cut: true)
        case "Paste": clipPaste()
        case "Transparent background": if let d = doc { setBackground(visible: !d.bgVis); say(d.bgVis ? "The background shows." : "The background is transparent.") }
        case "Make tile (slide half way round)": makeTile()
        case "ColorDrop": setMode(mode == .fill ? .draw : .fill)
        case "Hide interface": uiHidden.toggle()
        case "Settings": panel = .settings
        case "Handbook": panel = .handbook
        case "Facet next stroke": toggleFacetNext()
        case "Facet (toggle)": facet.toggle(); say(facet ? "Every stroke is faceted." : "Facet off."); prefsSoon()
        case "Echo Fill": toggleEcho()
        case "Node mode": toggleNodes()
        case "Lights off": toggleLightsOff()
        case "Light one": toggleLightOne()
        case "Other ground": otherGround()
        case "Hand trace": handTrace()
        case "Seam mode (toggle)": toggleSeam()
        case "Save print files (seam mode)": seamPrintFiles()
        case "Tile (cycle)":
            let all = TileMode.allCases
            tile = all[((all.firstIndex(of: tile) ?? 0) + 1) % all.count]; say("Tile: \(tile.label)."); stage?.updateOverlay(); markChanged()
        case "Show the tiles around": tilePrev.toggle(); say(tilePrev ? "The tiles around show." : "The tiles around are hidden."); stage?.updateOverlay(); prefsSoon()
        case "Tangent Lock": tangentLock.toggle(); say("Tangent lock \(tangentLock ? "on" : "off")."); prefsSoon()
        case "Export alive (breathe)": panel = .timelapse
        case "More tools": panel = .tools2
        default: say("\(name) is not on this phone.")
        }
    }

    func cycleSymmetry() {
        let all = SymMode.allCases
        sym = all[((all.firstIndex(of: sym) ?? 0) + 1) % all.count]
        say("Symmetry: \(sym.label).")
        stage?.updateOverlay()
    }
    func cycleGuide() {
        let all = GuideKind.allCases
        guide = all[((all.firstIndex(of: guide) ?? 0) + 1) % all.count]
        if guide.points > 0 { vpEdit = true; say("Drag the coloured points to move the vanishing points.") } else { say("Guide: \(guide.label).") }
        _ = guideVPs()
        stage?.updateOverlay(); markChanged()
    }

    /// Slides everything half way round both ways, so what lay at the edges is in the middle where it can be mended.
    func makeTile() {
        guard live == nil, let d = doc else { return }
        structDo("Make tile", pixels: d.layers) {
            let W = Double(d.w), H = Double(d.h)
            for l in d.layers {
                for b in [Optional(l.pixels), l.maskPx].compactMap({ $0 }) {
                    guard let img = b.image(), let t = PixelBuffer(w: b.w, h: b.h) else { continue }
                    for dx in [-W / 2, W / 2] { for dy in [-H / 2, H / 2] {
                        t.ctx.saveGState(); t.ctx.translateBy(x: dx, y: dy)
                        t.drawUpright(img, in: CGRect(x: -dx, y: -dy, width: W, height: H))
                        t.ctx.restoreGState()
                    } }
                    memcpy(b.ptr, t.ptr, b.w * b.h * 4)
                }
            }
            tile = .both; tilePrev = true
            return true
        }
        say("Slid half way round. Tile mode is on, so what you paint at an edge comes back on the other.")
    }

    // MARK: vanishing points

    func vpBegin(at p: CGPoint) -> Bool {
        guard vpEdit, guide.points > 0 else { return false }
        let hit = 22 / max(0.05, scale)
        for (i, v) in guideVPs().enumerated() where hypot(Double(p.x - v.x), Double(p.y - v.y)) < hit { vpDrag = i; return true }
        return false
    }
    func vpMove(to p: CGPoint) {
        guard let i = vpDrag, var v = vps[guide.rawValue], v.indices.contains(i) else { return }
        v[i] = p; vps[guide.rawValue] = v
        stage?.updateOverlay()
    }
    func vpEnd() { vpDrag = nil; markChanged() }
}
