import SwiftUI
import UserNotifications

/// Calendar (his ask 11-24, S353·7b1e: "a calendar app in PL DEV for drops and reminders and stuff for you and I"): one shared list in
/// pl-cron (`/api/widget/calendar`, D1 `calendar_items`) that he writes here and the sessions write with the same widget keys, plus how
/// many posts the content calendar holds each day. Items with a time (and every drop, at 9 AM) remind him with a local notification.
@MainActor enum CalendarSection: PLSection {
    static let manifest = SectionManifest(id: "calendar", title: "Calendar", symbol: "calendar", needsKeys: ["widgetWrite"], needsOrigins: ["cron"])
    static let state = CalendarModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(SharedCalendarView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh {
        await state.load(model: model)
        return SectionRefresh(badge: state.todayOpen > 0 ? state.todayOpen : nil, notify: [])
    }
}

struct CalendarItem: Decodable, Identifiable, Hashable {
    let id: Int
    let date: String
    let time: String?
    let title: String
    let kind: String
    let by: String
    let note: String?
    let done: Int
}

@MainActor @Observable final class CalendarModel {
    private(set) var items: [CalendarItem] = []
    private(set) var posts: [String: Int] = [:]
    private(set) var loaded = false
    var problem: String?

    /// Today in Pacific time, as the server keeps its dates.
    static var today: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    var todayOpen: Int { items.filter { $0.date == Self.today && $0.done == 0 }.count }

    private func key(_ model: AppModel) -> String? { model.config?.key("widgetWrite") }

    func load(model: AppModel) async {
        guard let http = model.http, let key = key(model) else { problem = "The calendar needs the widget write key in your config."; return }
        struct Out: Decodable { let ok: Bool; let items: [CalendarItem]; let content: [Post]? }
        struct Post: Decodable { let date: String; let count: Int }
        do {
            let data = try await http.send(RequestPlan(origin: "cron", path: "api/widget/calendar", query: ["days": "90"]),
                                           extraHeaders: ["Authorization": "Bearer " + key])
            let out = try JSONDecoder().decode(Out.self, from: data)
            items = out.items
            posts = Dictionary((out.content ?? []).map { ($0.date, $0.count) }, uniquingKeysWith: { a, _ in a })
            problem = nil
            loaded = true
            scheduleReminders()
        } catch {
            problem = "The calendar did not load: " + plainSentence(error)
        }
    }

    func send(_ body: [String: Any], model: AppModel) async -> Bool {
        guard let http = model.http, let key = key(model), let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        do {
            _ = try await http.send(RequestPlan(origin: "cron", method: "POST", path: "api/widget/calendar",
                                                headers: ["content-type": "application/json"], body: data),
                                    idempotent: false, extraHeaders: ["Authorization": "Bearer " + key])
            await load(model: model)
            return true
        } catch {
            problem = "Not saved: " + plainSentence(error)
            return false
        }
    }

    /// One local notification per open item with a time (drops at 9 AM on the day). Replaces the earlier set each load.
    private func scheduleReminders() {
        // the Companion's pattern (no async notification calls, Swift 6 strict): forget the ids set last time, then set this load's
        let center = UNUserNotificationCenter.current(), d = UserDefaults.standard
        center.removePendingNotificationRequests(withIdentifiers: d.stringArray(forKey: "pldev.calendar.notified") ?? [])
        var set: [String] = []
        defer { d.set(set, forKey: "pldev.calendar.notified") }
        guard d.bool(forKey: "pldev.notify") else { return }
        let pt = TimeZone(identifier: "America/Los_Angeles")
        for item in items where item.done == 0 {
            let time = item.time ?? (item.kind == "drop" ? "09:00" : nil)
            guard let time else { continue }
            let d = item.date.split(separator: "-").compactMap { Int($0) }, t = time.split(separator: ":").compactMap { Int($0) }
            guard d.count == 3, t.count == 2 else { continue }
            var parts = DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1])
            parts.timeZone = pt
            guard let when = Calendar(identifier: .gregorian).date(from: parts), when > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.kind == "drop" ? "Drop today" : "Calendar"
            content.body = item.title
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "cal-\(item.id)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            set.append("cal-\(item.id)")
        }
    }
}

struct SharedCalendarView: View {
    let model: AppModel
    let state: CalendarModel
    @State private var adding = false

    init(model: AppModel, state: CalendarModel) {
        self.model = model
        self.state = state
    }

