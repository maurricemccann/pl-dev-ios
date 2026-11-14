import SwiftUI

/// The tools that sit beside the brush: Facet and Curve, Node mode, Echo Fill, Light one, Lights off, Other ground, the tile guides, Seam mode
/// with its print files, and the Hand Trace. Each is the laptop's own (see the file named in its footer); the ones that need a tap on the picture
/// close this sheet and wait for it.
struct NativeMoreToolsSheet: View {
    @Bindable var canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Facet and Curve: all strokes faceted", isOn: $canvas.facet)
                    Button { dismiss(); canvas.toggleFacetNext() } label: { Label(canvas.facetNext ? "Facet the next stroke: on" : "Facet the next stroke", systemImage: "hexagon") }
                    Toggle("Node mode", isOn: Binding(get: { canvas.nodeOn }, set: { on in canvas.toggleNodes(on); if on { dismiss() } }))
                    Stepper("Most nodes on a line: \(canvas.nodeMax)", value: $canvas.nodeMax, in: 3...40)
                } header: { Text("Strokes") } footer: {
                    Text("Facet draws a stroke again as straight segments with rounded corners. Node mode puts nodes on the line you just drew: drag one and the line is drawn again through the new path. Touch another line to give it the nodes.")
                }
                Section {
                    Button { dismiss(); canvas.toggleEcho(true) } label: { Label("Echo Fill", systemImage: "circle.dashed.inset.filled") }
                    Button { dismiss(); canvas.toggleLightOne(true) } label: { Label("Light one", systemImage: "lightbulb.max") }
                    Toggle("Lights off", isOn: Binding(get: { canvas.lightsOff }, set: { _ in canvas.toggleLightsOff() }))
                    Button { dismiss(); canvas.otherGround() } label: { Label("Other ground", systemImage: "circle.lefthalf.filled") }
                } header: { Text("Fill and light") } footer: {
                    Text("Echo Fill fills a closed shape with concentric lines. Light one makes a shape the lit cell: a new glowing layer. Lights off dims everything that does not glow. Other ground puts the same marks on the other ground, cream to black and back.")
                }
                Section {
                    Picker("Tile mode", selection: $canvas.tile) { ForEach(TileMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                    Toggle("Smart tile guides", isOn: $canvas.tileGuides)
                    Toggle("Show the tiles around", isOn: $canvas.tilePrev)
                    Button { dismiss(); canvas.makeTile() } label: { Label("Make tile (slide half way round)", systemImage: "square.grid.3x3") }
                } header: { Text("Tile") } footer: {
                    Text("With tile mode on, a line that leaves one edge comes back on the other. The guides show where it comes out, a gate where an end is missing its partner, and the middle cross where the old seams lie.")
                }
                Section {
                    if let s = canvas.seam {
                        LabeledContent("Template", value: s.name)
                        Toggle("Seam mode: marks carry across sewn edges", isOn: Binding(get: { canvas.seamOn }, set: { _ in canvas.toggleSeam() }))
                        Button { dismiss(); Task { try? await Task.sleep(for: .milliseconds(400)); canvas.seamPrintFiles() } } label: { Label("Save print files", systemImage: "square.and.arrow.up.on.square") }
                    } else {
                        Text("Seam mode needs a garment template. Start a new canvas and choose Hoodie 717 zip.").font(.footnote).foregroundStyle(.secondary)
                        Button { dismiss(); canvas.panel = .newCanvas } label: { Label("New canvas", systemImage: "plus") }
                    }
                } header: { Text("Seams") } footer: {
                    Text("Printful's pieces on one sheet. Print files cuts each piece from the sheet and scales it to the size Printful takes, with the template guide left out.")
                }
                Section {
                    Button { dismiss(); Task { try? await Task.sleep(for: .milliseconds(400)); canvas.handTrace() } } label: { Label("Hand trace", systemImage: "scribble.variable") }
                } header: { Text("Record") } footer: {
                    Text("A one-page record of how the piece was drawn, made from its own stroke log. It shows the hand at work. It does not prove who drew it.")
                }
                if let l = canvas.line { Section { ResultLine(text: l) } }
            }
            .navigationTitle("More tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { canvas.savePrefs(); canvas.stage?.updateOverlay(); canvas.markChanged(); dismiss() } } }
        }
    }
}
