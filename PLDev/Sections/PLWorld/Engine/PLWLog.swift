import RealityKit
import CoreGraphics
import Foundation

/// PL World's error log (his ask 11-18: "a debug mode so I can just have it read all errors and I can send it to you").
/// Every load that used to fail silently (`try?`) goes through here and leaves one line in the app's debug log
/// (Settings > Log, sent to his own server log when Debug is on), naming what failed and why.
@MainActor enum PLWLog {
    static func note(_ s: String) { AppModel.shared.debug.note("plworld", s) }
    static func fail(_ what: String, _ error: Error) { note("FAILED \(what): \(String(describing: error))") }

    static func mesh(from d: [MeshDescriptor], _ what: String = "mesh") -> MeshResource? {
        do { return try MeshResource.generate(from: d) } catch { fail(what, error); return nil }
    }
    static func texture(image: CGImage, options: TextureResource.CreateOptions, _ what: String = "texture") async -> TextureResource? {
        do { return try await TextureResource(image: image, options: options) } catch { fail(what, error); return nil }
    }
    static func texture(contentsOf url: URL, options: TextureResource.CreateOptions) async -> TextureResource? {
        do { return try await TextureResource(contentsOf: url, options: options) } catch { fail("texture \(url.lastPathComponent)", error); return nil }
    }
    static func staticMesh(from m: MeshResource) async -> ShapeResource? {
        do { return try await ShapeResource.generateStaticMesh(from: m) } catch { fail("collision shape", error); return nil }
    }
    static func entity(contentsOf url: URL) async -> Entity? {
        do { return try await Entity(contentsOf: url) } catch { fail("model \(url.lastPathComponent)", error); return nil }
    }
}