    private var days: [String] {
        let keys = Set(state.items.map(\.date)).union(state.posts.filter { $0.value > 0 }.map(\.key))
        return keys.filter { $0 >= CalendarModel.today }.sorted()
    }

    var body: some View {
        List {
            if let problem = state.problem {
                Text(problem).plFont(.footnote).foregroundStyle(.secondary)
            }
            if state.loaded && days.isEmpty {
                EmptyNote(symbol: "calendar", title: "Nothing ahead", detail: "Add a drop or a reminder, or ask a session to.",
                          actionTitle: "Add", action: { adding = true })
            }
            ForEach(days, id: \.self) { day in
                Section {
                    if let n = state.posts[day], n > 0 {
                        Label("\(n) post\(n == 1 ? "" : "s") scheduled", systemImage: "square.stack")
                            .plFont(.footnote).foregroundStyle(.secondary)
                            .listRowBackground(PLRowGround())
                    }
                    ForEach(state.items.filter { $0.date == day }) { item in
                        row(item)
                            .listRowBackground(PLRowGround())
                            .swipeActions(edge: .leading) {
                                Button(item.done == 0 ? "Done" : "Undo") {
                                    Task { _ = await state.send(["action": "done", "id": item.id, "done": item.done == 0], model: model) }
                                }
                                .tint(PLTone.accent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    Task { _ = await state.send(["action": "delete", "id": item.id], model: model) }
                                }
                            }
                    }
                } header: {
                    Text(Self.heading(day)).plTitle(.subhead)
                }
            }
        }
        .plGround()
        .plScreenTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus").frame(minWidth: PLMetric.touch, minHeight: PLMetric.touch) }
                    .accessibilityLabel("Add to the calendar")
            }
        }
        .refreshable { await state.load(model: model) }
        .task { if !state.loaded { await state.load(model: model) } }
        .sheet(isPresented: $adding) { CalendarAddSheet(model: model, state: state) }
    }

    private func row(_ item: CalendarItem) -> some View {
        HStack(alignment: .top, spacing: PLSpace.gap) {
            Image(systemName: Self.symbol(item.kind)).foregroundStyle(item.kind == "drop" ? PLTone.accent : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).plFont(.body).strikethrough(item.done == 1).foregroundStyle(item.done == 1 ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let time = item.time { Text(Self.time12(time)) }
                    Text(item.by == "claude" ? "Claude" : "You")
                    Text(item.kind.capitalized)
                }
                .plFont(.caption).foregroundStyle(.secondary)
                if let note = item.note, !note.isEmpty { Text(note).plFont(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: PLMetric.touch)
        .accessibilityElement(children: .combine)
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "drop": return "bag"
        case "content": return "film"
        case "task": return "checklist"
        case "reminder": return "bell"
        default: return "circle"
        }
    }

    static func time12(_ hhmm: String) -> String {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return hhmm }
        let h = p[0] % 12 == 0 ? 12 : p[0] % 12
        return String(format: "%d:%02d %@", h, p[1], p[0] < 12 ? "AM" : "PM")
    }

    static func heading(_ day: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return day }
        if day == CalendarModel.today { return "Today" }
        f.dateFormat = "EEE MMM d"
        return f.string(from: d)
    }
}

struct CalendarAddSheet: View {
    let model: AppModel
    let state: CalendarModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var day = Date()
    @State private var timed = false
    @State private var time = Date()
    @State private var kind = "reminder"
    @State private var note = ""
    @State private var saving = false

    init(model: AppModel, state: CalendarModel) {
        self.model = model
        self.state = state
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What", text: $title)
                Picker("Kind", selection: $kind) {
                    Text("Reminder").tag("reminder"); Text("Drop").tag("drop"); Text("Content").tag("content"); Text("Task").tag("task")
                }
                DatePicker("Day", selection: $day, displayedComponents: .date)
                Toggle("At a time", isOn: $timed)
                if timed { DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute) }
                TextField("Note (optional)", text: $note, axis: .vertical)
                if let problem = state.problem { Text(problem).font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            var body: [String: Any] = ["action": "add", "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       "kind": kind, "by": "him", "date": Self.ymd(day)]
                            if timed { body["time"] = Self.hm(time) }
                            if !note.isEmpty { body["note"] = note }
                            if await state.send(body, model: model) { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
        }
    }

    /// The day as he picked it on his phone's calendar (local), sent as the date the server stores.
    static func ymd(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func hm(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
