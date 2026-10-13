import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let files = ["01-top-energy.png", "02-knowledge-life.png", "03-courage-tab.png"]
let images = files.map { name -> CGImage in
    let url = root.appendingPathComponent("Artwork/Designs/v4-slices/" + name)
    return CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
}
for width in [414, 828] {
    let heights = images.map { Int((Double($0.height) * Double(width) / Double($0.width)).rounded()) }
    let total = heights.reduce(0, +)
    let canvas = CGContext(data: nil, width: width, height: total, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    canvas.interpolationQuality = .high
    var offset = 0
    for (index, image) in images.enumerated() {
        let h = heights[index]
        canvas.draw(image, in: CGRect(x: 0, y: total - offset - h, width: width, height: h))
        offset += h
    }
    let name = width == 414 ? "多多打卡-首页完整设计稿-414-v4.png" : "多多打卡-首页完整设计稿-414@2x-v4.png"
    let out = root.appendingPathComponent("Artwork/Designs/" + name)
    let writer = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, canvas.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(writer))
    print("\(out.path): \(width) × \(total)")
}
