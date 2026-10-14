import AppKit

/// `Mochi --icon out.png` renders the 1024px app icon from the cat itself.
enum Icon {
    static func render(to path: String) {
        let size = 1024
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.addPath(shape)
        ctx.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [rgb(0xFFF4E2), rgb(0xFFD9B0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
        ctx.saveGState()
        ctx.translateBy(x: 512, y: 350)
        ctx.scaleBy(x: 11, y: 11)
        var pose = Pose.peek(rise: 1)
        pose.eyes = .open
        pose.blush = 1
        pose.lookY = 0.2
        pose.headTilt = 0.08
        CatRenderer(coat: .named("ginger"), time: 0).draw(ctx, pose: pose)
        ctx.restoreGState()
        // A cardboard box edge for the cat to peek over.
        ctx.setFillColor(BoxView.card)
        ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 250))
        ctx.setStrokeColor(BoxView.line)
        ctx.setLineWidth(14)
        ctx.move(to: CGPoint(x: 100, y: 350)); ctx.addLine(to: CGPoint(x: 924, y: 350)); ctx.strokePath()
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}
