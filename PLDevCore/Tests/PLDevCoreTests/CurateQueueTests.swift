import XCTest
@testable import PLDevCore

/// The Curate deck rules, each one taken from CurateDeck.tsx and checked here (sub-spec 4).
final class CurateQueueTests: XCTestCase {
    private func it(_ id: String, _ cls: String = "still", name: String? = nil, origin: String? = nil, tags: String? = nil, src: String? = nil) -> LibraryItem {
        LibraryItem(vault_id: id, item_id: id, class: cls, name: name ?? id, origin: origin, tags: tags, src: src)
    }

    func testFnvMatchesTheWebHash() {
        XCTAssertEqual(CurateQueue.fnv("abc"), 440920331)
        XCTAssertEqual(CurateQueue.fnv("V-CRV-cloth"), 2960234608)
    }

    func testDefaultDeckIsUnmarkedWithoutArchiveOrUnrenderable() {
        let items = [it("a"), it("b"), it("arch", "archive-work"), it("broken", tags: #"["unrenderable"]"#)]
        let ids = CurateQueue.build(.everything, items: items, marks: ["b": TasteMark(v: "keep")]).map(\.vault_id)
        XCTAssertEqual(ids, ["a"])
    }

    func testDefaultDeckRanksHoodieWeekThenCloudThenOnModelThenRest() {
        let items = [
            it("rest1"),
            it("om", origin: "onmodel"),
            it("c-old", name: "x-20261101g0100.png"),
            it("c-new", name: "x-20261110g0100.png"),
            it("wk02", name: "hood-wk02v1"),
            it("wk03v1", name: "hood-wk03v1"),
            it("wk03v2", name: "hood-wk03v2"),
            it("rest2"),
        ]
        let ids = CurateQueue.build(.everything, items: items, marks: [:]).map(\.vault_id)
        // only the newest week outranks; wk02 falls back to the rest in index order
        XCTAssertEqual(ids, ["wk03v2", "wk03v1", "c-new", "c-old", "om", "rest1", "wk02", "rest2"])
    }

    func testBatchClipsNeverShowOneDrawingTwiceInARowWhileAnotherIsLeft() {
        var items: [LibraryItem] = []
        for n in 0..<6 { items.append(it("A\(n)", "cinematic", name: "20261101ba-\(n).mp4", tags: #"["PL-0001"]"#)) }
        for n in 0..<3 { items.append(it("B\(n)", "cinematic", name: "20261101bb-\(n).mp4", tags: #"["PL-0002"]"#)) }
        let out = CurateQueue.build(.everything, items: items, marks: [:])
        let pieces = out.map { $0.tagList.first! }
        XCTAssertEqual(out.count, 9)
        // with 6 of A and 3 of B, A must lead and B must split the A run as long as B lasts
        for i in 1..<pieces.count where pieces[i] == pieces[i - 1] {
            XCTAssertFalse(pieces[i...].contains { $0 != pieces[i] }, "a repeat while another drawing was still left at \(i)")
        }
    }

    func testNewIsUnmarkedOnlyNewestStampFirst() {
        let items = [it("old", name: "p-20261101a-1"), it("newer", name: "p-20261110a-1"), it("marked", name: "p-20261111a-1"), it("arch", "archive-work")]
        let ids = CurateQueue.build(.new, items: items, marks: ["marked": TasteMark(v: "cut")]).map(\.vault_id)
        XCTAssertEqual(ids, ["newer", "old"])
    }

    func testTrashIsCutsNewestFirst() {
        let marks = ["a": TasteMark(v: "cut", at: "2026-11-01"), "b": TasteMark(v: "cut", at: "2026-11-05"), "c": TasteMark(v: "keep")]
        XCTAssertEqual(CurateQueue.build(.trash, items: [it("a"), it("b"), it("c")], marks: marks).map(\.vault_id), ["b", "a"])
    }

    func testFavsDeckIsPlainKeepsNewestFirstNoArchive() {
        let marks = ["a": TasteMark(v: "keep"), "b": TasteMark(v: "keep", note: "fav"), "c": TasteMark(v: "keep"), "d": TasteMark(v: "keep")]
        let ids = CurateQueue.build(.favs, items: [it("a"), it("b"), it("c"), it("d", "archive-work")], marks: marks).map(\.vault_id)
        XCTAssertEqual(ids, ["c", "a"])
    }

    func testMaybesKeepArchiveWorks() {
        let marks = ["a": TasteMark(v: "maybe"), "arch": TasteMark(v: "maybe")]
        XCTAssertEqual(CurateQueue.build(.maybes, items: [it("a"), it("arch", "archive-work")], marks: marks).map(\.vault_id), ["a", "arch"])
    }
}
