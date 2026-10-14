import AppKit

extension Sheet {
    static func render(to path: String, coatID: String?) {
        let (W, H) = size(coatID: coatID)
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx, coatID: coatID) { name, at in
            let label = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.gray])
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            label.draw(at: at)
            NSGraphicsContext.restoreGraphicsState()
        }
        let img = ctx.makeImage()!
        let rep = NSBitmapImageRep(cgImage: img)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}

enum Bench {
    static func run() {
        let w = 460, h = 500
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        let poses: [Pose] = [.walk(phase: 1, speed: 60), .sit(), .sleep(breath: 0.5), .sitFront()]
        for (label, image) in [("draw only", false), ("draw+makeImage", true)] {
            let t0 = CACurrentMediaTime()
            for i in 0..<400 {
                ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.saveGState()
                ctx.scaleBy(x: 2, y: 2)
                ctx.translateBy(x: 115, y: 108)
                CatRenderer(coat: .named("ginger"), time: CGFloat(i) * 0.016).draw(ctx, pose: poses[i % 4])
                ctx.restoreGState()
                if image { _ = ctx.makeImage() }
            }
            print(label, String(format: "%.3f ms/frame", (CACurrentMediaTime() - t0) / 400 * 1000))
        }
    }
}
