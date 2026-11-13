import BackgroundTasks
import Foundation
import UIKit

/// Quiet hours as plain arithmetic on minutes of the day, so it can be checked without a clock.
enum Quiet {
    /// "HH:mm" to minutes after midnight; nil when the text is not a time.
    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    static func text(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    /// True inside the window. A window that crosses midnight (22:00 to 07:00) wraps; equal ends mean no window.
    static func isQuiet(now: Int, from: Int, to: Int) -> Bool {
        if from == to { return false }
        return from < to ? (now >= from && now < to) : (now >= from || now < to)
    }

    static func isQuietNow(from: String, to: String, date: Date = Date()) -> Bool {
        guard let start = minutes(from), let end = minutes(to) else { return false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return isQuiet(now: (parts.hour ?? 0) * 60 + (parts.minute ?? 0), from: start, to: end)
    }

    /// The arithmetic checked against known answers; run once in debug builds when the poller is made.
    static func selfCheck() -> Bool {
        isQuiet(now: 23 * 60, from: 22 * 60, to: 7 * 60)
            && isQuiet(now: 6 * 60 + 59, from: 22 * 60, to: 7 * 60)
            && !isQuiet(now: 7 * 60, from: 22 * 60, to: 7 * 60)
            && !isQuiet(now: 12 * 60, from: 22 * 60, to: 7 * 60)
            && isQuiet(now: 13 * 60, from: 12 * 60, to: 14 * 60)
            && !isQuiet(now: 14 * 60, from: 12 * 60, to: 14 * 60)
            && !isQuiet(now: 5, from: 60, to: 60)
            && minutes("07:05") == 425 && minutes("24:00") == nil && minutes("x") == nil
            && text(425) == "07:05"
    }
}

/// Asks every ready section to refresh: on a timer while the app is open, and when the system grants a background refresh.
/// Raises each section's notices through the hub, subject to the master switch, the per-type switch and quiet hours.
@MainActor final class Poller {
    static let shared = Poller()
    static let taskID = "com.psychedluxuries.dev.refresh"   // must match BGTaskSchedulerPermittedIdentifiers in the Info.plist
    private static let interval: Duration = .seconds(120)

    private var loop: Task<Void, Never>?
    private var refreshing = false

    private init() {
        assert(Quiet.selfCheck(), "quiet hours arithmetic")
    }

    /// The app came to the front: refresh now, then on the timer.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: Poller.interval)
            }
        }
    }

    /// The app left the front: stop the timer and ask the system for a background refresh.
    func stop() {
        loop?.cancel()
        loop = nil
        if AppModel.shared.config != nil { schedule() }   // with no config there is nothing to refresh
    }

    /// Nil when the system took the request, else the reason. The system alone decides when (and whether) it runs.
    @discardableResult
    func schedule() -> String? {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// What the background task runs: ask for the next one first, then refresh.
    func backgroundRefresh() async {
        schedule()
        await AppModel.shared.restoreIfNeeded()
        await refreshAll()
    }

    /// One pass over the ready sections. With no config loaded this does nothing at all: no request leaves the phone.
    func refreshAll() async {
        let model = AppModel.shared
        guard model.config != nil, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        for entry in model.sections where entry.readiness.isReady {
            guard let section = SectionRegistry.section(entry.id) else { continue }
            let result = await section.refresh(model: model)
            model.setBadge(result.badge, for: entry.id)
            for notice in result.notify { await raise(notice) }
        }
        await model.drainInbox()
        model.writeSnapshot()
    }

    private func raise(_ notice: LocalNotice) async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "pldev.notify") else { return }
        let type = notice.category ?? NotificationHub.generalType
        if defaults.object(forKey: "pldev.notify." + type) != nil, !defaults.bool(forKey: "pldev.notify." + type) { return }   // unset means on
        let from = defaults.string(forKey: "pldev.quietFrom") ?? ""
        let to = defaults.string(forKey: "pldev.quietTo") ?? ""
        if Quiet.isQuietNow(from: from, to: to) { return }
        if let refused = await NotificationHub.shared.post(id: notice.id, title: notice.title, body: notice.body,
                                                           category: notice.category, link: notice.link?.url.absoluteString) {
            model(note: "notice not shown: " + refused)
        }
    }

    private func model(note: String) {
        AppModel.shared.debug.note("notify", note)
    }
}
