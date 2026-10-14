import AppKit

/// `Mochi --showcase <dir>` paints the README pictures with the app's own drawing code: a looping desktop
/// scene as numbered frames in <dir>/frames (docs/make-visuals.sh turns them into demo.gif), every coat, and a few moods.
enum Showcase {
    static let size = CGSize(width: 1040, height: 560)
    static let fps = 25
    static let loop: CGFloat = 6

    static func render(to dir: String) {
        let frames = dir + "/frames"
        try? FileManager.default.removeItem(atPath: frames)
        try! FileManager.default.createDirectory(atPath: frames, withIntermediateDirectories: true)
        let scene = Scene()
        let n = Int(loop) * fps, dt = 1 / CGFloat(fps)
        // One loop to get the hearts and z's floating, then the loop that's kept.
        for f in -n..<n {
            let t = CGFloat(f) * dt
            scene.step(t, dt)
            guard f >= 0 else { continue }
            write(paint(size, scale: 1) { scene.draw($0, t) }, to: String(format: "%@/%03d.png", frames, f))
        }
        write(coats(), to: dir + "/coats.png")
        write(moods(), to: dir + "/moods.png")
        print("wrote \(dir)")
    }

    // MARK: Coats and moods

    private static func coats() -> CGImage {
        let cell = CGSize(width: 150, height: 170)
        return paint(CGSize(width: cell.width * CGFloat(Coat.all.count), height: cell.height), scale: 2) { ctx in
            card(ctx, CGRect(origin: .zero, size: CGSize(width: cell.width * CGFloat(Coat.all.count), height: cell.height)))
            for (i, coat) in Coat.all.enumerated() {
                var p = Pose.sitFront()
                p.headTilt = i % 2 == 0 ? 0.07 : -0.07
                p.lookY = 0.15
                let x = cell.width * (CGFloat(i) + 0.5)
                cat(ctx, coat, p, at: CGPoint(x: x, y: 44), scale: 1.45, time: 0.5)
                label(ctx, coat.name, at: CGPoint(x: x, y: 14))
            }
        }
    }

    private static func moods() -> CGImage {
        let ginger = Coat.named("ginger")
        let z = Effects()
        z.spawn(.z, at: CGPoint(x: 30, y: 26), v: CGPoint(x: 9, y: 16), life: 2.4)
        z.update(1.2)
        z.spawn(.z, at: CGPoint(x: 30, y: 26), v: CGPoint(x: 9, y: 16), life: 2.4)
        z.update(0.5)
        let sweat = Effects()
        sweat.spawn(.sweat, at: CGPoint(x: 15, y: -9), v: CGPoint(x: 8, y: 14), life: 0.9)
        sweat.update(0.25)
        // (name, pose, origin height, effects, edge to hang from)
        let list: [(String, Pose, CGFloat, Effects?, Bool)] = [
            ("Sleeping", .sleep(breath: 0.5), 44, z, false),
            ("Grooming", .groom(lick: 0.5, wash: 1), 44, nil, false),
            ("Hanging on", .hang(kick: 0.6, effort: 0.2), 150, sweat, true),
            ("Carried", .held(kick: 0.3), 164, nil, false),
            ("Pouncing", .leap(t: 0.3), 66, nil, false),
            ("Grumpy", Pose.sitFront().grumpy(1), 44, nil, false),
        ]
        let cell = CGSize(width: 150, height: 200)
        let total = CGSize(width: cell.width * CGFloat(list.count), height: cell.height)
        return paint(total, scale: 2) { ctx in
            card(ctx, CGRect(origin: .zero, size: total))
            for (i, (name, pose, y, fx, edge)) in list.enumerated() {
                let x = cell.width * (CGFloat(i) + 0.5)
                if edge {
                    // The top of a window to dangle from.
                    let r = CGRect(x: x - 62, y: y - 84, width: 124, height: 84)
                    let shape = CGPath(roundedRect: CGRect(x: r.minX, y: r.minY - 20, width: r.width, height: r.height + 20),
                                       cornerWidth: 9, cornerHeight: 9, transform: nil)
                    ctx.saveGState()
                    ctx.clip(to: r)
                    ctx.addPath(shape)
                    ctx.setStrokeColor(rgb(0xB9BAC2)); ctx.setLineWidth(2); ctx.strokePath()
                    ctx.addPath(shape)
                    ctx.clip()
                    ctx.setFillColor(rgb(0xFFFFFF)); ctx.fill(r)
                    ctx.setFillColor(rgb(0xF1F0F3)); ctx.fill(CGRect(x: r.minX, y: r.maxY - 20, width: r.width, height: 20))
                    for (k, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
                        ctx.setFillColor(rgb(UInt32(c)))
                        ctx.fillEllipse(in: CGRect(x: r.minX + 9 + CGFloat(k) * 13, y: r.maxY - 14, width: 8, height: 8))
                    }
                    ctx.restoreGState()
                }
                cat(ctx, ginger, pose, at: CGPoint(x: x, y: y), scale: 1.3, time: 0.5, fx: fx)
                label(ctx, name, at: CGPoint(x: x, y: 14))
            }
        }
    }

