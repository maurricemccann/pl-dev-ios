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

/// The calendars (config over the air, S353·7b1e): the feed's `calendar.kinds` when it lists any, else build 380's four.
/// pl-cron stores any kind id shaped ^[a-z0-9-]{1,24}$ (its b8fd54e); ThemeFeed drops feed kinds of any other shape.
enum CalendarKinds {
    static let builtIn: [ThemeFeed.CalendarKind] = [
        .init(id: "reminder", label: "Reminder", symbol: "bell", accent: false, time: nil),
        .init(id: "drop", label: "Drop", symbol: "bag", accent: true, time: "09:00"),
        .init(id: "content", label: "Content", symbol: "film", accent: false, time: nil),
        .init(id: "task", label: "Task", symbol: "checklist", accent: false, time: nil)]
    static var all: [ThemeFeed.CalendarKind] { ThemeFeed.calendarKinds ?? builtIn }
    static func find(_ id: String) -> ThemeFeed.CalendarKind? { all.first { $0.id == id } ?? builtIn.first { $0.id == id } }
    static func symbol(_ id: String) -> String { find(id)?.symbol ?? "circle" }
    static func accent(_ id: String) -> Bool { find(id)?.accent ?? false }
    static func label(_ id: String) -> String { find(id)?.label ?? id.capitalized }
    static var standard: String {
        let d = ThemeFeed.calendarDefault ?? "reminder"
        return all.contains { $0.id == d } ? d : (all.first?.id ?? "reminder")
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

    /// The first day of this month in Pacific time; the grid's window starts at the month on screen (`from`).
    static var thisMonth: String { String(today.prefix(8)) + "01" }
    private(set) var from = CalendarModel.thisMonth

    func load(model: AppModel, from: String? = nil) async {
        guard let http = model.http, let key = key(model) else { problem = "The calendar needs the widget write key in your config."; return }
        struct Out: Decodable { let ok: Bool; let items: [CalendarItem]; let content: [Post]? }
        struct Post: Decodable { let date: String; let count: Int }
        let start = from ?? self.from
        do {
            let data = try await http.send(RequestPlan(origin: "cron", path: "api/widget/calendar", query: ["from": start, "days": String(ThemeFeed.calendarDays ?? 120)]),
                                           extraHeaders: ["Authorization": "Bearer " + key])
            let out = try JSONDecoder().decode(Out.self, from: data)
            items = out.items
            posts = Dictionary((out.content ?? []).map { ($0.date, $0.count) }, uniquingKeysWith: { a, _ in a })
            self.from = start
            problem = nil
            loaded = true
            // only a window that starts this month holds every reminder still ahead; another month would drop some
            if start == Self.thisMonth { scheduleReminders() }
        } catch {
            // a re-run load (pull to refresh, a month change) cancels this one: keep the last good items, say nothing.
            // Task.isCancelled, not URLError.cancelled: a refused certificate also ends as URLError.cancelled and must still show.
            if Task.isCancelled || error is CancellationError { return }
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
            if Task.isCancelled || error is CancellationError { return false }   // cancelled, not refused: no false sentence
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
            let time = item.time ?? CalendarKinds.find(item.kind)?.time   // build 380: drops at 09:00, the rest only with a time
            guard let time else { continue }
            let d = item.date.split(separator: "-").compactMap { Int($0) }, t = time.split(separator: ":").compactMap { Int($0) }
            guard d.count == 3, t.count == 2 else { continue }
            var parts = DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1])
            parts.timeZone = pt
            guard let when = Calendar(identifier: .gregorian).date(from: parts), when > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.kind == "drop" ? ThemeFeed.text("calendar.dropNotice", "Drop today") : ThemeFeed.text("calendar.notice", "Calendar")
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
    @State private var selected = CalendarModel.today
    @State private var month = CalendarModel.thisMonth   // yyyy-MM-01 of the month on screen

    init(model: AppModel, state: CalendarModel) {
        self.model = model
        self.state = state
    }

    /// The grid reads Pacific days, as the server keeps them.
    private static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }
    static func date(_ k: String) -> Date? {
        let p = k.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }
    static func key(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private var dayItems: [CalendarItem] { state.items.filter { $0.date == selected } }

    var body: some View {
        List {
            Section {
                monthGrid
                    .listRowBackground(PLRowGround())
                    .listRowInsets(EdgeInsets(top: PLSpace.pad, leading: PLSpace.gap, bottom: PLSpace.pad, trailing: PLSpace.gap))
            }
            if let problem = state.problem {
                Text(problem).plFont(.footnote).foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
            Section {
                if let n = state.posts[selected], n > 0 {
                    Label("\(n) post\(n == 1 ? "" : "s") scheduled", systemImage: "square.stack")
                        .plFont(.footnote).foregroundStyle(.secondary)
                        .listRowBackground(PLRowGround())
                }
                if state.loaded && dayItems.isEmpty {
                    Button { adding = true } label: {
                        Label(ThemeFeed.text("calendar.empty", "Nothing on this day. Add one"), systemImage: "plus.circle")
                            .plFont(.callout).frame(maxWidth: .infinity, minHeight: PLMetric.touch, alignment: .leading)
                    }
                    .tint(PLTone.accent)
                    .listRowBackground(PLRowGround())
                }
                ForEach(dayItems) { item in
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
                Text(Self.heading(selected)).plTitle(.subhead)
            }
        }
        .plGround()
        .plScreenTitle(ThemeFeed.text("calendar.title", "Calendar"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") { select(CalendarModel.today) }
                    .tint(PLTone.accent)
                    .disabled(selected == CalendarModel.today && month == CalendarModel.thisMonth)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus").frame(minWidth: PLMetric.touch, minHeight: PLMetric.touch) }
                    .accessibilityLabel("Add to the calendar")
            }
        }
        .refreshable { await state.load(model: model, from: month) }
        .task(id: month) { if !state.loaded || state.from != month { await state.load(model: model, from: month) } }
        .sheet(isPresented: $adding) { CalendarAddSheet(model: model, state: state, day: Self.date(selected) ?? Date()) }
    }

    // MARK: the month (Apple's Calendar month view: the month name, a weekday row, numbers in circles, a dot per day that has something)

    private var monthGrid: some View {
        let cal = Self.cal
        let first = Self.date(month) ?? Date()
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let symbols = cal.veryShortWeekdaySymbols
        let weekdays = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        let prefix = String(month.prefix(8))
        return VStack(spacing: PLSpace.gap) {
            HStack {
                Text(first.formatted(.dateTime.month(.wide).year())).plTitle(.title3)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: PLMetric.touch, height: PLMetric.touch) }
                    .accessibilityLabel("Previous month")
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: PLMetric.touch, height: PLMetric.touch) }
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.plain).foregroundStyle(PLTone.accent)
            HStack(spacing: 0) {
                ForEach(weekdays.indices, id: \.self) { i in
                    Text(weekdays[i]).plFont(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: PLSpace.tight) {
                ForEach(0..<(lead + count), id: \.self) { i in
                    if i < lead { Color.clear.frame(height: PLMetric.touch + 8) }
                    else { dayCell(prefix + String(format: "%02d", i - lead + 1)) }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if abs(v.translation.width) > 60 { shift(v.translation.width < 0 ? 1 : -1) }
        })
    }

    private func dayCell(_ k: String) -> some View {
        let isToday = k == CalendarModel.today, isSelected = k == selected
        let open = state.items.filter { $0.date == k && $0.done == 0 }
        let hasDrop = open.contains { CalendarKinds.accent($0.kind) }   // the accent dot: drops in build 380, any accent calendar from the feed
        let hasOther = open.contains { !CalendarKinds.accent($0.kind) } || (state.posts[k] ?? 0) > 0
        return Button { selected = k } label: {
            VStack(spacing: 3) {
                Text("\(Int(k.suffix(2)) ?? 0)")
                    .plFont(.callout, emphasized: isToday || isSelected)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : isToday ? PLTone.accent : k < CalendarModel.today ? Color.secondary : Color.primary)
                    .frame(width: 36, height: 36)
                    .background { if isSelected { Circle().fill(isToday ? PLTone.accent : Color.primary) } }
                HStack(spacing: 3) {
                    if hasDrop { Circle().fill(PLTone.accent).frame(width: 5, height: 5) }
                    if hasOther { Circle().fill(Color.secondary).frame(width: 5, height: 5) }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: PLMetric.touch + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility(k, open: open.count, drop: hasDrop))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibility(_ k: String, open: Int, drop: Bool) -> String {
        var parts = [Self.heading(k)]
        if open > 0 { parts.append("\(open) item\(open == 1 ? "" : "s")") }
        if drop { parts.append("a drop") }
        if let n = state.posts[k], n > 0 { parts.append("\(n) post\(n == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    private func shift(_ n: Int) {
        guard let d = Self.date(month), let m = Self.cal.date(byAdding: .month, value: n, to: d) else { return }
        withAnimation(.snappy) { month = String(Self.key(m).prefix(8)) + "01" }
        selected = month == CalendarModel.thisMonth ? CalendarModel.today : month
    }

    private func select(_ k: String) {
        withAnimation(.snappy) { month = String(k.prefix(8)) + "01" }
        selected = k
    }

    private func row(_ item: CalendarItem) -> some View {
        HStack(alignment: .top, spacing: PLSpace.gap) {
            Image(systemName: CalendarKinds.symbol(item.kind)).foregroundStyle(CalendarKinds.accent(item.kind) ? PLTone.accent : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).plFont(.body).strikethrough(item.done == 1).foregroundStyle(item.done == 1 ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let time = item.time { Text(Self.time12(time)) }
                    Text(item.by == "claude" ? "Claude" : "You")
                    Text(CalendarKinds.label(item.kind))
                }
                .plFont(.caption).foregroundStyle(.secondary)
                if let note = item.note, !note.isEmpty { Text(note).plFont(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: PLMetric.touch)
        .accessibilityElement(children: .combine)
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
    @State private var kind = CalendarKinds.standard
    @State private var note = ""
    @State private var saving = false

    /// Opens on the day picked in the grid.
    init(model: AppModel, state: CalendarModel, day: Date = Date()) {
        self.model = model
        self.state = state
        _day = State(initialValue: day)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What", text: $title)
                Picker("Kind", selection: $kind) {
                    ForEach(CalendarKinds.all, id: \.id) { k in Text(CalendarKinds.label(k.id)).tag(k.id) }
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
