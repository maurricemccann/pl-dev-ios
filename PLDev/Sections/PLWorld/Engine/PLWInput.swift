import SwiftUI
import GameController
import simd

/// Everything the player does, in one place: the touch layout (left floating stick, right drag to look, short tap to jump, JUMP and ACT buttons)
/// and a real pad when one is connected. The runtime calls `sample()` once a frame; edges (a press) are returned once and cleared.
@MainActor final class PLWInput {
    struct Sample {
        var move: SIMD2<Float> = .zero         // x right, y forward, each -1...1
        var lookYaw: Float = 0, lookPitch: Float = 0   // radians since the last frame (positive yaw turns the view left, positive pitch looks up)
        var jumpPressed = false, jumpHeld = false
        var actPressed = false, actHeld = false
    }

    var move: SIMD2<Float> = .zero
    private var lookYaw: Float = 0, lookPitch: Float = 0
    private var jumpDown = false, jumpEdge = false, actDown = false, actEdge = false
    private var padJump = false, padAct = false

    func look(dx: CGFloat, dy: CGFloat) { lookYaw -= Float(dx) * 0.0035; lookPitch -= Float(dy) * 0.0035 }
    func jump(_ on: Bool) { if on && !jumpDown { jumpEdge = true }; jumpDown = on }
    func tapJump() { jumpEdge = true }
    func act(_ on: Bool) { if on && !actDown { actEdge = true }; actDown = on }

    func sample() -> Sample {
        var s = Sample(move: move, lookYaw: lookYaw, lookPitch: lookPitch, jumpPressed: jumpEdge, jumpHeld: jumpDown, actPressed: actEdge, actHeld: actDown)
        lookYaw = 0; lookPitch = 0; jumpEdge = false; actEdge = false
        if let pad = GCController.controllers().compactMap(\.extendedGamepad).first {
            let l = SIMD2<Float>(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value)
            if simd_length(l) > 0.12 { s.move = l }
            s.lookYaw -= pad.rightThumbstick.xAxis.value * 0.045; s.lookPitch += pad.rightThumbstick.yAxis.value * 0.03
            let j = pad.buttonA.isPressed, a = pad.buttonX.isPressed || pad.buttonB.isPressed
            if j && !padJump { s.jumpPressed = true }; if a && !padAct { s.actPressed = true }
            padJump = j; padAct = a
            s.jumpHeld = s.jumpHeld || j; s.actHeld = s.actHeld || a
        }
        return s
    }
}

/// The touch layer. The left thumb walks with a stick that appears where it lands, the right thumb looks (a short tap there jumps), and the two
/// buttons are smaller and spaced apart (his note: "the controls are cramped").
struct PLWControls: View {
    let input: PLWInput
    @State private var stickBase: CGPoint?
    @State private var knob: CGSize = .zero
    @State private var lookLast: CGSize = .zero
    @State private var lookStart: Date?
    private let reach: CGFloat = 50

    var body: some View {
        GeometryReader { g in
            ZStack {
                HStack(spacing: 0) {
                    Color.clear.frame(width: g.size.width * 0.45).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("plwpad"))
                            .onChanged { v in
                                if stickBase == nil { stickBase = v.startLocation }
                                let dx = v.location.x - v.startLocation.x, dy = v.location.y - v.startLocation.y
                                let mag = max(1, hypot(dx, dy)), k = min(mag, reach) / mag
                                knob = CGSize(width: dx * k, height: dy * k)
                                input.move = SIMD2(Float(knob.width / reach), Float(-knob.height / reach))
                            }
                            .onEnded { _ in stickBase = nil; knob = .zero; input.move = .zero })
                        .accessibilityLabel("Walk").accessibilityHint("Drag with the left thumb")
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                if lookStart == nil { lookStart = Date() }
                                input.look(dx: v.translation.width - lookLast.width, dy: v.translation.height - lookLast.height)
                                lookLast = v.translation
                            }
                            .onEnded { v in
                                if hypot(v.translation.width, v.translation.height) < 10, let t = lookStart, Date().timeIntervalSince(t) < 0.28 { input.tapJump() }
                                lookLast = .zero; lookStart = nil
                            })
                        .accessibilityLabel("Look").accessibilityHint("Drag with the right thumb, tap to jump")
                }
                if let stickBase {
                    ZStack {
                        Circle().fill(.white.opacity(0.06)).overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5)).frame(width: 116, height: 116)
                        Circle().fill(.white.opacity(0.45)).frame(width: 46, height: 46).offset(knob)
                    }
                    .position(stickBase).allowsHitTesting(false)
                }
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                    button("JUMP", size: 60) { input.jump($0) }.padding(.trailing, 26).padding(.bottom, 34)
                    button("ACT", size: 52) { input.act($0) }.padding(.trailing, 26 + 60 + 22).padding(.bottom, 34 + 34)
                }
            }
            .coordinateSpace(name: "plwpad")
        }
    }

    private func button(_ label: String, size: CGFloat, _ set: @escaping (Bool) -> Void) -> some View {
        PLWHoldButton(label: label, size: size, set: set)
    }
}

private struct PLWHoldButton: View {
    let label: String, size: CGFloat, set: (Bool) -> Void
    @State private var down = false
    var body: some View {
        Text(label).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.9))
            .frame(width: size, height: size)
            .background(Circle().fill(.white.opacity(down ? 0.32 : 0.14))).overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.2))
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in if !down { down = true; set(true) } }.onEnded { _ in down = false; set(false) })
            .accessibilityLabel(label == "JUMP" ? "Jump" : "Act").accessibilityAddTraits(.isButton)
    }
}