    // MARK: Helpers

    static func paint(_ size: CGSize, scale: CGFloat, _ body: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        body(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    static func write(_ img: CGImage, to path: String) {
        try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    /// Tail sways are nudged to whole cycles per loop, so the GIF loops without a hitch.
    static func looped(_ speed: CGFloat) -> CGFloat {
        let w = 2 * .pi / loop
        return max(1, (speed / w).rounded()) * w
    }

    static func cat(_ ctx: CGContext, _ coat: Coat, _ pose: Pose, at p: CGPoint, scale: CGFloat, scaleX: CGFloat = 1,
                    time: CGFloat, fx: Effects? = nil, clipBelow: CGFloat? = nil) {
        var pose = pose
        pose.tailSwaySpeed = looped(pose.tailSwaySpeed)
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.saveGState()
        if let b = clipBelow { ctx.clip(to: CGRect(x: -200, y: b, width: 400, height: 400)) }
        ctx.scaleBy(x: scaleX, y: 1)
        CatRenderer(coat: coat, time: time).draw(ctx, pose: pose)
        ctx.restoreGState()
        fx?.draw(ctx)
        ctx.restoreGState()
    }

    static func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, centered: Bool = false) {
        let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        a.draw(at: CGPoint(x: centered ? p.x - a.size().width / 2 : p.x, y: p.y))
    }

    private static func label(_ ctx: CGContext, _ s: String, at p: CGPoint) {
        text(s, at: p, size: 13, weight: .semibold, color: NSColor(srgbRed: 0.33, green: 0.28, blue: 0.24, alpha: 1), centered: true)
    }

    private static func card(_ ctx: CGContext, _ r: CGRect) {
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 18, cornerHeight: 18, transform: nil))
        ctx.setFillColor(rgb(0xF7F1E8))
        ctx.fillPath()
    }
}

/// The looping demo: a little desktop with two windows, the box, the bowls, the yarn ball and seven cats.
private final class Scene {
    let S: CGFloat = 1.2                     // cat (and box, bowls, ball) size
    let W = Showcase.size.width, H = Showcase.size.height
    let windowA = CGRect(x: 40, y: 190, width: 480, height: 270)
    let windowB = CGRect(x: 360, y: 120, width: 420, height: 260)
    var boxOrigin: CGPoint { CGPoint(x: W - 20 - HomeBox.viewSize.width * S, y: 4 - HomeBox.frontRect.minY * S) }
    var bowlsOrigin: CGPoint { CGPoint(x: boxOrigin.x - 8 - Bowls.viewSize.width * S, y: 4 - 4 * S) }

    let gray = Effects(), tux = Effects(), siamese = Effects(), black = Effects(), calico = Effects(), white = Effects()

    private func local(_ t: CGFloat) -> CGFloat { t - floor(t / Showcase.loop) * Showcase.loop }
    private func wave(_ speed: CGFloat, _ t: CGFloat, _ shift: CGFloat = 0) -> CGFloat { sin(Showcase.looped(speed) * t + shift) }
    /// Did a tick of this period (shifted by `at`) happen during the last frame?
    private func every(_ period: CGFloat, at: CGFloat = 0, _ t: CGFloat, _ dt: CGFloat) -> Bool {
        floor((t - at) / period) != floor((t - dt - at) / period)
    }
    private func smooth(_ x: CGFloat) -> CGFloat { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }

    // MARK: Who's doing what

    /// Strolls along the top of window A and back.
    func ginger(_ t: CGFloat) -> (x: CGFloat, scaleX: CGFloat, pose: Pose) {
        let tl = local(t), leg: CGFloat = 2.6
        let d = 8 * .pi * 7 * S                // a whole number of strides each way, so the legs loop too
        let x0: CGFloat = 100
        let dist: CGFloat, x: CGFloat
        var facing: CGFloat = 1, pause: CGFloat = -1
        switch tl {
        case ..<leg: dist = d * tl / leg; x = x0 + dist
        case ..<3: dist = d; x = x0 + d; pause = tl - leg
        case ..<(3 + leg): dist = d + d * (tl - 3) / leg; x = x0 + d - d * (tl - 3) / leg; facing = -1
        default: dist = 2 * d; x = x0; pause = tl - 3 - leg; facing = -1
        }
        var pose = Pose.walk(phase: dist / (8 * S), speed: 60)
        var scaleX = facing
        if pause >= 0 {
            pose.blend(toward: .stand(), smooth(pause / 0.12) * smooth((0.4 - pause) / 0.12))
            // Turn round halfway through the pause, squashing through the middle like the app does.
            let u = min(1, max(0, (pause - 0.05) / 0.3))
            if u > 0.5 { facing = -facing }
            scaleX = facing * (1 - 0.8 * sin(.pi * u))
        }
        return (x, scaleX, pose)
    }

