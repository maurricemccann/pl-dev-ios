import CoreImage
import Foundation
import ImageIO
import UIKit
import Vision

/// What the phone adds to a photo of art before it leaves (his rules 11-14): the year it was made, read from the photo itself; his
/// signature written into the image's own metadata; and a straightened copy of a camera capture. All on this iPhone, no network.
enum CaptureMeta {
    /// The day the photo was taken (EXIF DateTimeOriginal) as yyyy-MM-dd, or nil when the picture does not say.
    nonisolated static func madeDate(of data: Data) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String, stamp.count >= 10 else { return nil }
        let day = stamp.prefix(10).replacingOccurrences(of: ":", with: "-")
        return day.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil ? day : nil
    }

    /// The same JPEG with his signature in its metadata: artist, copyright with the year, the day it was made and the title
    /// (TIFF, EXIF and IPTC fields, the ones archives and photo apps read). Returns the input unchanged if the image cannot be rewritten.
    nonisolated static func signed(_ jpeg: Data, artist: String, made: String, title: String) -> Data {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil), let type = CGImageSourceGetType(src) else { return jpeg }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return jpeg }
        let year = String(made.prefix(4))
        let notice = "\u{00A9} \(year) \(artist)"
        let tiff: [CFString: Any] = [kCGImagePropertyTIFFArtist: artist, kCGImagePropertyTIFFCopyright: notice, kCGImagePropertyTIFFImageDescription: title]
        let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: made.replacingOccurrences(of: "-", with: ":") + " 00:00:00"]
        let iptc: [CFString: Any] = [kCGImagePropertyIPTCByline: artist, kCGImagePropertyIPTCCopyrightNotice: notice, kCGImagePropertyIPTCObjectName: title]
        let props: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: tiff,
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyIPTCDictionary: iptc,
            kCGImageDestinationLossyCompressionQuality: 0.92,
        ]
        CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : jpeg
    }

    /// Apple's on-device aesthetics score for a photo (Vision, iOS 18): a plain warning when the picture looks soft or dark, or looks
    /// like a screenshot or document, else nil. A hint only; nothing is blocked.
    static func qualityNote(_ data: Data) async -> String? {
        guard let upright = CaptureModel.jpeg(data), let cg = UIImage(data: upright)?.cgImage,
              let seen = try? await CalculateImageAestheticsScoresRequest().perform(on: cg) else { return nil }
        if seen.isUtility { return "This looks like a screenshot or a document, not a photo of a piece." }
        if seen.overallScore < -0.3 { return "This photo looks soft or dark. Retake it in better light?" }
        return nil
    }

    /// A camera capture with the artwork's four corners found and pulled square (crop and straighten). Nil when no clear rectangle fills
    /// enough of the picture; the original is never changed, this is a second copy he can choose.
    nonisolated static func straightened(_ data: Data) -> Data? {
        guard let upright = CaptureModel.jpeg(data), let image = CIImage(data: upright) else { return nil }
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.8
        request.minimumSize = 0.3
        request.minimumAspectRatio = 0.3
        request.quadratureTolerance = 20
        request.maximumObservations = 1
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let quad = request.results?.first else { return nil }
        let w = image.extent.width, h = image.extent.height
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: quad.topLeft.x * w, y: quad.topLeft.y * h), forKey: "inputTopLeft")
        filter.setValue(CIVector(x: quad.topRight.x * w, y: quad.topRight.y * h), forKey: "inputTopRight")
        filter.setValue(CIVector(x: quad.bottomLeft.x * w, y: quad.bottomLeft.y * h), forKey: "inputBottomLeft")
        filter.setValue(CIVector(x: quad.bottomRight.x * w, y: quad.bottomRight.y * h), forKey: "inputBottomRight")
        guard let flat = filter.outputImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CIContext().jpegRepresentation(of: flat, colorSpace: space, options: [:])
    }
}
