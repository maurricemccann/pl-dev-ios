import Foundation
import SafariServices

/// Receives the one native message the toolbar action sends ({url, title, selection}) and writes it into
/// the shared inbox. It never opens the network, and the script gets nothing back but ok or failed.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let reply = NSExtensionItem()
        reply.userInfo = [SFExtensionMessageKey: SafariWebExtensionHandler.store(message)]
        context.completeRequest(returningItems: [reply], completionHandler: nil)
    }

    /// A web page chose these strings, so each one is checked and cut to a sane length before it is stored.
    static func store(_ message: [String: Any]?) -> [String: Any] {
        guard let message, let address = message["url"] as? String, address.count <= 4000,
              let url = URL(string: address), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return ["ok": false, "error": "This page has no web address to save."]
        }
        let title = (message["title"] as? String).map { String($0.prefix(500)) }
        let selection = (message["selection"] as? String).map { String($0.prefix(20000)) }
        let item = SharedInbox.Item(
            id: UUID().uuidString,
            createdAt: Date(),
            source: "safari",
            kind: "url",
            text: selection?.isEmpty == false ? selection : nil,
            url: address,
            title: title?.isEmpty == false ? title : nil,
            fileName: nil,
            note: nil
        )
        do {
            try SharedInbox.add(item, file: nil)
            return ["ok": true]
        } catch {
            return ["ok": false, "error": error.localizedDescription]
        }
    }
}