    func step(_ t: CGFloat, _ dt: CGFloat) {
        for fx in [gray, tux, siamese, black, calico, white] { fx.update(dt) }
        // Gray tabby: being petted.
        if every(1.5, at: 0.3, t, dt) { gray.hearts(at: CGPoint(x: 0, y: 40 + 16), count: 2) }
        if every(1.0, at: 0.8, t, dt) {
            gray.spawn(.note, at: CGPoint(x: .random(in: -12...12), y: 40 + 16), v: CGPoint(x: .random(in: -10...10), y: 24), life: 1.3)
        }
        // Tuxedo: hanging on for dear life.
        if every(0.6, t, dt) {
            tux.spawn(.sweat, at: CGPoint(x: .random(in: 12...18) * (Bool.random() ? 1 : -1), y: -17 + 8),
                      v: CGPoint(x: .random(in: -10...10), y: 14), life: 0.9)
        }
        // Siamese: pops back up after ducking.
        if every(Showcase.loop, at: 4.95, t, dt) {
            siamese.spawn(.sparkle, at: CGPoint(x: 16, y: 14.5 + 14), v: CGPoint(x: 10, y: 20), life: 0.7)
        }
        // Black cat: playing with the yarn.
        if every(1.2, at: 0.5, t, dt) {
            black.spawn(Bool.random() ? .sparkle : .heart, at: CGPoint(x: 9 + .random(in: -12...12), y: 42 + 10), v: CGPoint(x: 0, y: 22), life: 0.9)
        }
        // Calico: dinner.
        if every(0.75, t, dt) {
            for _ in 0..<2 {
                calico.spawn(.crumb, at: CGPoint(x: 30, y: 6), v: CGPoint(x: .random(in: -25...25), y: .random(in: 30...70)), life: 0.5)
            }
        }
        if every(3, at: 1, t, dt) { calico.say("nom", at: CGPoint(x: 18, y: 26), color: .systemBrown, life: 1) }
        // Snowball: asleep in the box.
        if every(1.5, at: 0.2, t, dt) { white.spawn(.z, at: CGPoint(x: 10, y: 14.5 + 12), v: CGPoint(x: 9, y: 16), life: 2.4) }
    }

