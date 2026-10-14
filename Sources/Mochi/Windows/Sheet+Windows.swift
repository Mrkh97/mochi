import CDirect2D
import Foundation

extension Sheet {
    static func render(to path: String, coatID: String?, on win: WinPlatform) {
        let (W, H) = size(coatID: coatID)
        guard mg_canvas_begin(win.canvas, Int32(W), Int32(H)) != 0 else { return print("couldn't draw \(W)x\(H)") }
        let ctx = CGContext(canvas: win.canvas, width: W, height: H)
        draw(ctx, coatID: coatID) { name, at in
            ctx.saveGState()
            ctx.translateBy(x: at.x + CGFloat(name.count) * 2.6, y: at.y + 4)
            ctx.drawLetters(name, size: 9, color: rgb(0x8E8E93), outline: 0)
            ctx.restoreGState()
        }
        mg_canvas_end(win.canvas)
        let ok = mg_canvas_save_png(win.canvas, Win32.wide(path)) != 0
        print(ok ? "wrote \(path)" : "couldn't write \(path)")
    }
}

/// `Mochi --bench`: how long one cat frame takes to draw.
enum Bench {
    static func run(on win: WinPlatform) {
        let w = 460, h = 500
        let poses: [Pose] = [.walk(phase: 1, speed: 60), .sit(), .sleep(breath: 0.5), .sitFront()]
        let t0 = win.now()
        for i in 0..<400 {
            mg_canvas_begin(win.canvas, Int32(w), Int32(h))
            let ctx = CGContext(canvas: win.canvas, width: w, height: h)
            ctx.scaleBy(x: 2, y: 2)
            ctx.translateBy(x: 115, y: 108)
            CatRenderer(coat: .named("ginger"), time: CGFloat(i) * 0.016).draw(ctx, pose: poses[i % 4])
            mg_canvas_end(win.canvas)
        }
        print(String(format: "draw %.3f ms/frame", (win.now() - t0) / 400 * 1000))
    }
}
