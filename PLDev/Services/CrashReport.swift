import Foundation
import MetricKit

/// A crash cannot report itself, so iOS hands its record to the app the next time it opens (MetricKit).
/// Each one goes to the debug log as one line: what killed the app and the app's own frames, so a crash he
/// sees on the phone reaches the session without him digging in Settings (11-14: Paint died while a stroke was adjusted).
final class CrashReport: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {   // no stored state
    static let shared = CrashReport()

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let lines = payloads.flatMap { $0.crashDiagnostics ?? [] }.map(Self.line)
        guard !lines.isEmpty else { return }
        Task { @MainActor in for l in lines { AppModel.shared.debug.note("crash error", l) } }
    }

    static func line(_ c: MXCrashDiagnostic) -> String {
        var parts = ["build \(c.metaData.applicationBuildVersion)"]
        if let t = c.exceptionType { parts.append("exception \(t)") }
        if let s = c.signal { parts.append("signal \(s)") }
        if let r = c.terminationReason { parts.append(String(r.prefix(300))) }
        parts.append("frames " + appFrames(c.callStackTree.jsonRepresentation()))
        return parts.joined(separator: " | ")
    }

    /// The crashed thread's frames inside the app, as offsets a dSYM can turn back into lines.
    static func appFrames(_ json: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]] else { return "?" }
        let crashed = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
        var out: [String] = []
        func walk(_ frames: [[String: Any]]) {
            for f in frames where out.count < 12 {
                let bin = f["binaryName"] as? String ?? "?"
                if bin.hasPrefix("PLDev") { out.append("\(bin)+\(f["offsetIntoBinaryTextSegment"] ?? "?")") }
                if let sub = f["subFrames"] as? [[String: Any]] { walk(sub) }
            }
        }
        walk(crashed?["callStackRootFrames"] as? [[String: Any]] ?? [])
        return out.isEmpty ? "none in the app" : out.joined(separator: " ")
    }
}
