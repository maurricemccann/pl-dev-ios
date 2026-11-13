import XCTest
@testable import PLDevCore

private let goodJSON = #"""
{"v":1,"sections":["status","paint"],
 "origins":{"cron":{"base":"https://example.com/api","certName":"example.com","fallbackIp":"203.0.113.7","auth":{"key":"widgetRead","header":"Authorization","scheme":"Bearer"}},
            "bare":{"base":"https://example.org/","auth":{"key":"debug","header":"X-Key"}}},
 "keys":{"widgetRead":"KEY-PLACEHOLDER","debug":"KEY-TWO"},
 "theme":{"palette":"night","handTitle":true},"capture":{"defaultTarget":"inbox"},
 "slash":[{"label":"Ship","send":"/ship"}],"words":["one"],"futureField":{"x":1}}
"""#

private func config() throws -> PLDevConfig { try PLDevConfig.load(Data(goodJSON.utf8)) }

final class ConfigTests: XCTestCase {
    func testLoadsAndNormalisesTrailingSlash() throws {
        let c = try config()
        XCTAssertEqual(c.origin("cron")?.base, "https://example.com/api/")
        XCTAssertEqual(c.origin("bare")?.base, "https://example.org/")
        XCTAssertEqual(c.sections, ["status", "paint"])
        XCTAssertEqual(c.theme?.palette, "night")
        XCTAssertEqual(c.theme?.handTitle, true)
        XCTAssertEqual(c.capture?.defaultTarget, "inbox")
        XCTAssertEqual(c.slash, [PLDevConfig.Slash(label: "Ship", send: "/ship")])
        XCTAssertEqual(c.key("widgetRead"), "KEY-PLACEHOLDER")
        XCTAssertNil(c.key("nope"))
        XCTAssertNil(c.origin("nope"))
    }

    func testUnknownFieldsIgnored() throws {
        let c = try PLDevConfig.load(Data(#"{"v":1,"sections":["a"],"whatever":[1,2],"origins":{}}"#.utf8))
        XCTAssertEqual(c.sections, ["a"])
        XCTAssertTrue(c.keys.isEmpty)
    }

    func testNotJSON() {
        XCTAssertThrowsError(try PLDevConfig.load(Data("not json".utf8))) { XCTAssertEqual($0 as? ConfigError, .notJSON) }
        XCTAssertThrowsError(try PLDevConfig.load(Data())) { XCTAssertEqual($0 as? ConfigError, .notJSON) }
        XCTAssertThrowsError(try PLDevConfig.load(Data(#"{"sections":["a"]}"#.utf8))) { XCTAssertEqual($0 as? ConfigError, .notJSON) }
    }

    func testWrongVersion() {
        XCTAssertThrowsError(try PLDevConfig.load(Data(#"{"v":2,"sections":["a"]}"#.utf8))) { XCTAssertEqual($0 as? ConfigError, .wrongVersion(2)) }
    }

    func testOriginNotHTTPS() {
        let j = #"{"v":1,"sections":["a"],"origins":{"cron":{"base":"http://example.com/"}}}"#
        XCTAssertThrowsError(try PLDevConfig.load(Data(j.utf8))) { XCTAssertEqual($0 as? ConfigError, .originNotHTTPS("cron")) }
    }

    func testEmptySections() {
        XCTAssertThrowsError(try PLDevConfig.load(Data(#"{"v":1,"sections":[]}"#.utf8))) { XCTAssertEqual($0 as? ConfigError, .emptySections) }
        XCTAssertThrowsError(try PLDevConfig.load(Data(#"{"v":1}"#.utf8))) { XCTAssertEqual($0 as? ConfigError, .emptySections) }
    }

    func testUnknownAuthKey() {
        let j = #"{"v":1,"sections":["a"],"keys":{},"origins":{"cron":{"base":"https://example.com/","auth":{"key":"ghost","header":"Authorization"}}}}"#
        XCTAssertThrowsError(try PLDevConfig.load(Data(j.utf8))) {
            XCTAssertEqual($0 as? ConfigError, .unknownAuthKey(origin: "cron", key: "ghost"))
        }
    }

    func testErrorsHavePlainSentences() {
        let all: [ConfigError] = [.notJSON, .wrongVersion(3), .originNotHTTPS("x"), .emptySections, .unknownAuthKey(origin: "o", key: "k")]
        for e in all { XCTAssertTrue(e.description.hasSuffix("."), "\(e)") }
    }

    func testBlankKeyReadsAsNotSet() throws {
        let c = PLDevConfig(sections: ["a"], keys: ["blank": "  ", "real": "KEY-PLACEHOLDER"])
        XCTAssertNil(c.key("blank"))
        XCTAssertNotNil(c.key("real"))
    }

    func testPublicCopyHasNoKeys() throws {
        let c = try config()
        let p = c.publicCopy
        XCTAssertTrue(p.keys.isEmpty)
        XCTAssertEqual(p.origins, c.origins)
        XCTAssertEqual(p.sections, c.sections)
        let text = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        XCTAssertFalse(text.contains("KEY-PLACEHOLDER"))
        XCTAssertFalse(text.contains("KEY-TWO"))
        XCTAssertEqual(try JSONDecoder().decode(PLDevConfig.self, from: Data(text.utf8)), p)
    }
}

final class ManifestTests: XCTestCase {
    func testReadinessCases() throws {
        let c = try config()
        func m(_ id: String, keys: [String] = [], origins: [String] = []) -> SectionManifest {
            SectionManifest(id: id, title: id, symbol: "circle", needsKeys: keys, needsOrigins: origins)
        }
        XCTAssertEqual(m("status").readiness(in: c), .ready)
        XCTAssertEqual(m("status", keys: ["widgetRead"], origins: ["cron"]).readiness(in: c), .ready)
        XCTAssertEqual(m("status", keys: ["widgetRead", "paintSync", "vault"]).readiness(in: c), .missingKeys(["paintSync", "vault"]))
        XCTAssertEqual(m("status", origins: ["cron", "board"]).readiness(in: c), .missingOrigins(["board"]))
        XCTAssertEqual(m("status", keys: ["paintSync"], origins: ["board"]).readiness(in: c), .missingOrigins(["board"]))
        XCTAssertEqual(m("unlisted").readiness(in: c), .notListed)
        XCTAssertEqual(m("unlisted", keys: ["x"]).readiness(in: c), .notListed)
        XCTAssertEqual(m("status").id, "status")
    }

    func testBlankKeyCountsAsMissing() {
        let c = PLDevConfig(sections: ["s"], keys: ["k": " "])
        let m = SectionManifest(id: "s", title: "S", symbol: "circle", needsKeys: ["k"])
        XCTAssertEqual(m.readiness(in: c), .missingKeys(["k"]))
    }
}

final class RequestPlanTests: XCTestCase {
    func testQueryEncodingAndPath() throws {
        let c = try config()
        let ok = RequestPlan(origin: "cron", path: "/health", query: ["b": "x y&z", "a": "1+2", "c": "é"])
        let r = try ok.urlRequests(config: c)[0]
        XCTAssertEqual(r.url.absoluteString, "https://example.com/api/health?a=1%2B2&b=x%20y%26z&c=%C3%A9")
        XCTAssertEqual(r.method, "GET")
        XCTAssertEqual(r.certName, "example.com")
    }

    func testNoQueryNoQuestionMark() throws {
        let r = try RequestPlan(origin: "bare", path: "ping").urlRequests(config: try config())[0]
        XCTAssertEqual(r.url.absoluteString, "https://example.org/ping")
    }

    func testAuthWithScheme() throws {
        let r = try RequestPlan(origin: "cron", path: "x", headers: ["Accept": "a/b"]).urlRequests(config: try config())[0]
        XCTAssertEqual(r.headers["Authorization"], "Bearer KEY-PLACEHOLDER")
        XCTAssertEqual(r.headers["Accept"], "a/b")
    }

    func testAuthWithoutSchemeIsBare() throws {
        let r = try RequestPlan(origin: "bare", path: "x").urlRequests(config: try config())[0]
        XCTAssertEqual(r.headers["X-Key"], "KEY-TWO")
        XCTAssertNil(r.certName)
    }

    func testAuthOverridesCallerHeader() throws {
        let r = try RequestPlan(origin: "cron", path: "x", headers: ["Authorization": "mine"]).urlRequests(config: try config())[0]
        XCTAssertEqual(r.headers["Authorization"], "Bearer KEY-PLACEHOLDER")
    }

    func testFallbackIpGivesSecondRequestKeepingCertName() throws {
        let plan = RequestPlan(origin: "cron", method: "POST", path: "send", query: ["k": "v"], body: Data("hi".utf8))
        let rs = try plan.urlRequests(config: try config())
        XCTAssertEqual(rs.count, 2)
        XCTAssertEqual(rs[0].url.host, "example.com")
        XCTAssertEqual(rs[1].url.absoluteString, "https://203.0.113.7/api/send?k=v")
        XCTAssertEqual(rs[1].certName, "example.com")
        XCTAssertEqual(rs[1].method, "POST")
        XCTAssertEqual(rs[1].body, Data("hi".utf8))
        XCTAssertEqual(rs[1].headers, rs[0].headers)
    }

    func testFallbackWithoutCertNameUsesPrimaryHost() throws {
        let c = PLDevConfig(sections: ["a"], origins: ["o": .init(base: "https://example.com/", fallbackIp: "203.0.113.9")])
        let rs = try RequestPlan(origin: "o", path: "p").urlRequests(config: c)
        XCTAssertEqual(rs.count, 2)
        XCTAssertEqual(rs[1].certName, "example.com")
    }

    func testErrorsHavePlainSentences() {
        let all: [ConfigError] = [.notJSON, .wrongVersion(3), .originNotHTTPS("x"), .emptySections, .unknownAuthKey(origin: "o", key: "k")]
        for e in all { XCTAssertTrue(e.description.hasSuffix("."), "\(e)") }
    }

    func testBlankKeyReadsAsNotSet() throws {
        let c = PLDevConfig(sections: ["a"], keys: ["blank": "  ", "real": "KEY-PLACEHOLDER"])
        XCTAssertNil(c.key("blank"))
        XCTAssertNotNil(c.key("real"))
    }

    func testPublicCopyHasNoKeys() throws {
        let c = try config()
        let p = c.publicCopy
        XCTAssertTrue(p.keys.isEmpty)
        XCTAssertEqual(p.origins, c.origins)
        XCTAssertEqual(p.sections, c.sections)
        let text = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        XCTAssertFalse(text.contains("KEY-PLACEHOLDER"))
        XCTAssertFalse(text.contains("KEY-TWO"))
        XCTAssertEqual(try JSONDecoder().decode(PLDevConfig.self, from: Data(text.utf8)), p)
    }
}

final class ManifestTests: XCTestCase {
    func testReadinessCases() throws {
        let c = try config()
        func m(_ id: String, keys: [String] = [], origins: [String] = []) -> SectionManifest {
            SectionManifest(id: id, title: id, symbol: "circle", needsKeys: keys, needsOrigins: origins)
        }
        XCTAssertEqual(m("status").readiness(in: c), .ready)
        XCTAssertEqual(m("status", keys: ["widgetRead"], origins: ["cron"]).readiness(in: c), .ready)
        XCTAssertEqual(m("status", keys: ["widgetRead", "paintSync", "vault"]).readiness(in: c), .missingKeys(["paintSync", "vault"]))
        XCTAssertEqual(m("status", origins: ["cron", "board"]).readiness(in: c), .missingOrigins(["board"]))
        XCTAssertEqual(m("status", keys: ["paintSync"], origins: ["board"]).readiness(in: c), .missingOrigins(["board"]))
        XCTAssertEqual(m("unlisted").readiness(in: c), .notListed)
        XCTAssertEqual(m("unlisted", keys: ["x"]).readiness(in: c), .notListed)
        XCTAssertEqual(m("status").id, "status")
    }

    func testBlankKeyCountsAsMissing() {
        let c = PLDevConfig(sections: ["s"], keys: ["k": " "])
        let m = SectionManifest(id: "s", title: "S", symbol: "circle", needsKeys: ["k"])
        XCTAssertEqual(m.readiness(in: c), .missingKeys(["k"]))
    }
}

final class RequestPlanTests: XCTestCase {
    func testQueryEncodingAndPath() throws {
        let c = try config()
        let ok = RequestPlan(origin: "cron", path: "/health", query: ["b": "x y&z", "a": "1+2", "c": "é"])
        let r = try ok.urlRequests(config: c)[0]
        XCTAssertEqual(r.url.absoluteString, "https://example.com/api/health?a=1%2B2&b=x%20y%26z&c=%C3%A9")
        XCTAssertEqual(r.method, "GET")
        XCTAssertEqual(r.certName, "example.com")
    }

    func testNoQueryNoQuestionMark() throws {
        let r = try RequestPlan(origin: "bare", path: "ping").urlRequests(config: try config())[0]
        XCTAssertEqual(r.url.absoluteString, "https://example.org/ping")
    }

    func testAuthWithScheme() throws {
        let r = try RequestPlan(origin: "cron", path: "x", headers: ["Accept": "a/b"]).urlRequests(config: try config())[0]
        XCTAssertEqual(r.headers["Authorization"], "Bearer KEY-PLACEHOLDER")
        XCTAssertEqual(r.headers["Accept"], "a/b")
    }

    func testAuthWithoutSchemeIsBare() throws {
        let r = try RequestPlan(origin: "bare", path: "x").urlRequests(config: try config())[0]
        XCTAssertEqual(r.headers["X-Key"], "KEY-TWO")
        XCTAssertNil(r.certName)
    }

    func testAuthOverridesCallerHeader() throws {
        let r = try RequestPlan(origin: "cron", path: "x", headers: ["Authorization": "mine"]).urlRequests(config: try config())[0]
        XCTAssertEqual(r.headers["Authorization"], "Bearer KEY-PLACEHOLDER")
    }

    func testFallbackIpGivesSecondRequestKeepingCertName() throws {
        let plan = RequestPlan(origin: "cron", method: "POST", path: "send", query: ["k": "v"], body: Data("hi".utf8))
        let rs = try plan.urlRequests(config: try config())
        XCTAssertEqual(rs.count, 2)
        XCTAssertEqual(rs[0].url.host, "example.com")
        XCTAssertEqual(rs[1].url.absoluteString, "https://203.0.113.7/api/send?k=v")
        XCTAssertEqual(rs[1].certName, "example.com")
        XCTAssertEqual(rs[1].method, "POST")
        XCTAssertEqual(rs[1].body, Data("hi".utf8))
        XCTAssertEqual(rs[1].headers, rs[0].headers)
    }

    func testFallbackWithoutCertNameUsesPrimaryHost() throws {
        let c = PLDevConfig(sections: ["a"], origins: ["o": .init(base: "https://example.com/", fallbackIp: "203.0.113.9")])
        let rs = try RequestPlan(origin: "o", path: "p").urlRequests(config: c)
        XCTAssertEqual(rs.count, 2)
        XCTAssertEqual(rs[1].certName, "example.com")
    }

    func testErrors() throws {
        let c = try config()
        XCTAssertThrowsError(try RequestPlan(origin: "ghost").urlRequests(config: c)) { XCTAssertEqual($0 as? RequestPlanError, .unknownOrigin("ghost")) }
        // key name exists in `keys` at load time but the value was blanked afterwards
        var blank = c
        blank.keys["widgetRead"] = ""
        XCTAssertThrowsError(try RequestPlan(origin: "cron").urlRequests(config: blank)) { XCTAssertEqual($0 as? RequestPlanError, .missingKey("widgetRead")) }
    }
}

final class RetryPolicyTests: XCTestCase {
    func testDelayTable() {
        XCTAssertEqual(RetryPolicy.delay(attempt: 0), 1)
        XCTAssertEqual(RetryPolicy.delay(attempt: 1), 1)
        XCTAssertEqual(RetryPolicy.delay(attempt: 2), 2)
        XCTAssertEqual(RetryPolicy.delay(attempt: 3), 4)
        XCTAssertEqual(RetryPolicy.delay(attempt: 4), 8)
        XCTAssertEqual(RetryPolicy.delay(attempt: 5), 15)
        XCTAssertEqual(RetryPolicy.delay(attempt: 50), 15)
    }

    func testRetriesServerErrorsAndNetworkFailuresWhenIdempotent() {
        XCTAssertTrue(RetryPolicy.shouldRetry(status: nil, attempt: 1, idempotent: true))
        XCTAssertTrue(RetryPolicy.shouldRetry(status: 500, attempt: 2, idempotent: true))
        XCTAssertTrue(RetryPolicy.shouldRetry(status: 503, attempt: 4, idempotent: true))
        XCTAssertTrue(RetryPolicy.shouldRetry(status: 408, attempt: 1, idempotent: true))
        XCTAssertTrue(RetryPolicy.shouldRetry(status: 429, attempt: 1, idempotent: true))
    }

    func testNeverRetriesOtherClientErrorsOrSuccess() {
        for s in [400, 401, 403, 404, 410, 200, 204, 301] {
            XCTAssertFalse(RetryPolicy.shouldRetry(status: s, attempt: 1, idempotent: true), "\(s)")
        }
    }

    func testNeverAutoRetriesNonIdempotent() {
        for s in [nil, 408, 429, 500, 503] as [Int?] {
            XCTAssertFalse(RetryPolicy.shouldRetry(status: s, attempt: 1, idempotent: false), "\(String(describing: s))")
        }
    }

    func testStopsAfterMaxRetries() {
        XCTAssertFalse(RetryPolicy.shouldRetry(status: 500, attempt: 5, idempotent: true))
        XCTAssertFalse(RetryPolicy.shouldRetry(status: 500, attempt: 0, idempotent: true))
    }
}

final class OfflineQueueTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func item(_ id: String, at: Double = 0) -> QueuedItem {
        QueuedItem(id: id, createdAt: t0.addingTimeInterval(at), kind: "text", origin: "cron", path: "api/x", text: "hello")
    }

    func testAddAndMarkSent() {
        var q = OfflineQueue()
        q.add(item("a")); q.add(item("b"))
        XCTAssertEqual(q.items.map(\.id), ["a", "b"])
        q.markSent("a")
        XCTAssertEqual(q.items.map(\.id), ["b"])
        q.markSent("missing")
        XCTAssertEqual(q.items.count, 1)
    }

    func testAddSameIdReplaces() {
        var q = OfflineQueue()
        q.add(item("a"))
        var again = item("a"); again.text = "new"
        XCTAssertNil(q.add(again))
        XCTAssertEqual(q.items.count, 1)
        XCTAssertEqual(q.items[0].text, "new")
    }

    func testCapDropsOldestAndReportsIt() {
        XCTAssertEqual(OfflineQueue.cap, 200)
        var q = OfflineQueue()
        for i in 0..<200 { XCTAssertNil(q.add(item("\(i)", at: Double(i)))) }
        XCTAssertEqual(q.items.count, 200)
        let dropped = q.add(item("200", at: 200))
        XCTAssertEqual(dropped?.id, "0")
        XCTAssertEqual(q.items.count, 200)
        XCTAssertEqual(q.items.first?.id, "1")
        XCTAssertEqual(q.items.last?.id, "200")
    }

    func testBackoffInDue() {
        var q = OfflineQueue()
        q.add(item("a"))
        XCTAssertEqual(q.due(now: t0).map(\.id), ["a"])
        q.markFailed("a", now: t0)
        XCTAssertEqual(q.items[0].attempts, 1)
        XCTAssertTrue(q.due(now: t0.addingTimeInterval(4.9)).isEmpty)
        XCTAssertEqual(q.due(now: t0.addingTimeInterval(5)).map(\.id), ["a"])
        q.markFailed("a", now: t0.addingTimeInterval(5))
        XCTAssertEqual(q.items[0].attempts, 2)
        XCTAssertTrue(q.due(now: t0.addingTimeInterval(14.9)).isEmpty)
        XCTAssertFalse(q.due(now: t0.addingTimeInterval(15)).isEmpty)
    }

    func testBackoffTable() {
        XCTAssertEqual(OfflineQueue.backoff(attempts: 0), 0)
        XCTAssertEqual(OfflineQueue.backoff(attempts: 1), 5)
        XCTAssertEqual(OfflineQueue.backoff(attempts: 2), 10)
        XCTAssertEqual(OfflineQueue.backoff(attempts: 3), 20)
        XCTAssertEqual(OfflineQueue.backoff(attempts: 20), 900)
        XCTAssertEqual(OfflineQueue.backoff(attempts: 1000), 900)
    }

    func testDueIsOldestFirstAndSkipsWaiting() {
        var q = OfflineQueue()
        q.add(item("late", at: 10)); q.add(item("early", at: 1)); q.add(item("wait", at: 5))
        q.markFailed("wait", now: t0.addingTimeInterval(20))
        XCTAssertEqual(q.due(now: t0.addingTimeInterval(21)).map(\.id), ["early", "late"])
    }

    func testMarkFailedUnknownIdIsNoOp() {
        var q = OfflineQueue(items: [item("a")])
        q.markFailed("zzz")
        XCTAssertEqual(q.items[0].attempts, 0)
    }

    func testCodableRoundTrip() throws {
        var q = OfflineQueue()
        q.add(item("a")); q.markFailed("a", now: t0)
        let back = try JSONDecoder().decode(OfflineQueue.self, from: try JSONEncoder().encode(q))
        XCTAssertEqual(back, q)
    }
}

final class ScrubTests: XCTestCase {
    func testBearerToken() {
        XCTAssertEqual(Scrub.clean("Authorization: Bearer abc.def-123_x"), "Authorization: Bearer [redacted]")
        XCTAssertEqual(Scrub.clean("sent bearer KEY-PLACEHOLDER ok"), "sent Bearer [redacted] ok")
    }

    func testLongHex() {
        let hex = String(repeating: "ab12", count: 8)   // 32 chars
        XCTAssertEqual(Scrub.clean("id \(hex) done"), "id [redacted] done")
        XCTAssertEqual(Scrub.clean("id \(hex)ff done"), "id [redacted] done")
        XCTAssertEqual(Scrub.clean("short \(String(repeating: "ab12", count: 7))"), "short \(String(repeating: "ab12", count: 7))")   // 28 chars stays
    }

    func testKeyValueParams() {
        XCTAssertEqual(Scrub.clean("GET /x?k=abc123&auth=zzz&token=qq"), "GET /x?k=[redacted]&auth=[redacted]&token=[redacted]")
        XCTAssertEqual(Scrub.clean("api_key=SECRET1 and apikey=SECRET2"), "api_key=[redacted] and apikey=[redacted]")
        XCTAssertEqual(Scrub.clean("KEY=Upper"), "KEY=[redacted]")
    }

    func testOrdinaryTextUntouched() {
        let lines = [
            "Loaded 3 sections from cron in 120 ms",
            "task=done status=ok build 1a2b3c",
            "key count 4, token missing",
            "https://example.com/api/health?x=1",
            "",
        ]
        for l in lines { XCTAssertEqual(Scrub.clean(l), l) }
    }

    func testIdempotent() {
        let once = Scrub.clean("Bearer KEY-PLACEHOLDER k=abc")
        XCTAssertEqual(Scrub.clean(once), once)
    }
}

final class DebugBufferTests: XCTestCase {
    private func ev(_ i: Int) -> DebugEvent { DebugEvent(at: Date(timeIntervalSince1970: Double(i)), category: "t", message: "m\(i)") }

    func testCapDropsOldest() {
        XCTAssertEqual(DebugBuffer.cap, 200)
        var b = DebugBuffer()
        for i in 0..<250 { b.add(ev(i)) }
        XCTAssertEqual(b.events.count, 200)
        XCTAssertEqual(b.events.first?.message, "m50")
        XCTAssertEqual(b.events.last?.message, "m249")
    }

    func testDrainTakesOldestAndRemoves() {
        var b = DebugBuffer()
        for i in 0..<5 { b.add(ev(i)) }
        XCTAssertEqual(b.drain(max: 2).map(\.message), ["m0", "m1"])
        XCTAssertEqual(b.events.count, 3)
        XCTAssertEqual(b.drain(max: 100).map(\.message), ["m2", "m3", "m4"])
        XCTAssertTrue(b.drain(max: 5).isEmpty)
        XCTAssertTrue(b.drain(max: -1).isEmpty)
    }

    func testCodable() throws {
        var b = DebugBuffer()
        b.add(ev(1))
        let back = try JSONDecoder().decode(DebugBuffer.self, from: try JSONEncoder().encode(b))
        XCTAssertEqual(back.events, b.events)
    }
}

final class DeepLinkTests: XCTestCase {
    private func link(_ s: String) -> DeepLink? { URL(string: s).flatMap(DeepLink.init(url:)) }

    func testParsesForms() {
        XCTAssertEqual(link("pldev://home"), .home)
        XCTAssertEqual(link("pldev://settings"), .settings)
        XCTAssertEqual(link("pldev://section/paint"), .section(id: "paint", path: [], query: [:]))
        XCTAssertEqual(link("pldev://section/paint/a/b?k=v&x=1"), .section(id: "paint", path: ["a", "b"], query: ["k": "v", "x": "1"]))
        XCTAssertEqual(link("PLDEV://Home"), .home)
    }

    func testRoundTrips() {
        let all: [DeepLink] = [
            .home, .settings,
            .section(id: "capture", path: [], query: [:]),
            .section(id: "paint", path: ["a b", "c/d", "é"], query: ["k": "v w", "z": "&=", "empty": ""]),
        ]
        for l in all { XCTAssertEqual(DeepLink(url: l.url), l, "\(l.url)") }
    }

    func testUrlShape() {
        XCTAssertEqual(DeepLink.home.url.absoluteString, "pldev://home")
        XCTAssertEqual(DeepLink.settings.url.absoluteString, "pldev://settings")
        XCTAssertEqual(DeepLink.section(id: "p", path: ["x"], query: ["b": "2", "a": "1"]).url.absoluteString, "pldev://section/p/x?a=1&b=2")
    }

    func testRejectsOtherSchemesAndShapes() {
        XCTAssertNil(link("https://example.com/section/paint"))
        XCTAssertNil(link("pldevx://home"))
        XCTAssertNil(link("pldev://nowhere"))
        XCTAssertNil(link("pldev://section"))
        XCTAssertNil(link("pldev://section/"))
    }
}

final class SSEParserTests: XCTestCase {
    func testBlankLineEndsAnEventAndCommentsAreIgnored() {
        var p = SSEParser()
        XCTAssertNil(p.feed(": keep-alive"))
        XCTAssertNil(p.feed("data: {\"a\":1}"))
        XCTAssertEqual(p.feed(""), SSEParser.Message(event: nil, data: "{\"a\":1}", id: nil))
        XCTAssertNil(p.feed(""))
    }

    func testMultiLineDataAndCRLF() {
        var p = SSEParser()
        _ = p.feed("event: x\r")
        _ = p.feed("data: one\r")
        _ = p.feed("data:two\r")
        XCTAssertEqual(p.feed("\r"), SSEParser.Message(event: "x", data: "one\ntwo", id: nil))
    }

    func testLineSplitterKeepsPartialLine() {
        var buf = ""
        XCTAssertEqual(SSEParser.lines(appending: "data: a\nda", to: &buf), ["data: a"])
        XCTAssertEqual(buf, "da")
        XCTAssertEqual(SSEParser.lines(appending: "ta: b\n\n", to: &buf), ["data: b", ""])
    }
}

final class JSONValueTests: XCTestCase {
    func testRoundTrip() throws {
        let json = #"{"a":[1,"x",true,null],"b":{"c":2.5}}"#
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        XCTAssertEqual(v, .object(["a": .array([.number(1), .string("x"), .bool(true), .null]), "b": .object(["c": .number(2.5)])]))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(v)), v)
    }
}
