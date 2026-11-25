import PhotosUI
import SwiftUI

// His own colours for the vote (his ask 11-24, S353·7b1e): "add more colours based off hex codes and a colour catcher camera feature,
// so I can capture colours and capture votes". Both add to PickModel.custom; the catcher can cast the vote at once.

/// Type a hex code, see it, add it.
struct PickHexSheet: View {
    let state: PickModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    init(state: PickModel) { self.state = state }

    private var hex: String? { PickModel.normalHex(text) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("#1A2B3C", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.title3, design: .monospaced))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(hex.flatMap { Color(hex: $0) } ?? Color.secondary.opacity(0.15))
                    .frame(height: 120)
                    .overlay { if hex == nil { Text("Six hex digits").font(.footnote).foregroundStyle(.secondary) } }
                    .accessibilityHidden(true)
            }
            .navigationTitle("Add a colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { if state.addColour(text) { dismiss() } }.disabled(hex == nil)
                }
            }
        }
    }
}

/// A photo from the camera or the library; he taps where the colour is, and it is sampled (a small spot, averaged).
struct PickCatcher: View {
    let state: PickModel
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var caught: String?
    @State private var shooting = false
    @State private var item: PhotosPickerItem?

    init(state: PickModel, model: AppModel) {
        self.state = state
        self.model = model
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: PLSpace.margin) {
                if let image {
                    GeometryReader { geo in
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { p in caught = Self.sample(image, at: p, in: geo.size) }
                    }
                    .accessibilityLabel("Your photo. Tap where the colour is.")
                    Text("Tap where the colour is.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Spacer()
                    Image(systemName: "eyedropper.halffull").font(.system(size: 54)).foregroundStyle(.secondary)
                    Text("Take a photo or pick one, then tap the colour you want.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Spacer()
                }
                if let caught {
                    HStack(spacing: PLSpace.margin) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: caught) ?? .gray).frame(width: 64, height: 64)
                        Text(caught.uppercased()).font(.system(.title3, design: .monospaced))
                        Spacer()
                    }
                    HStack {
                        Button("Add") { state.addColour(caught); dismiss() }
                            .buttonStyle(.bordered).frame(minHeight: PLMetric.touch)
                        Button("Add and vote") {
                            state.addColour(caught)
                            state.selected = PickModel.hexName(caught)
                            Task { await state.vote(model: model); dismiss() }
                        }
                        .buttonStyle(.borderedProminent).frame(minHeight: PLMetric.touch)
                    }
                }
                HStack {
                    if CaptureCamera.available {
                        Button { shooting = true } label: { Label("Camera", systemImage: "camera") }
                            .buttonStyle(.bordered).frame(minHeight: PLMetric.touch)
                    }
                    PhotosPicker(selection: $item, matching: .images) { Label("Photos", systemImage: "photo") }
                        .buttonStyle(.bordered).frame(minHeight: PLMetric.touch)
                }
            }
            .padding(PLSpace.margin)
            .navigationTitle("Catch a colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fullScreenCover(isPresented: $shooting) {
                CaptureCamera { data in image = UIImage(data: data); caught = nil }.ignoresSafeArea()
            }
            .onChange(of: item) { _, new in
                Task {
                    if let data = try? await new?.loadTransferable(type: Data.self), let img = UIImage(data: data) { image = img; caught = nil }
                }
            }
        }
    }

    /// The colour under a tap on a scaled-to-fit photo: a spot about 1/60 of the photo's width, averaged, as "#rrggbb".
    static func sample(_ img: UIImage, at p: CGPoint, in box: CGSize) -> String? {
        let s = img.size
        guard s.width > 0, s.height > 0, box.width > 0, box.height > 0 else { return nil }
        let scale = min(box.width / s.width, box.height / s.height)
        let ox = (box.width - s.width * scale) / 2, oy = (box.height - s.height * scale) / 2
        let x = (p.x - ox) / scale, y = (p.y - oy) / scale
        guard x >= 0, y >= 0, x < s.width, y < s.height else { return nil }
        let spot = max(2, s.width / 60)
        var px = [UInt8](repeating: 0, count: 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.translateBy(x: 0, y: 1)
            ctx.scaleBy(x: 1, y: -1)   // UIKit drawing is top-down; the bitmap is bottom-up
            UIGraphicsPushContext(ctx)
            img.draw(in: CGRect(x: -(x - spot / 2) / spot, y: -(y - spot / 2) / spot, width: s.width / spot, height: s.height / spot))
            UIGraphicsPopContext()
            return true
        }
        guard ok else { return nil }
        return String(format: "#%02x%02x%02x", px[0], px[1], px[2])
    }
}
