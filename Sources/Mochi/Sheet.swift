import AppKit

/// Debug helper: `Mochi --sheet out.png [coat]` renders every pose into a grid image.
enum Sheet {
    static func render(to path: String, coatID: String?) {
        let coats = coatID.map { [Coat.named($0)] } ?? Coat.all
        let poses: [(String, Pose)] = [
            ("stand", .stand()), ("walk", .walk(phase: 0.6, speed: 60)), ("run", .walk(phase: 2.0, speed: 240)),
            ("sit", .sit()), ("loaf", .loaf()), ("sleep", .sleep(breath: 0.5)),
            ("crouch", .crouch(wiggle: 0.5)), ("leap up", .leap(t: 0.2)), ("leap down", .leap(t: 0.8)),
            ("stretch", .stretch(yawn: 0)), ("yawn", .stretch(yawn: 1)), ("groom lick", .groom(lick: 0.5, wash: 0)),
            ("groom wash", .groom(lick: 0.5, wash: 1)), ("sit front", .sitFront()), ("hang", .hang(kick: 0.6, effort: 0.2)),
            ("peek", .peek(rise: 1)), ("climb", .climb(phase: 1)), ("held", .held(kick: 0.3)), ("fall", .fall()),
            ("happy", { var p = Pose.sitFront(); p.eyes = .happy; p.blush = 1; return p }()),
            ("grumpy sit", Pose.sit().grumpy(1)), ("grumpy front", Pose.sitFront().grumpy(1)), ("hiss", .hiss()),
            ("sulk", .sulk()), ("eat", .eat(chew: 0.5, drinking: false)), ("drink", .eat(chew: 0.7, drinking: true)),
            ("bunny kick", .bunnyKick(1)), ("bat", .bat(0.6)), ("boop", .boop(1)), ("lick friend", .lickFriend(0.6)),
            ("startled", .startled()), ("fight", Pose()), ("meow", { var p = Pose.sitFront().grumpy(0.8); p.mouthOpen = 0.7; return p }()),
        ]
        let cell: CGFloat = 150, scale: CGFloat = 2
        let perRow = coatID == nil ? poses.count : 10
        let cols = perRow, rows = coats.count * ((poses.count + perRow - 1) / perRow)
        let W = Int(CGFloat(cols) * cell * scale), H = Int(CGFloat(rows) * cell * scale)
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(rgb(0xF4F1EC)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.scaleBy(x: scale, y: scale)
        for (ci, coat) in coats.enumerated() {
            for (i, (name, pose)) in poses.enumerated() {
                let c = i % perRow, r = ci * ((poses.count + perRow - 1) / perRow) + i / perRow
                let ox = CGFloat(c) * cell, oy = CGFloat(rows - 1 - r) * cell
                // Edge line for poses anchored on an edge.
                let anchoredOnEdge = ["hang", "peek", "climb", "held"].contains(name)
                let origin = CGPoint(x: ox + cell / 2, y: oy + (anchoredOnEdge ? cell * 0.62 : cell * 0.22))
                ctx.setStrokeColor(rgb(0xB9B2A8)); ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: ox + 8, y: origin.y)); ctx.addLine(to: CGPoint(x: ox + cell - 8, y: origin.y)); ctx.strokePath()
                ctx.saveGState()
                ctx.translateBy(x: origin.x, y: origin.y)
                if name == "fight" {
                    CatRenderer(coat: coat, time: 0.4).drawFightCloud(ctx, other: Coat.all[(Coat.all.firstIndex { $0.id == coat.id }! + 2) % Coat.all.count])
                } else {
                    CatRenderer(coat: coat, time: 0.4).draw(ctx, pose: pose)
                }
                ctx.restoreGState()
                if ci == 0 {
                    let label = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.gray])
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                    label.draw(at: CGPoint(x: ox + 6, y: oy + cell - 14))
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
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
