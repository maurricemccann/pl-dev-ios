import SwiftUI

/// The capability probe: each thing this install may or may not be able to do, run on this iPhone, with the reason when it fails.
/// Nothing is believed until it passes here.
struct ProbeView: View {
    let probe: ProbeModel
    let showsDone: Bool   // true when shown as a sheet, which needs its own way out
    @Environment(\.dismiss) private var dismiss
    @State private var runTick = 0
    @State private var runningAll = false

    init(probe: ProbeModel, showsDone: Bool) {
        self.probe = probe
        self.showsDone = showsDone
    }

    private var passed: Int {
        probe.items.filter { if case .pass = $0.result { return true } else { return false } }.count
    }

    var body: some View {
        List {
            if probe.items.isEmpty {
                EmptyNote(symbol: "stethoscope", title: "No checks yet", detail: "Load a config and the checks appear here.")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(probe.items) { item in
                        row(item)
                    }
                } footer: {
                    Text("\(passed) of \(probe.items.count) passed. A result never shows an address or a key.")
                        .plFont(.footnote)
                }
            }
        }
        .refreshable { await runAll() }
        .plScreenTitle("Probes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await runAll() }
                } label: {
                    Text("Run all").plFont(.body)
                }
                .disabled(runningAll || probe.items.isEmpty)
            }
            if showsDone {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done").plFont(.body, emphasized: true)
                    }
                }
            }
        }
        .sensoryFeedback(PLHaptic.commit, trigger: runTick)
    }

    private func runAll() async {
        guard !runningAll else { return }
        runningAll = true
        runTick += 1
        await probe.runAll()
        runningAll = false
    }

    private func row(_ item: ProbeModel.Item) -> some View {
        let id = item.id
        return VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .plFont(.headline)
                .foregroundStyle(.primary)
            if !item.detail.isEmpty {
                Text(item.detail)
                    .plFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            resultLine(item.result)
            Button {
                runTick += 1
                Task { await probe.run(id) }
            } label: {
                Text("Run")
                    .plFont(.callout, emphasized: true)
                    .padding(.horizontal, 18)
                    .frame(minHeight: PLMetric.touch)
                    .contentShape(Capsule())
            }
            .buttonStyle(.bordered)
            .disabled(probe.isRunning(item))
            .accessibilityLabel("Run \(item.title)")
        }
        .padding(.vertical, PLSpace.tight)
    }

    @ViewBuilder
    private func resultLine(_ result: ProbeModel.Item.Result) -> some View {
        switch result {
        case .untested:
            NoteLine(symbol: "circle", tint: PLTone.quiet, text: "Not run yet")
        case .running:
            NoteLine(symbol: "ellipsis.circle", tint: PLTone.quiet, text: "Running")
        case .pass(let detail):
            NoteLine(symbol: "checkmark.circle.fill", tint: PLTone.good, text: detail.isEmpty ? "Passed" : "Passed: \(detail)")
        case .fail(let reason):
            NoteLine(symbol: "xmark.circle.fill", tint: PLTone.bad, text: "Failed: \(reason)")
        }
    }
}
