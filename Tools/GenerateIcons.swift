#!/usr/bin/env swift
//
//  GenerateIcons.swift
//  Draws the Kocharian AI app icon with Core Graphics and writes it into the
//  asset catalog. Run on a Mac from the repository root:
//
//      swift Tools/GenerateIcons.swift
//
//  The committed icon was produced by this exact code, so you only need to run
//  it after changing the artwork below.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("KocharianAI/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("error: could not create a bitmap context")
    exit(1)
}

let s = CGFloat(size)

// MARK: - Background gradient (deep teal → Kocharian green → mint)

let colors = [
    CGColor(red: 0.024, green: 0.235, blue: 0.212, alpha: 1),
    CGColor(red: 0.063, green: 0.639, blue: 0.498, alpha: 1),
    CGColor(red: 0.290, green: 0.871, blue: 0.643, alpha: 1)
] as CFArray
if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1]) {
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: s, y: 0),
                           options: [])
}

// Soft highlight in the upper-left corner.
if let glow = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.30),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0)
] as CFArray, locations: [0, 1]) {
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: s * 0.30, y: s * 0.76), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.30, y: s * 0.76), endRadius: s * 0.62,
                           options: [])
}

// MARK: - The mark: a geometric K with an AI spark

let unit = s * 0.265
let cx = s * 0.5
let cy = s * 0.46          // Core Graphics origin is bottom-left
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let soft = CGColor(red: 0.925, green: 1, blue: 0.973, alpha: 1)

ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setStrokeColor(white)
ctx.setLineWidth(unit * 0.26)

let stemX = cx - unit * 0.72
ctx.move(to: CGPoint(x: stemX, y: cy - unit * 1.05))
ctx.addLine(to: CGPoint(x: stemX, y: cy + unit * 1.05))
ctx.strokePath()

let joint = CGPoint(x: stemX + unit * 0.06, y: cy)
ctx.move(to: joint)
ctx.addLine(to: CGPoint(x: cx + unit * 0.86, y: cy + unit * 0.97))
ctx.strokePath()
ctx.move(to: joint)
ctx.addLine(to: CGPoint(x: cx + unit * 0.88, y: cy - unit * 0.99))
ctx.strokePath()

// Node at the tip of the rising arm.
let node = CGPoint(x: cx + unit * 0.88, y: cy + unit * 0.99)
ctx.setFillColor(soft)
ctx.fillEllipse(in: CGRect(x: node.x - unit * 0.30, y: node.y - unit * 0.30,
                           width: unit * 0.60, height: unit * 0.60))
ctx.setFillColor(CGColor(red: 0.039, green: 0.369, blue: 0.298, alpha: 1))
ctx.fillEllipse(in: CGRect(x: node.x - unit * 0.145, y: node.y - unit * 0.145,
                           width: unit * 0.29, height: unit * 0.29))

// Four-point sparkle above the letter.
let sparkle = CGPoint(x: cx - unit * 0.14, y: cy + unit * 1.39)
let long = unit * 0.26
let short = unit * 0.075
ctx.setFillColor(soft)
for flipped in [false, true] {
    let a = flipped ? short : long
    let b = flipped ? long : short
    ctx.move(to: CGPoint(x: sparkle.x, y: sparkle.y + a))
    ctx.addLine(to: CGPoint(x: sparkle.x + b, y: sparkle.y))
    ctx.addLine(to: CGPoint(x: sparkle.x, y: sparkle.y - a))
    ctx.addLine(to: CGPoint(x: sparkle.x - b, y: sparkle.y))
    ctx.closePath()
    ctx.fillPath()
}

// MARK: - Write

guard let image = ctx.makeImage() else {
    print("error: could not render the icon")
    exit(1)
}
try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    print("error: could not open \(output.path)")
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("Wrote \(output.lastPathComponent) (\(size)×\(size))")
