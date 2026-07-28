#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: generate-qa-app-icon.swift SOURCE_1024_PNG OUTPUT_APPICONSET\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to read source icon at \(sourceURL.path)\n", stderr)
    exit(1)
}
var sourceRect = NSRect(origin: .zero, size: sourceImage.size)
guard let sourceCGImage = sourceImage.cgImage(
    forProposedRect: &sourceRect,
    context: nil,
    hints: nil
) else {
    fputs("Unable to decode source icon at \(sourceURL.path)\n", stderr)
    exit(1)
}

let outputs: [(name: String, pixels: Int)] = [
    ("Icon-20.png", 20),
    ("Icon-20@2x.png", 40),
    ("Icon-20@3x.png", 60),
    ("Icon-29.png", 29),
    ("Icon-29@2x.png", 58),
    ("Icon-29@3x.png", 87),
    ("Icon-40.png", 40),
    ("Icon-40@2x.png", 80),
    ("Icon-40@3x.png", 120),
    ("Icon-60@2x.png", 120),
    ("Icon-60@3x.png", 180),
    ("Icon-76.png", 76),
    ("Icon-76@2x.png", 152),
    ("Icon-83.5@2x.png", 167),
    ("Icon-1024.png", 1024),
]

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

for output in outputs {
    let size = CGFloat(output.pixels)
    guard let bitmapContext = CGContext(
        data: nil,
        width: output.pixels,
        height: output.pixels,
        bitsPerComponent: 8,
        bytesPerRow: output.pixels * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fputs("Unable to allocate \(output.name)\n", stderr)
        exit(1)
    }

    bitmapContext.interpolationQuality = .high
    bitmapContext.draw(
        sourceCGImage,
        in: CGRect(x: 0, y: 0, width: size, height: size)
    )

    let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let badge = NSRect(
        x: size * 0.58,
        y: size * 0.07,
        width: size * 0.34,
        height: size * 0.18
    )
    let badgePath = NSBezierPath(
        roundedRect: badge,
        xRadius: size * 0.055,
        yRadius: size * 0.055
    )
    NSColor(
        calibratedRed: 1.0,
        green: 0.35,
        blue: 0.20,
        alpha: 1.0
    ).setFill()
    badgePath.fill()

    NSColor(calibratedWhite: 1.0, alpha: 0.32).setStroke()
    badgePath.lineWidth = max(1, size * 0.008)
    badgePath.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size * 0.115, weight: .heavy),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ]
    let label = NSAttributedString(string: "QA", attributes: attributes)
    let labelSize = label.size()
    label.draw(
        at: NSPoint(
            x: badge.midX - labelSize.width / 2,
            y: badge.midY - labelSize.height / 2
        )
    )

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let renderedImage = bitmapContext.makeImage() else {
        fputs("Unable to render \(output.name)\n", stderr)
        exit(1)
    }
    let bitmap = NSBitmapImageRep(cgImage: renderedImage)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Unable to encode \(output.name)\n", stderr)
        exit(1)
    }
    try png.write(to: outputDirectory.appendingPathComponent(output.name))
}

print("Generated \(outputs.count) QA app icon assets in \(outputDirectory.path)")
