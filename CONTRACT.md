# Build contract (read before writing any file)

*How it looks and behaves: `DESIGN.md`, the one UI/UX contract every app follows (his ruling 11-13).*

PL DEV: one native iPhone app that holds many native sections, with a widget extension, a share extension and a Safari web extension. This build is the FOUNDATION only: the shell, the config, the key store, the network client, Settings, notifications, the debug log, the probes, one placeholder section ("Status") and one stub of each extension. No section features yet.

Three writers work in this repo at once. Each owns folders; nobody edits another's folder. Shared names below are law.

The reference app is `C:\dev\pl-call-ios` (same owner, same pipeline, proven on the device). Copy its patterns; where this contract names a file to lift from it, read that file first. That repo is read-only for you.

## This repo is PUBLIC. Rule 1, above every other rule
Nothing private is ever written into any file, commit message or log: no key, token, hostname, IP address, URL of a private service, email, person's name, city, account, session link. Every address and key arrives at run time from a config file the owner loads once. Placeholders in examples and tests use `example.com` and obviously fake values such as `"KEY-PLACEHOLDER"`. `scripts/scan.sh` enforces this and fails the build.

## Layout and owners
- `PLDevCore/` (CORE writer): a Swift package, pure Foundation, tested on Linux with `swift test`. Sources in `PLDevCore/Sources/PLDevCore/`, tests in `PLDevCore/Tests/PLDevCoreTests/`. **App and extension code compile these source files directly (same module): never write `import PLDevCore` outside the package tests.**
- `PLDev/Services/` (APP writer): everything in the app without SwiftUI views: `AppModel`, `KeyStore`, `ConfigStore`, `HTTPClient` wiring, `NotificationHub`, `Poller`, `DebugLog`, `ProbeModel`, `SectionRegistry`.
- `PLDev/UI/` (APP writer): every SwiftUI view, the theme, fonts, haptics. Also `PLDev/PLDevApp.swift`, `PLDev/Sections/Status/` and `PLDev/Resources/`.
- `Shared/` (PLATFORM writer): types compiled into the app AND every extension: `SharedInbox`, `SharedState`, `IntentBridge`, the App Intents.
- `PLDevWidgets/`, `PLDevShare/`, `PLDevSafari/` (PLATFORM writer): the three extension targets.
- `PLDev.xcodeproj/`, every `Info.plist`, `.github/workflows/`, `scripts/` (PLATFORM writer).

The Xcode project uses **file-system-synchronized groups** (objectVersion 77, `PBXFileSystemSynchronizedRootGroup`), exactly as `pl-call-ios/PLCall.xcodeproj` does, so any `.swift` file placed in an owned folder is compiled automatically; only PLATFORM touches the project file. Folder to target: `PLDev/` → app · `PLDevCore/Sources/PLDevCore/` → app and all three extensions · `Shared/` → app and all three extensions · `PLDevWidgets/`, `PLDevShare/`, `PLDevSafari/` → their own extension.

Bundle ids: app `com.psychedluxuries.dev`, extensions `.widgets`, `.share`, `.safari`. App Group `group.com.psychedluxuries.dev`. URL scheme `pldev`.

## PLDevCore (CORE implements exactly these names)
```swift
public struct PLDevConfig: Codable, Sendable, Equatable {
    public var v: Int                          // must be 1
    public var sections: [String]              // order of the home grid, section ids
    public var origins: [String: Origin]       // "cron", "gallery", "board", "call", ...
    public var keys: [String: String]          // "widgetRead", "widgetWrite", "paintSync", "debug", "vault", "call", ...
    public var theme: Theme?
    public var capture: Capture?
    public var slash: [Slash]?
    public var words: [String]?
    public struct Origin: Codable, Sendable, Equatable { public var base: String; public var certName: String?; public var fallbackIp: String?; public var auth: Auth?
        public struct Auth: Codable, Sendable, Equatable { public var key: String; public var header: String; public var scheme: String? } }   // key = a name in `keys`; scheme "Bearer" or nil for a bare header value
    public struct Theme: Codable, Sendable, Equatable { public var fontFamily: String?; public var palette: String?; public var handTitle: Bool? }
    public struct Capture: Codable, Sendable, Equatable { public var defaultTarget: String? }
    public struct Slash: Codable, Sendable, Equatable { public var label: String; public var send: String }
    public static func load(_ data: Data) throws -> PLDevConfig      // validates; throws ConfigError with a plain sentence
    public func key(_ name: String) -> String?
    public func origin(_ name: String) -> Origin?
    public var publicCopy: PLDevConfig { get }                        // same config with `keys` emptied: the only form ever written to the App Group
}
public enum ConfigError: Error, Equatable, CustomStringConvertible   // .notJSON, .wrongVersion(Int), .originNotHTTPS(String), .emptySections, .unknownAuthKey(origin: String, key: String)
```
Validation: `v == 1`; every `origins[*].base` starts with `https://` and gets a trailing `/`; `sections` non-empty; an origin's `auth.key` must exist in `keys`. Unknown JSON fields are ignored (forward compatible).

