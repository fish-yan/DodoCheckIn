import Foundation
import ImageIO
import CoreGraphics

// Run from the project root: swift tools/verify_artwork.swift
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Artwork/manifest.json"))) as! [String: Any]
let assets = manifest["assets"] as! [[String: Any]]
for asset in assets {
    let name = asset["name"] as! String
    let path = asset["assetPath"] as! String
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    let alphas = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    let transparent = alphas.filter { $0 == 0 }.count
    if name == "AppIcon" || asset["opaqueBackground"] as? Bool == true {
        if name == "AppIcon" { precondition(image.width == 1024 && image.height == 1024) }
        precondition(alphas.allSatisfy { $0 == 255 }, "Icon must be opaque")
    } else {
        precondition(Double(transparent) / Double(alphas.count) > 0.15, "Missing real transparency: \(name)")
        precondition(alphas[0] == 0 && alphas[image.width - 1] == 0 && alphas[alphas.count - 1] == 0)
    }
    print("\(name): \(image.width) × \(image.height), transparent pixels \(transparent)")
}
print("Validated \(assets.count) artwork assets.")
