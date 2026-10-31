// Draws the app icon and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
//
// Everything is laid out on Apple's 1024 grid, top-left origin: an 824-point
// rounded tile inset by 100, a usage ring around a robot head, and signal bars
// filling the ring's gap in the lower right.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha
  )
}

func gradient(_ colors: [CGColor]) -> CGGradient {
  CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

/// Fills `path` with a vertical gradient spanning `rect`.
func fill(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], over rect: CGRect) {
  ctx.saveGState()
  ctx.addPath(path)
  ctx.clip()
  ctx.drawLinearGradient(
    gradient(colors),
    start: CGPoint(x: rect.midX, y: rect.minY),
    end: CGPoint(x: rect.midX, y: rect.maxY),
    options: []
  )
  ctx.restoreGState()
}

func draw(_ ctx: CGContext) {
  let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
  let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

  // Tile, with the drop shadow macOS expects under a full-bleed icon.
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: rgb(0x000000, 0.35))
  ctx.addPath(tilePath)
  ctx.setFillColor(rgb(0x121A33))
  ctx.fillPath()
  ctx.restoreGState()
  fill(ctx, tilePath, [rgb(0x1E2A4D), rgb(0x0C1226)], over: tile)

  // Usage ring: slate track from 12 o'clock down the left side to 6 o'clock,
  // green usage from 12 o'clock round to just past 3.
  let center = CGPoint(x: 512, y: 512)
  let radius: CGFloat = 300
  let stroke: CGFloat = 46
  let track = CGMutablePath()
  track.addArc(center: center, radius: radius, startAngle: radians(270), endAngle: radians(85), clockwise: true)
  let usage = CGMutablePath()
  usage.addArc(center: center, radius: radius, startAngle: radians(270), endAngle: radians(10), clockwise: false)

  for (arc, colors) in [(track, [rgb(0x5A6789), rgb(0x3A4666)]), (usage, [rgb(0x7CF5C4), rgb(0x1ED68C)])] {
    let outline = arc.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 0)
    fill(ctx, outline, colors, over: outline.boundingBox)
  }

  // Signal bars, bottoms aligned, climbing to the right.
  for (index, height) in [CGFloat(92), 150, 208].enumerated() {
    let bar = CGRect(x: 604 + CGFloat(index) * 86, y: 810 - height, width: 48, height: height)
    let path = CGPath(roundedRect: bar, cornerWidth: 12, cornerHeight: 12, transform: nil)
    fill(ctx, path, [rgb(0x5CF0B6), rgb(0x1ED68C)], over: bar)
  }

  // Robot: antenna, ears, then the head over them, then the eyes.
  let face = [rgb(0xF7F8FF), rgb(0xC3CBF6)]
  let head = CGRect(x: 342, y: 418, width: 340, height: 212)
  let parts = CGMutablePath()
  parts.addRoundedRect(in: CGRect(x: 501, y: 345, width: 22, height: 80), cornerWidth: 11, cornerHeight: 11)
  parts.addEllipse(in: CGRect(x: 484, y: 300, width: 56, height: 56))
  parts.addRoundedRect(in: CGRect(x: 298, y: 474, width: 60, height: 100), cornerWidth: 24, cornerHeight: 24)
  parts.addRoundedRect(in: CGRect(x: 666, y: 474, width: 60, height: 100), cornerWidth: 24, cornerHeight: 24)
  fill(ctx, parts, [rgb(0xDDE2FF), rgb(0xA9B3EA)], over: CGRect(x: 298, y: 300, width: 428, height: 274))

  let headPath = CGPath(roundedRect: head, cornerWidth: 84, cornerHeight: 84, transform: nil)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: rgb(0x000000, 0.4))
  ctx.addPath(headPath)
  ctx.setFillColor(face[1])
  ctx.fillPath()
  ctx.restoreGState()
  fill(ctx, headPath, face, over: head)

  ctx.setFillColor(rgb(0x1A2244))
  for x in [CGFloat(438), 556] {
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 490, width: 30, height: 68), cornerWidth: 15, cornerHeight: 15, transform: nil))
  }
  ctx.fillPath()
}

func render(size: Int) -> CGImage {
  let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  let scale = CGFloat(size) / 1024
  // Flip to a top-left origin so the layout reads like the design.
  ctx.translateBy(x: 0, y: CGFloat(size))
  ctx.scaleBy(x: scale, y: -scale)
  draw(ctx)
  return ctx.makeImage()!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
  for factor in [1, 2] {
    let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    let url = iconset.appendingPathComponent(name) as CFURL
    let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, render(size: points * factor), nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(name)") }
  }
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print(output.path)