```swift
public struct SectionManifest: Sendable, Equatable, Identifiable {   // what a section declares; pure data, no UI
    public var id: String; public var title: String; public var symbol: String        // SF Symbol name
    public var needsKeys: [String]; public var needsOrigins: [String]
    public func readiness(in config: PLDevConfig) -> Readiness        // .ready, .missingKeys([String]), .missingOrigins([String]), .notListed
}
public enum Readiness: Sendable, Equatable

public struct RequestPlan: Sendable, Equatable {                      // a request described without URLSession, so it tests on Linux
    public var origin: String; public var method: String; public var path: String; public var query: [String: String]; public var headers: [String: String]; public var body: Data?
    public func urlRequests(config: PLDevConfig) throws -> [PlannedRequest]   // primary base first, then the fallbackIp base if any; auth header applied from the origin's auth
}
public struct PlannedRequest: Sendable, Equatable { public var url: URL; public var method: String; public var headers: [String: String]; public var body: Data?; public var certName: String? }
public enum RetryPolicy { public static func delay(attempt: Int) -> Double; public static func shouldRetry(status: Int?, attempt: Int, idempotent: Bool) -> Bool }   // 1, 2, 4, 8 s capped at 15; never retry 4xx except 408 and 429; never auto-retry a non-idempotent write

public struct QueuedItem: Codable, Sendable, Equatable, Identifiable { public var id: String; public var createdAt: Date; public var kind: String; public var origin: String; public var path: String; public var text: String?; public var fileName: String?; public var note: String?; public var attempts: Int }
public struct OfflineQueue: Codable, Sendable, Equatable {           // pure value type; the app persists it
    public var items: [QueuedItem]
    public mutating func add(_ item: QueuedItem); public mutating func markSent(_ id: String); public mutating func markFailed(_ id: String)
    public func due(now: Date) -> [QueuedItem]                         // backoff per item by attempts
    public static let cap: Int                                          // 200; adding beyond it drops the oldest and reports it
}
public struct DebugEvent: Codable, Sendable, Equatable { public var at: Date; public var category: String; public var message: String }
public enum Scrub { public static func clean(_ text: String) -> String }   // removes Bearer tokens, 32+ hex runs, key=/token=/k=/auth= values: the same rules as the web kit's scrub()
public struct DebugBuffer: Codable, Sendable { public mutating func add(_ e: DebugEvent); public mutating func drain(max: Int) -> [DebugEvent]; public static let cap: Int }   // cap 200
public enum DeepLink: Sendable, Equatable { case section(id: String, path: [String], query: [String: String]); case settings; case home
    public init?(url: URL); public var url: URL { get } }             // pldev://section/<id>/<path...>?k=v, pldev://settings, pldev://home
```
Also lift unchanged from `pl-call-ios/PLCallCore/Sources/PLCallCore/`: `JSONValue.swift`, `SSEParser.swift` (and their tests).

CORE writes real tests for every type above (config validation cases, readiness, request planning with and without fallback, retry table, queue cap and backoff, scrub cases, deep link round trips) and runs `swift test` if a Swift toolchain is on this machine; if not, says so plainly and checks the code by reading it twice.

