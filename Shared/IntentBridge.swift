import Foundation

/// The hook the intents call. The app sets it when its process starts; in an extension process it stays nil.
@MainActor enum IntentBridge {
    static var open: ((DeepLink) -> Void)?

    /// An intent can start the app process cold, so wait up to two seconds for the app to set its hook, then run the body.
    static func whenReady(_ body: @escaping @MainActor () -> Void) async throws {
        for _ in 0..<20 where open == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard open != nil else { throw IntentBridgeError.notReady }
        body()
    }
}

/// Thrown when the app never set the hook, so the system shows that the action did not run.
enum IntentBridgeError: Error {
    case notReady
}
