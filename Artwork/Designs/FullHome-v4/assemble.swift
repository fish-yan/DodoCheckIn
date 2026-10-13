// Assemble ImageGen-produced UI sections into the requested single scrolling design.
// Usage: swift Artwork/Designs/FullHome-v4/assemble.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = root.appendingPathComponent("Artwork/Designs/FullHome-v4")
let files = ["01-home-energy.png", "02-knowledge-life.png", "03-courage-tab.png"]
let sideTrims = [0.0574, 0.0506, 0.0]
let width = 1170
let gap = 72
// Increase only the empty row gutters; preserve generated cards and their artwork.
let rowGutters: [[(y: Int, addedHeight: Int)]] = [
    [(1172, 26), (1442, 26)],
    [(492, 23), (1246, 23), (1534, 23)],
    [(762, 24)]
]
let sections = files.indices.map { index -> CGImage in
    let name = files[index]
    let trim = sideTrims[index]
    let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let inset = Int(Double(image.width) * trim)
    let cropped = image.cropping(to: CGRect(x: inset, y: 0, width: image.width - 2 * inset, height: image.height))!
    let sectionHeight = cropped.height + rowGutters[index].reduce(0) { $0 + $1.addedHeight }
    let section = CGContext(data: nil, width: cropped.width, height: sectionHeight, bitsPerComponent: 8,
                           bytesPerRow: cropped.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    var sourceY = 0
    var targetY = 0
    for gutter in rowGutters[index] + [(cropped.height, 0)] {
        let count = gutter.y - sourceY
        let slice = cropped.cropping(to: CGRect(x: 0, y: sourceY, width: cropped.width, height: count))!
        section.draw(slice, in: CGRect(x: 0, y: sectionHeight - targetY - count, width: cropped.width, height: count))
        targetY += count
        if gutter.addedHeight > 0 {
            let seam = cropped.cropping(to: CGRect(x: 0, y: gutter.y, width: cropped.width, height: 1))!
            section.draw(seam, in: CGRect(x: 0, y: sectionHeight - targetY - gutter.addedHeight,
                                         width: cropped.width, height: gutter.addedHeight))
            targetY += gutter.addedHeight
        }
        sourceY = gutter.y
    }
    return section.makeImage()!
}
let heights = sections.map { Int((Double($0.height) * Double(width) / Double($0.width)).rounded()) }
let height = heights.reduce(0, +) + gap * (sections.count - 1)
let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
canvas.setFillColor(CGColor(red: 243.0 / 255, green: 244.0 / 255, blue: 250.0 / 255, alpha: 1))
canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
canvas.interpolationQuality = .high
var offset = 0
for (index, section) in sections.enumerated() {
    canvas.draw(section, in: CGRect(x: 0, y: height - offset - heights[index], width: width, height: heights[index]))
    offset += heights[index] + gap
}
let output = root.appendingPathComponent("Artwork/Designs/多多打卡-完整首页开发设计稿-v4.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, canvas.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
print("Saved \(width) × \(height): \(output.path)")
