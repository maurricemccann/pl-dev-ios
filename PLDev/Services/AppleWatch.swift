import Foundation
import UserNotifications

/// The apple lane (11-13): every event across the house that deserves a notice and has no section to raise it, in one place.
/// The poller calls `pass` once per refresh (open app: every 2 minutes; background: whenever iOS grants a BGAppRefreshTask).
/// Notices are local (the account is free: no push, no Time Sensitive). Each kind has its own switch in Settings, and the
/// poller applies the master switch and quiet hours. The first pass after install only learns the counts: it raises nothing,
/// so a fresh install does not announce the whole backlog.
/// Also drains the widget's button taps (AppleActionQueue) and keeps the interactive widget's glance current.
@MainActor enum AppleWatch {
    /// Notice type → the words Settings shows beside its switch. Types other lanes declared are listed too.
    static let labels: [String: String] = [
        "drafts": "Drafts waiting (House)",
        "apple.dm": "Member messages (House)",
        "apple.support": "Support mail (House)",
        "apple.order": "New orders (Shop)",
        "apple.drop": "Drops chosen (Shop)",
        "apple.comments": "Comments to post (House)",
        "apple.reports": "Reports to moderate (Congregation)",
        "shop.new": "New pieces in the shop",
        "congregation.held": "Posts waiting in the room",
        "congregation.activity": "Your Congregation activity",
        "composer": "Renders moving (Composer)",
        "practice": "Practice evening reminder",
        "apple.stack": "Stack health failed",
        "apple.pc": "The PC: hot, low disk or memory",
        "apple.curate": "New Curate batch (Library)",
    ]
    static func label(for type: String) -> String { labels[type] ?? type }

    private static var d: UserDefaults { .standard }

    // MARK: categories and buttons

