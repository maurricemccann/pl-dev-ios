import Foundation

/// Reads the config file once, keeps its raw JSON in the Keychain and nowhere else, and hands it back at launch.
/// An actor so the file read and the Keychain calls never run on the main thread.
actor ConfigStore {
    private static let account = "config"

    /// `url` comes from the Files picker, AirDrop or "Open in", so it may be security-scoped.
    func load(from url: URL) throws -> PLDevConfig {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let config = try PLDevConfig.load(data)
        try KeyStore.save(data, account: Self.account)
        Self.removeIfOurCopy(url)
        return config
    }

    func saved() -> PLDevConfig? {
        guard let data = KeyStore.load(account: Self.account) else { return nil }
        return try? PLDevConfig.load(data)
    }

    func forget() {
        KeyStore.delete(account: Self.account)
    }

    /// A file opened into the app can land as a copy inside our own Documents folder, which Files can browse.
    /// The keys now live in the Keychain, so that copy is removed. A file picked in place elsewhere is left alone.
    private static func removeIfOurCopy(_ url: URL) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let ours = documents.standardizedFileURL.path
        if url.standardizedFileURL.path.hasPrefix(ours + "/") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