    func draw(_ ctx: CGContext, _ t: CGFloat) {
        let tl = local(t)
        wallpaper(ctx)

        window(ctx, windowA, title: "Notes", sidebar: false)
        let g = ginger(t)
        Showcase.cat(ctx, .named("ginger"), g.pose, at: CGPoint(x: g.x, y: windowA.maxY), scale: S, scaleX: g.scaleX, time: tl)

        // Window B bobs as the tuxedo's weight yanks on it.
        let kick = wave(12, tl)
        let bob = 1.2 * wave(12, tl, 0.6)
        let b = windowB.offsetBy(dx: 0, dy: bob)

        // Siamese, behind window B, peeking over its top edge (ducks down for a moment).
        let duck = smooth((tl - 3.6) / 0.25) * smooth((4.9 - tl) / 0.25)
        var peek = Pose.peek(rise: 1 - 0.75 * duck)
        peek.lookX = -0.7
        peek.headTilt = wave(0.8, tl) * 0.1
        Showcase.cat(ctx, .named("siamese"), peek, at: CGPoint(x: 720, y: b.maxY), scale: S, time: tl, fx: siamese)

        window(ctx, b, title: "Documents", sidebar: true)

        var hang = Pose.hang(kick: kick, effort: 0.25 + 0.2 * wave(5, tl))
        hang.tailSwaySpeed = 6
        Showcase.cat(ctx, .named("tuxedo"), hang, at: CGPoint(x: 430, y: b.maxY), scale: S, time: tl, fx: tux)

        var pet = Pose.sitFront()
        pet.eyes = .happy
        pet.blush = 1.2
        pet.purr = 1
        pet.earPerk = 0.85
        pet.headTilt = wave(2.2, tl) * 0.12
        pet.tailSway = 0.3
        let petX: CGFloat = 575
        Showcase.cat(ctx, .named("gray"), pet, at: CGPoint(x: petX, y: b.maxY), scale: S, time: tl, fx: gray)

        // Black cat batting the yarn ball about, with bunny kicks in between.
        let kicking = smooth((tl - 3.2) / 0.3) * smooth((5.2 - tl) / 0.3)
        let swipe = (wave(7, tl) + 1) / 2
        var play = Pose.bat(swipe)
        play.blend(toward: .bunnyKick(tl * Showcase.looped(15)), kicking)
        let batAt = CGPoint(x: 33 + swipe * 7, y: 9 + abs(wave(7, tl)) * 7)
        let kickAt = CGPoint(x: 24 + wave(15, tl) * 1.5, y: 15 + wave(15, tl, .pi / 2) * 1.2)
        let ball = CGPoint(x: batAt.x + (kickAt.x - batAt.x) * kicking, y: batAt.y + (kickAt.y - batAt.y) * kicking)
        let blackAt = CGPoint(x: 150, y: 4)
        Showcase.cat(ctx, .named("black"), play, at: blackAt, scale: S, time: tl, fx: black)
        ctx.saveGState()
        ctx.translateBy(x: blackAt.x + ball.x * S - Toy.viewSide / 2 * S, y: blackAt.y + ball.y * S - Toy.viewSide / 2 * S)
        ToyView.paint(ctx, scale: S, v: .zero, time: tl, spin: wave(7, tl) * 1.5, grounded: false)
        ctx.restoreGState()

        // Calico eating, face in the bowl (the bowls are in front of her).
        let bo = bowlsOrigin
        let food = CGPoint(x: bo.x + Bowls.foodX * S - 27 * S, y: bo.y + Bowls.matTop * S)
        Showcase.cat(ctx, .named("calico"), .eat(chew: (wave(8, tl) + 1) / 2, drinking: false), at: food, scale: S, time: tl, fx: calico)
        ctx.saveGState()
        ctx.translateBy(x: bo.x, y: bo.y)
        BowlsView.paint(ctx, scale: S, food: 0.8, water: 0.9)
        ctx.restoreGState()

        // Snowball asleep in the box, between its back and front walls.
        let o = boxOrigin
        ctx.saveGState(); ctx.translateBy(x: o.x, y: o.y); ctx.scaleBy(x: S, y: S); BoxView.paint(ctx, .back); ctx.restoreGState()
        var nap = Pose.peek(rise: 1)
        nap.eyes = .sleep
        nap.headTilt = 0.08 + wave(0.8, tl) * 0.06
        nap.fHead.y -= 1 + wave(1.2, tl)
        let rim = CGPoint(x: o.x + HomeBox.rimLocal.x * S, y: o.y + HomeBox.rimLocal.y * S)
        Showcase.cat(ctx, .named("white"), nap, at: rim, scale: S, time: tl, clipBelow: HomeBox.frontRect.minY - HomeBox.rimLocal.y)
        ctx.saveGState(); ctx.translateBy(x: o.x, y: o.y); ctx.scaleBy(x: S, y: S); BoxView.paint(ctx, .front); ctx.restoreGState()
        ctx.saveGState(); ctx.translateBy(x: rim.x, y: rim.y); ctx.scaleBy(x: S, y: S); white.draw(ctx); ctx.restoreGState()

        // Your pointer, stroking the gray tabby's head.
        cursor(ctx, at: CGPoint(x: petX + (17 + 6 * wave(3, tl)) * S, y: b.maxY + (40 + 13) * S + 2.5 * wave(6, tl, 1)))
        menuBar(ctx)
    }

    // MARK: Scenery

