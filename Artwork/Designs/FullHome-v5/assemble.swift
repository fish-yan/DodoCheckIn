// Assemble ImageGen edits on a deterministic grid. Run from the project root.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = root.appendingPathComponent("Artwork/Designs/FullHome-v5")
func load(_ name: String) -> CGImage {
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(directory.appendingPathComponent(name + ".png") as CFURL, nil)!, 0, nil)!
}
func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
struct Tile {
    let name: String
    let source: CGRect
    var button: CGRect? = nil
}
struct Section {
    let name: String
    let trim: Int
    let firstY: Int
    let gutterY: Int
    let bottomY: Int
    let tiles: [Tile]
}
let sections: [Section] = [
    Section(name: "energy", trim: 0, firstY: 173, gutterY: 631, bottomY: 1563, tiles: [
        Tile(name: "wake", source: rect(55,173,414,441)),
        Tile(name: "breakfast", source: rect(485,173,414,441)),
        Tile(name: "lunch", source: rect(55,649,414,432), button: rect(79,984,368,77)),
        Tile(name: "dinner", source: rect(485,649,414,432), button: rect(509,984,368,77)),
        Tile(name: "sleeping", source: rect(55,1115,414,441), button: rect(79,1459,368,77))
    ]),
    Section(name: "knowledge", trim: 0, firstY: 237, gutterY: 799, bottomY: 1378, tiles: [
        Tile(name: "listening", source: rect(64,237,463,546)),
        Tile(name: "homework", source: rect(546,237,462,546), button: rect(573,660,409,98)),
        Tile(name: "reading", source: rect(64,813,463,557), button: rect(94,1242,404,100))
    ]),
    Section(name: "life", trim: 0, firstY: 197, gutterY: 629, bottomY: 1563, tiles: [
        Tile(name: "toys", source: rect(55,197,416,416)),
        Tile(name: "cleaning", source: rect(485,197,415,416), button: rect(509,507,366,86)),
        Tile(name: "washing", source: rect(55,646,416,440), button: rect(80,980,365,85)),
        Tile(name: "hygiene", source: rect(485,646,415,440), button: rect(509,980,366,85)),
        Tile(name: "dressing", source: rect(55,1120,416,435))
    ]),
    Section(name: "courage", trim: 85, firstY: 242, gutterY: 769, bottomY: 1291, tiles: [
        Tile(name: "kindness", source: rect(142,242,421,515), button: rect(162,648,382,89)),
        Tile(name: "calmness", source: rect(583,242,422,515), button: rect(603,648,382,89)),
        Tile(name: "promptness", source: rect(142,785,421,498), button: rect(162,1172,382,90)),
        Tile(name: "honesty", source: rect(583,785,422,498), button: rect(603,1172,382,90))
    ])
]
let width = 1170
let cardWidth = 507
let cardHeight = 570
let rowGap = 54
let sectionGap = 60
let top = load("00-top")
let footer = load("05-footer")
let images = sections.map { load($0.name + "-edited") }
let headers = zip(sections, images).map { section, image in
    Int((Double(section.firstY) * Double(width) / Double(image.width - section.trim * 2)).rounded())
}
let bodies = sections.map { (($0.tiles.count + 1) / 2) * cardHeight + (($0.tiles.count + 1) / 2 - 1) * rowGap }
let bottoms = zip(sections, images).map { section, image in
    Int((Double(image.height - section.bottomY) * Double(width) / Double(image.width - section.trim * 2)).rounded())
}
let height = top.height + footer.height + headers.reduce(0,+) + bodies.reduce(0,+) + bottoms.reduce(0,+) + sectionGap * 3
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .high
context.setFillColor(CGColor(red: 243.0/255, green: 244.0/255, blue: 250.0/255, alpha: 1))
context.fill(rect(0,0,width,height))
func target(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: CGFloat(height) - r.maxY, width: r.width, height: r.height) }
func draw(_ image: CGImage, crop: CGRect? = nil, at destination: CGRect, radius: CGFloat? = nil) {
    let piece = crop.map { image.cropping(to: $0)! } ?? image
    context.saveGState()
    if let radius {
        context.addPath(CGPath(roundedRect: target(destination), cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
    }
    context.draw(piece, in: target(destination))
    context.restoreGState()
}
var y = top.height
var layout: [[String: Any]] = []
draw(top, at: rect(0,0,width,top.height))
for i in sections.indices {
    let section = sections[i]
    let image = images[i]
    let sourceWidth = image.width - section.trim * 2
    draw(image, crop: rect(section.trim,0,sourceWidth,section.firstY), at: rect(0,y,width,headers[i]))
    y += headers[i]
    // Use a card-free generated gutter as the original section surface and side borders.
    draw(image, crop: rect(section.trim,section.gutterY,sourceWidth,1), at: rect(0,y,width,bodies[i]))
    for (index,tile) in section.tiles.enumerated() {
        let x = index % 2 == 0 ? 60 : 603
        let tileY = y + (index / 2) * (cardHeight + rowGap)
        let destination = rect(x,tileY,cardWidth,cardHeight)
        context.saveGState()
        context.addPath(CGPath(roundedRect: target(destination), cornerWidth: 30, cornerHeight: 30, transform: nil))
        context.clip()
        if let button = tile.button {
            // Preserve the generated card surface, and place every actual button on one exact grid.
            let blank = CGRect(x: tile.source.minX + 35, y: tile.source.maxY - 12, width: tile.source.width - 70, height: 3)
            draw(image, crop: blank, at: destination)
            let topHeight = Int(button.minY - tile.source.minY) - 10
            let bodyCrop = CGRect(x: tile.source.minX, y: tile.source.minY, width: tile.source.width, height: CGFloat(topHeight))
            draw(image, crop: bodyCrop, at: rect(x,tileY,cardWidth,414))
            draw(image, crop: button, at: rect(x+36,tileY+426,435,120), radius: 30)
        } else {
            draw(image, crop: tile.source, at: destination)
        }
        context.restoreGState()
        layout.append(["task":tile.name,"card":[x,tileY,cardWidth,cardHeight],"button":tile.button == nil ? [] : [x+36,tileY+426,435,120]])
    }
    y += bodies[i]
    draw(image, crop: rect(section.trim,section.bottomY,sourceWidth,image.height-section.bottomY), at: rect(0,y,width,bottoms[i]))
    y += bottoms[i] + (i == sections.count-1 ? 0 : sectionGap)
}
draw(footer, at: rect(0,y,width,footer.height))
let output = root.appendingPathComponent("Artwork/Designs/多多打卡-统一卡片与按钮设计稿-v5.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(destination,context.makeImage()!,nil)
precondition(CGImageDestinationFinalize(destination))
let metadata:[String:Any] = ["width":width,"height":height,"cardWidth":cardWidth,"cardHeight":cardHeight,"buttonWidth":435,"buttonHeight":120,"buttonCornerRadius":30,"rowGap":rowGap,"tasks":layout]
try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted,.sortedKeys]).write(to: directory.appendingPathComponent("layout.json"))
print("Saved \(width) × \(height): \(output.path)")