    static func categories() -> Set<UNNotificationCategory> {
        registerActions()
        let reply = UNTextInputNotificationAction(identifier: "apple.dm.reply", title: "Reply", options: [.authenticationRequired],
                                                  icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Your reply")
        let resolve = UNNotificationAction(identifier: "apple.support.resolve", title: "Mark resolved", options: [.authenticationRequired],
                                           icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let again = UNNotificationAction(identifier: "apple.stack.run", title: "Run the check again", options: [],
                                         icon: UNNotificationActionIcon(systemImageName: "arrow.clockwise"))
        func plain(_ id: String) -> UNNotificationCategory { UNNotificationCategory(identifier: id, actions: [], intentIdentifiers: []) }
        return [UNNotificationCategory(identifier: "apple.dm", actions: [reply], intentIdentifiers: []),
                UNNotificationCategory(identifier: "apple.support", actions: [resolve], intentIdentifiers: []),
                UNNotificationCategory(identifier: "apple.stack", actions: [again], intentIdentifiers: []),
                plain("apple.order"), plain("apple.drop"), plain("apple.comments"), plain("apple.reports"),
                plain("apple.pc"), plain("apple.curate"), plain("composer")]
    }

    private static func registerActions() {
        NotificationHub.textActions["apple.dm.reply"] = { text in
            let model = AppModel.shared
            await model.restoreIfNeeded()
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let email = d.string(forKey: "pldev.apple.dm.email"), !body.isEmpty else { return }
            let said: String
            if (try? await Console.post("api/dm/send", ["email": email, "body": body], model: model)) != nil { said = "Sent." } else { said = "Not sent. Open House and try again." }
            _ = await NotificationHub.shared.post(id: "apple.dm.sent", title: said, body: body, category: nil, link: nil)
        }
        NotificationHub.actions["apple.support.resolve"] = {
            let model = AppModel.shared
            await model.restoreIfNeeded()
            guard let id = d.string(forKey: "pldev.apple.support.id") else { return }
            let ok = (try? await Console.post("api/pldev/x/contact", ["id": id, "status": "resolved"], model: model)) != nil
            _ = await NotificationHub.shared.post(id: "apple.support.done", title: ok ? "Marked resolved" : "Not resolved", body: ok ? "The message is closed." : "The console did not answer. Open House and try again.", category: nil, link: nil)
        }
        NotificationHub.actions["apple.stack.run"] = {
            let model = AppModel.shared
            await model.restoreIfNeeded()
            let line = await Console.run("run/stack-health", model: model)
            _ = await NotificationHub.shared.post(id: "apple.stack.rerun", title: "Stack health ran again", body: line, category: nil, link: nil)
        }
    }

    // MARK: what each source looks like (only the fields read)

    private struct ContactRow: Decodable { let id: String?; let status: String?; let name: String? }
    private struct Threads: Decodable { struct T: Decodable { let email: String?; let handle: String?; let unread: Int? }; let threads: [T]? }
    private struct Cost: Decodable { let orderCountAllTime: Int?; let revenue30d: Double?; let orderCount30d: Int? }
    private struct ChosenRow: Decodable { let product: String? }
    private struct ReportRow: Decodable { let count: Int? }
    private struct Health: Decodable {
        struct R: Decodable { let pass: Bool? }
        struct Run: Decodable { let id: String?; let all_pass: Bool?; let results: [String: R]? }
        let data: Run?
    }
    private struct Drafts: Decodable { struct D: Decodable { let id: String; let platform: String?; let caption: String? }; let drafts: [D]? }
    private struct Comments: Decodable { let items: [Item]; struct Item: Decodable { let id: String } }
    private struct PC: Decodable {
        struct Reading: Decodable { let temp_c: String?; let free_ram_gb: String? }
        let thermal: [Reading]?; let disk_free_gb: Double?
    }

    // MARK: the pass

    /// Sends the widget's taps, reads every source, refreshes the widget's glance and returns the notices to raise.
    static func pass(model: AppModel) async -> [LocalNotice] {
        guard model.http != nil else { return [] }
        await drain(model: model)
        var out: [LocalNotice] = []
        var glance = SharedState.readApple() ?? AppleGlance()
        glance.queued = AppleActionQueue.all().count

        if model.config?.origins["console"] != nil {
            async let contactR = try? Console.q("contact", [ContactRow].self, model: model)
            async let threadsR = try? Console.get("api/dm/threads", Threads.self, model: model)
            async let costR = try? Console.q("cost", Cost.self, model: model)
            async let chosenR = try? Console.q("chosen", [ChosenRow].self, model: model)
            async let reportsR = try? Console.q("reports", [ReportRow].self, model: model)
            async let healthR = try? Console.get("run/stack-health/latest", Health.self, model: model)
            async let draftsR = try? Console.get("api/drafts/pending", Drafts.self, model: model, query: ["limit": "1"])
            async let commentsR = try? OS.get("comments", Comments.self, model: model)
            let (contact, threads, cost, chosen, reports, health, drafts, comments) =
                await (contactR, threadsR, costR, chosenR, reportsR, healthR, draftsR, commentsR)

            if let contact {
                let open = contact.filter { $0.status != "resolved" }
                if let n = rose("support", now: open.count), n > 0 {
                    if let newest = open.first?.id { d.set(newest, forKey: "pldev.apple.support.id") }
                    out.append(notice("apple.support", "Support mail", n == 1 ? "A message needs an answer." : "\(n) new messages need an answer.", room: "support"))
                }
            }
            if let threads {
                let unread = (threads.threads ?? []).reduce(0) { $0 + ($1.unread ?? 0) }
                if let n = rose("dm", now: unread), n > 0 {
                    let top = (threads.threads ?? []).first { ($0.unread ?? 0) > 0 }
                    if let e = top?.email { d.set(e, forKey: "pldev.apple.dm.email") }
                    let who = top?.handle ?? "a member"
                    out.append(notice("apple.dm", "Message from \(who)", n == 1 ? "One new message in your inbox." : "\(n) new messages in your inbox.", room: "inbox"))
                }
            }
            if let count = cost?.orderCountAllTime, let n = rose("orders", now: count), n > 0 {
                let money = cost?.revenue30d.map { String(format: " Last 30 days: $%.0f.", $0) } ?? ""
                out.append(notice("apple.order", n == 1 ? "A new order" : "\(n) new orders", "The shop took an order." + money, room: "tally", tab: "inbound"))
            }
            if let chosen, let n = rose("drops", now: chosen.count), n > 0 {
                let name = chosen.first?.product ?? "A piece"
                out.append(notice("apple.drop", "A drop was chosen", n == 1 ? "\(name) was chosen from the tally." : "\(n) drops were chosen from the tally.", room: "tally", tab: "inbound"))
            }
            if let reports, let n = rose("reports", now: reports.count), n > 0 {
                out.append(notice("apple.reports", "Reports to moderate", n == 1 ? "One report waits for you." : "\(n) new reports wait for you.", room: "reports"))
            }
            if let comments, let n = rose("comments", now: comments.items.count), n > 0 {
                out.append(notice("apple.comments", "Comments to post", n == 1 ? "One comment is drafted for you to post." : "\(n) new comments are drafted for you to post.", room: "comments"))
            }
            if let run = health?.data, run.all_pass == false, let id = run.id, d.string(forKey: "pldev.apple.stack.id") != id {
                d.set(id, forKey: "pldev.apple.stack.id")
                let failed = (run.results ?? [:]).filter { $0.value.pass == false }.keys.sorted()
                out.append(notice("apple.stack", "Stack health failed", failed.isEmpty ? "A check failed." : "Failing: " + failed.joined(separator: ", ") + ".", room: "health"))
            }
            if let top = drafts?.drafts?.first {
                glance.draftID = top.id
                glance.draftPlatform = top.platform
                glance.draftCaption = String((top.caption ?? "").prefix(140))
            } else if drafts != nil {
                glance.draftID = nil; glance.draftPlatform = nil; glance.draftCaption = nil
            }
            if let stats = try? await Console.q("draftstats", HouseModel.DraftStats.self, model: model) { glance.draftCount = stats.pending ?? 0 }
        }

        if let pc = await readPC(model: model) { out += pcNotices(pc) }

        if let g = SharedState.readLibrary(), let batch = g.batch, !batch.isEmpty {
            let key = "pldev.apple.curate.batch"
            let seen = d.string(forKey: key), newCount = g.batchNew
            if seen == nil { d.set(batch + "|\(newCount)", forKey: key) }
            else if seen != batch + "|\(newCount)" {
                d.set(batch + "|\(newCount)", forKey: key)
                if newCount > 0 { out.append(notice("apple.curate", "New in Curate", "\(newCount) new in \(batch).", room: nil, section: "curate")) }
            }
        }
        if let top = LibraryData.shared.items.first(where: { LibraryData.shared.marks[$0.vault_id] == nil }) {
            glance.curateID = top.vault_id
            glance.curateLabel = String((top.name ?? top.sub ?? top.vault_id).prefix(60))
        }
        if let habits = try? await Practice.get("habits", [PracticeHabit].self, model: model) {
            let open = habits.filter { !$0.tickedToday }
            glance.habitsLeft = open.count
            glance.habitID = open.first?.id
            glance.habitLabel = open.first.map { String($0.response.prefix(60)) }
        }
        glance.updatedAt = .now
        SharedState.writeApple(glance)
        return out
    }

    // MARK: helpers

    /// How many are new since the last pass; nil on the very first pass (it only learns the count).
    private static func rose(_ key: String, now: Int) -> Int? {
        let k = "pldev.apple.seen." + key
        let prev = d.object(forKey: k) as? Int
        d.set(now, forKey: k)
        guard let prev else { return nil }
        return max(0, now - prev)
    }

    private static func notice(_ type: String, _ title: String, _ body: String, room: String?, tab: String? = nil, section: String = "house") -> LocalNotice {
        LocalNotice(id: type, title: title, body: body, category: type,
                    link: .section(id: section, path: [room].compactMap { $0 }, query: [:]))
    }

    private static func readPC(model: AppModel) async -> PC? {
        guard let http = model.http, let key = model.config?.key("call"), !key.isEmpty, model.config?.origins["call"] != nil else { return nil }
        guard let data = try? await http.send(RequestPlan(origin: "call", path: "pcstats"), extraHeaders: ["X-Call-Key": key], timeout: 12, cache: false) else { return nil }
        return try? JSONDecoder().decode(PC.self, from: data)
    }

    /// Hot, low on disk, low on memory. Each says so once, then stays quiet for three hours (a laptop that is hot stays hot).
    private static func pcNotices(_ pc: PC) -> [LocalNotice] {
        var parts: [String] = []
        if let t = pc.thermal?.last, let c = Double(t.temp_c ?? ""), c >= 85 { parts.append(String(format: "running hot at %.0f degrees", c)) }
        if let t = pc.thermal?.last, let r = Double(t.free_ram_gb ?? ""), r > 0, r < 2 { parts.append(String(format: "only %.1f GB of memory free", r)) }
        if let free = pc.disk_free_gb, free < 25 { parts.append(String(format: "only %.0f GB of disk free", free)) }
        guard !parts.isEmpty else { return [] }
        let key = "pldev.apple.pc.at"
        if let last = d.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 3 * 3600 { return [] }
        d.set(Date(), forKey: key)
        return [LocalNotice(id: "apple.pc", title: "The PC needs a look", body: "It is " + parts.joined(separator: ", ") + ".", category: "apple.pc",
                            link: .section(id: "status", path: [], query: [:]))]
    }

    // MARK: the widget's taps

    /// Sends what the widget's buttons queued. What fails goes back on the queue for the next pass.
    static func drain(model: AppModel) async {
        let actions = AppleActionQueue.take()
        guard !actions.isEmpty else { return }
        for a in actions {
            var ok = false
            switch a.kind {
            case "draft.approve": ok = (try? await Console.post("api/drafts/moderate", ["draft_id": a.target, "action": "approve"], model: model)) != nil
            case "draft.hold": ok = (try? await Console.post("api/drafts/moderate", ["draft_id": a.target, "action": "hold"], model: model)) != nil
            case "curate.keep": ok = await LibraryData.shared.post(["id": a.target, "v": "keep"], model: model)
            case "curate.cut": ok = await LibraryData.shared.post(["id": a.target, "v": "cut"], model: model)
            case "practice.tick": ok = (try? await Practice.post("habits/\(a.target)/tick", model: model)) != nil
            default: ok = true   // an action this build does not know is dropped, never retried forever
            }
            if !ok, Date().timeIntervalSince(a.at) < 6 * 3600 { AppleActionQueue.add(kind: a.kind, target: a.target) }
        }
        var g = SharedState.readApple() ?? AppleGlance()
        g.queued = AppleActionQueue.all().count
        SharedState.writeApple(g)
    }
}