## The model the UI binds to (APP implements, in `PLDev/Services/AppModel.swift`)
```swift
@MainActor @Observable final class AppModel {
    static let shared: AppModel
    var config: PLDevConfig?                 // nil = show the config gate
    var configError: String?
    var sections: [SectionEntry]             // registered sections in the config's order, each with its readiness
    var route: DeepLink?                     // set by onOpenURL, intents and notifications
    var inboxCount: Int                      // items waiting in the shared inbox / offline queue
    var lastError: String?
    func loadConfig(from url: URL) async
    func forgetConfig()
    func open(_ link: DeepLink)
    func drainInbox() async                  // sends what the extensions dropped into the App Group, through the offline queue
    var probes: ProbeModel { get }
    var debug: DebugLog { get }
}
struct SectionEntry: Identifiable { let manifest: SectionManifest; let readiness: Readiness; let makeRoot: @MainActor () -> AnyView; var badge: Int? ; var id: String { manifest.id } }
@MainActor protocol PLSection {              // the section contract: every future section conforms
    static var manifest: SectionManifest { get }
    static func makeRoot(model: AppModel) -> AnyView
    static func probes(model: AppModel) -> [ProbeModel.Item]            // may be empty
    static func settingsRows(model: AppModel) -> AnyView?               // may be nil
    static func notificationCategories() -> Set<UNNotificationCategory> // may be empty
    static func handle(link: DeepLink, model: AppModel) -> Bool
    static func refresh(model: AppModel) async -> SectionRefresh         // called by the poller and background refresh
}
struct SectionRefresh { var badge: Int?; var notify: [LocalNotice] }
struct LocalNotice { var id: String; var title: String; var body: String; var category: String?; var link: DeepLink? }
@MainActor enum SectionRegistry { static var all: [any PLSection.Type] { get } }   // the one list a new section is added to
@MainActor @Observable final class ProbeModel {
    struct Item: Identifiable { let id: String; var title: String; var detail: String; var result: Result; var run: @MainActor () async -> Result
        enum Result { case untested, running, pass(String), fail(String) } }
    var items: [Item]
    func run(_ id: String) async; func runAll() async
}
```
Shell probes APP must provide (ids): `config`, `keychain`, `appGroup`, `sharedKeychain`, `notification`, `backgroundRefresh`, `widgetFetch`, `shareInbox`, `safariInbox`, and one `origin.<name>` per configured origin (a GET of the origin base's health path if the Status section knows one, else a HEAD of the base; reports reachable + status code, never the address).

Services APP provides: `KeyStore` (Keychain generic password, service = bundle id, `AfterFirstUnlockThisDeviceOnly`; lift `pl-call-ios/PLCall/Engine/Keychain.swift`; plus a `sharedProbe()` that tries a write/read with a keychain access group and reports the result, used only by the `sharedKeychain` probe), `ConfigStore` (lift the import → validate → Keychain flow from `ConfigStore.swift`; the raw config JSON lives ONLY in the Keychain; `publicCopy` goes to the App Group), `HTTPClient` (an actor over an ephemeral URLSession: executes a `RequestPlan`, tries each planned URL on DNS/connect errors, validates the server name with a `certName` policy as `LineClient.PinnedTrust` does (call it name matching, not pinning), applies `RetryPolicy`, maps errors to one plain sentence as `LineClient.plainSentence` does, and offers `stream(_:)` for SSE using `SSEParser`), `NotificationHub` (a category registry fed by `PLSection.notificationCategories()`, local notifications only, routes taps to `AppModel.open`), `Poller` (foreground timer + `BGAppRefreshTask` with identifier `com.psychedluxuries.dev.refresh`, calls every ready section's `refresh`, raises `LocalNotice`s through the hub, respects quiet hours and per-type switches), `DebugLog` (in-memory `DebugBuffer`, last 40 lines on screen, when Debug is on flushes scrubbed events to the `cron` origin `api/debug` with the `debug` key as Bearer, body `{app:"pl-dev", device:<random id kept in UserDefaults>, events:[...]}`, never throws into callers).

Settings store: `@AppStorage` keys prefixed `pldev.`: `theme` (system|light|dark), `font` (system|jost, DEFAULT system: owner ruling, the text face is Apple's system font; titles use the hand font from the theme pack when one is loaded, else the system font), `glassBlur`, `glassClear`, `tileStrength`, `textSize` (90...130 step 5), `motion` (full|reduce), `notify` (Bool, default false), `notify.<type>` (default true), `quietFrom`, `quietTo` ("HH:mm"), `debug` (Bool, default false).

## UI (APP writer)
- `RootView`: no config → `ConfigGateView` ("Load your config", one button, file importer for `.json`, also accepts a file opened into the app; **no network request of any kind before a config is loaded**). With a config: Face ID gate (lift from `pl-call-ios/PLCall/UI/RootView.swift`), then `HomeView`.
- `HomeView`: a grid of section tiles in the config's order (symbol, title, badge, a quiet "needs a key" state for a section that is not ready), a Settings button, an inbox chip when `inboxCount > 0`. Tapping a tile pushes the section's root with a zoom transition. Deep links route here.
- `SettingsView`: Appearance (theme, font, glass blur, see-through, tile strength, text size, motion), Notifications (master, per type, quiet hours), Keys (one row per key name the registered sections need: "Set" / "Not set", never the value), Sections (each section's own rows), Debug (switch, the last 40 log lines, Clear), Probes (link), Forget config (confirmation), About (version and build from the bundle).
- `ProbeView`: lift the pattern from `pl-call-ios/PLCall/UI/ProbeView.swift`.
- `Sections/Status/StatusSection.swift`: the placeholder section conforming to `PLSection`; shows each configured origin as reachable or not and each key as Set / Not set, with pull to refresh. Needs no key.
- `Theme.swift`: lift `pl-call-ios/PLCall/UI/Theme.swift` (`PLText` Dynamic Type mapping, `PLFonts.register()`, `glassControl`, `PLHaptic`, `PLMotion`) and add `Tokens.swift` beside it holding the spacing scale (2, 4, 8, 10, 12, 16, 20, 36), radii (card 28, sheet 32, row 14, list 26), touch 44 and the neutral colour roles. **Brand colours, the hand font and the pattern tile are NOT in this repo**: the app ships with Apple's system look and the bundled Jost text face (copy the four Jost TTFs and `OFL.txt` from `pl-call-ios/PLCall/Resources/Fonts/`; do NOT copy `PLHand.ttf` or the backdrop asset), and `ThemePack` (APP writes it) loads an optional theme pack from the app's Documents folder at run time: `theme.json` (named colours as hex, palette), a title font file and a tile image. With no pack the app is complete and good-looking on system colours.
- The bar every screen meets: Apple's materials on the floating control layer only (never glass on glass), Dynamic Type everywhere, SF Symbols, spring motion that respects Reduce Motion and the `motion` setting, a haptic on every committed action, every tap answered within 100 ms by a visual or haptic state, no spinner where cached content or a skeleton can show, designed empty / loading / error / offline states, every screen has an exit reachable with one thumb, 44 pt touch targets, VoiceOver labels on every control.

## Shared (PLATFORM implements; compiled into the app and all three extensions)
```swift
enum SharedState {                                  // App Group UserDefaults; lift the group lookup (with the renamed-group fallback) from pl-call-ios/Shared/SharedState.swift
    static var groupID: String? { get }; static var isAvailable: Bool { get }
    static func writeSnapshot(_ s: WidgetSnapshot); static func readSnapshot() -> WidgetSnapshot?
    static func writePublicConfig(_ c: PLDevConfig); static func readPublicConfig() -> PLDevConfig?   // the keyless copy only
}
struct WidgetSnapshot: Codable, Equatable { var updatedAt: Date; var inboxCount: Int; var badges: [String: Int]; var statusLine: String }
enum SharedInbox {                                  // files in the App Group container; extensions write, the app drains
    struct Item: Codable, Identifiable, Equatable { var id: String; var createdAt: Date; var source: String /* "share" | "safari" | "widget" */; var kind: String /* "text" | "url" | "image" */; var text: String?; var url: String?; var title: String?; var fileName: String?; var note: String? }
    static func add(_ item: Item, file: Data?) throws; static func all() -> [Item]; static func data(for item: Item) -> Data?; static func remove(_ id: String); static var isAvailable: Bool { get }
}
@MainActor enum IntentBridge { static var open: ((DeepLink) -> Void)?; static func whenReady(_ body: @escaping @MainActor () -> Void) async throws }   // lift whenReady from pl-call-ios/Shared/IntentBridge.swift
// App Intents: OpenSectionIntent(section: String), OpenCaptureIntent (opens pldev://section/capture; the section does not exist yet, so it lands on Home with the inbox chip), InboxCountIntent (returns the count as dialog). AppShortcutsProvider with phrases for "Open <app name>" and "What is in my <app name> inbox".
```
**Extensions never hold a key and never call the network.** They write into `SharedInbox`; the app sends. (A free-account Keychain cannot be shared for certain; the `sharedKeychain` probe reports what the device allows.)

Extension stubs:
- `PLDevWidgets`: a small/accessory widget showing `WidgetSnapshot` (inbox count, status line, "updated <time>"), and one Control Center control that opens `pldev://home`. Uses `SharedState`. No Live Activity yet.
- `PLDevShare`: accepts URLs, plain text and one image; a SwiftUI sheet in a `UIHostingController` with the item preview, a note field, Save and Cancel; writes one `SharedInbox.Item`; says "Saved. PL DEV sends it next time it opens." Never opens the network.
- `PLDevSafari`: a Safari web extension (manifest v3) with one toolbar action "Send to PL DEV" that sends the page URL, title and the current selection to `SFSafariWebExtensionHandler` by native messaging, which writes one `SharedInbox.Item`. The page script receives nothing back but ok / failed. Minimal permissions (`activeTab`, `nativeMessaging`, `scripting`).

PLATFORM also writes: `PLDev.xcodeproj` (four targets, the three extensions embedded in the app; start from `pl-call-ios/PLCall.xcodeproj/project.pbxproj` and its checker `scripts/check_pbxproj.py`, extended for the new targets), the Info.plists (app: `UIBackgroundModes` = `fetch`, `BGTaskSchedulerPermittedIdentifiers`, `CFBundleURLTypes` for `pldev`, FaceID usage string, `UIAppFonts` for Jost, `CFBundleDocumentTypes` so a `.json` can be opened into the app, `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` so the theme pack can be dropped into Documents through Files; no microphone, camera, voip or audio modes), entitlements files with only the App Group, `.github/workflows/build.yml` (manual dispatch, unsigned build, ad-hoc sign with entitlements, verify all three `.appex` are inside the app, zip to `PLDev.ipa`, `make_source.py`, release `build-N`, version `0.1.<run_number>`) and `logic.yml` (every push: `swift test --package-path PLDevCore`, then `scripts/scan.sh`), `scripts/scan.sh` (lift, keep every rule, change the ignored config name to `pldev-config*.json`), `scripts/make_source.py`, `scripts/check_pbxproj.py`, a placeholder app icon (a plain generated mark, no brand asset), and `README.md` (what the app is in neutral words, how the config file works with a fake example, no private detail).

## Rules for every writer
1. **Check Apple's own page before and after each API you use** (`https://developer.apple.com/documentation/<path>.md` returns the raw doc with availability; if it will not load, say so and mark the API unverified). The reference app's code compiled against the same SDK: prefer an API it already uses. A wrong name is a failed build that nobody can run locally (there is no Mac here; the build runs on a CI Mac).
2. Swift 6 language mode, deployment target iOS 26.0, built with Xcode 27.2. Guard anything iOS 27-only with `if #available(iOS 27, *)`.
3. Rule 1 at the top: nothing private in any file.
4. No third-party libraries.
5. Comments say why, one line, at the end of the line or above it; never before code on the same line. ASCII only in scripts.
6. Do not run `git commit`, `git push`, `gh`, or any network write. Do not create anything outside `C:\dev\pl-dev-ios`.
7. When you finish, list every file you wrote, every API you could not verify at Apple's pages, and anything in this contract you had to bend, with the reason.