    private func wallpaper(_ ctx: CGContext) {
        ctx.setFillColor(rgb(0xC9D6EE)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setFillColor(rgb(0xD7E1F3)); ctx.fillEllipse(in: CGRect(x: 560, y: 150, width: 720, height: 720))
        ctx.setFillColor(rgb(0xBCCBE8)); ctx.fillEllipse(in: CGRect(x: -260, y: -420, width: 900, height: 640))
    }

    private func window(_ ctx: CGContext, _ r: CGRect, title: String, sidebar: Bool) {
        let shape = CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil)
        for (dy, a) in [(-6, 0.07), (-3, 0.08)] as [(CGFloat, CGFloat)] {
            ctx.addPath(CGPath(roundedRect: r.insetBy(dx: -2, dy: -2).offsetBy(dx: 0, dy: dy), cornerWidth: 14, cornerHeight: 14, transform: nil))
            ctx.setFillColor(rgb(0x1E2A44, a)); ctx.fillPath()
        }
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        ctx.setFillColor(rgb(0xFFFFFF)); ctx.fill(r)
        let bar: CGFloat = 28
        ctx.setFillColor(rgb(0xF1F0F3)); ctx.fill(CGRect(x: r.minX, y: r.maxY - bar, width: r.width, height: bar))
        ctx.setFillColor(rgb(0xDDDCE1)); ctx.fill(CGRect(x: r.minX, y: r.maxY - bar - 1, width: r.width, height: 1))
        var left = r.minX + 26
        if sidebar {
            ctx.setFillColor(rgb(0xF4F3F7)); ctx.fill(CGRect(x: r.minX, y: r.minY, width: 118, height: r.height - bar - 1))
            ctx.setFillColor(rgb(0xE3E2E8)); ctx.fill(CGRect(x: r.minX + 118, y: r.minY, width: 1, height: r.height - bar - 1))
            for i in 0..<6 {
                let y = r.maxY - bar - 30 - CGFloat(i) * 25
                ctx.setFillColor(i == 1 ? rgb(0x7FA7E8) : rgb(0xC9CDD8))
                ctx.fillEllipse(in: CGRect(x: r.minX + 14, y: y, width: 10, height: 10))
                bubble(ctx, CGRect(x: r.minX + 30, y: y + 1, width: [64, 50, 70, 44, 58, 52][i], height: 8), rgb(0xD9DBE3))
            }
            left = r.minX + 140
        }
        bubble(ctx, CGRect(x: left, y: r.maxY - bar - 38, width: sidebar ? 170 : 200, height: 14), sidebar ? rgb(0xCADBF7) : rgb(0xD3D6DE))
        let widths: [CGFloat] = [0.92, 0.85, 0.96, 0.6, 0.88, 0.94, 0.72, 0.9, 0.8, 0.5, 0.86, 0.9]
        var y = r.maxY - bar - 66
        var i = 0
        while y > r.minY + 16 {
            bubble(ctx, CGRect(x: left, y: y, width: (r.maxX - 26 - left) * widths[i % widths.count], height: 8), rgb(0xE6E7EC))
            y -= i % 4 == 3 ? 30 : 18
            i += 1
        }
        ctx.restoreGState()
        ctx.addPath(shape); ctx.setStrokeColor(rgb(0xB9BAC2)); ctx.setLineWidth(1); ctx.strokePath()
        for (k, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            ctx.setFillColor(rgb(UInt32(c)))
            ctx.fillEllipse(in: CGRect(x: r.minX + 13 + CGFloat(k) * 20, y: r.maxY - 20, width: 12, height: 12))
        }
        Showcase.text(title, at: CGPoint(x: r.midX, y: r.maxY - 21), size: 13, weight: .semibold,
                      color: NSColor(srgbRed: 0.33, green: 0.33, blue: 0.36, alpha: 1), centered: true)
    }

    private func bubble(_ ctx: CGContext, _ r: CGRect, _ c: CGColor) {
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil))
        ctx.setFillColor(c); ctx.fillPath()
    }

    private func menuBar(_ ctx: CGContext) {
        ctx.setFillColor(rgb(0xFFFFFF, 0.6)); ctx.fill(CGRect(x: 0, y: H - 26, width: W, height: 26))
        let ink = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        var x: CGFloat = 18
        for (i, item) in ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
            let s = NSAttributedString(string: item, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: i == 0 ? .bold : .regular), .foregroundColor: ink])
            s.draw(at: CGPoint(x: x, y: H - 20))
            x += s.size().width + 20
        }
        Showcase.text("Wed 9:41", at: CGPoint(x: W - 76, y: H - 20), size: 13, color: ink)
        AppDelegate.menuIcon().draw(in: CGRect(x: W - 108, y: H - 22, width: 18, height: 18))
    }

    private func cursor(_ ctx: CGContext, at tip: CGPoint) {
        let p = CGMutablePath()
        let pts: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: -17), CGPoint(x: 4.2, y: -13), CGPoint(x: 7, y: -19.5),
                              CGPoint(x: 9.6, y: -18.4), CGPoint(x: 6.9, y: -12.1), CGPoint(x: 12, y: -12)]
        p.addLines(between: pts.map { CGPoint(x: tip.x + $0.x * 1.15, y: tip.y + $0.y * 1.15) })
        p.closeSubpath()
        ctx.saveGState()
        ctx.setLineJoin(.round)
        ctx.addPath(p); ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(3); ctx.strokePath()
        ctx.addPath(p); ctx.setFillColor(rgb(0x111111)); ctx.fillPath()
        ctx.restoreGState()
    }
}
