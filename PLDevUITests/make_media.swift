// Writes the simulator's test media: three pictures and one two-second clip, generated here, never anyone's own photos.
// Usage: swift make_media.swift <output dir>
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func frame(_ w: Int, _ h: Int, hue: CGFloat, step: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.setFillColor(CGColor(red: 0.05, green: 0.04, blue: 0.03, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for i in 0..<12 {
        let t = CGFloat(i) / 11
        ctx.setFillColor(CGColor(red: min(1, hue + t * 0.5), green: 0.55 - t * 0.3, blue: 0.9 - hue * 0.5 + t * 0.1, alpha: 1))
        let r = CGFloat(min(w, h)) * (0.46 - t * 0.036 * 11 / 1.0 * 0.9)
        let cx = CGFloat(w) / 2 + CGFloat(step) * 6, cy = CGFloat(h) / 2
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }
    return ctx.makeImage()!
}

func writeJPEG(_ name: String, _ img: CGImage) {
    let url = out.appendingPathComponent(name) as CFURL
    let d = CGImageDestinationCreateWithURL(url, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    CGImageDestinationFinalize(d)
}

writeJPEG("pl-test-photo-1.jpg", frame(1200, 900, hue: 0.1, step: 0))
writeJPEG("pl-test-photo-2.jpg", frame(900, 1200, hue: 0.45, step: 0))
writeJPEG("pl-test-photo-3.jpg", frame(1200, 1200, hue: 0.8, step: 0))

// the clip: 2 s, 30 fps, 640x360
let movie = out.appendingPathComponent("pl-test-clip.mov")
try? FileManager.default.removeItem(at: movie)
let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 360])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
for n in 0..<60 {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA, nil, &pb)
    CVPixelBufferLockBaseAddress(pb!, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(frame(640, 360, hue: CGFloat(n) / 80, step: n - 30), in: CGRect(x: 0, y: 0, width: 640, height: 360))
    CVPixelBufferUnlockBaseAddress(pb!, [])
    adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(n), timescale: 30))
}
input.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
print("wrote", try FileManager.default.contentsOfDirectory(atPath: out.path).sorted())
