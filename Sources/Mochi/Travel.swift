import Foundation

// MARK: - Getting from one display to another

/// How two displays meet.
enum Crossing {
    case side(CGFloat)              // the other display is beside this one (+1 right, -1 left)
    case up(CGFloat, CGFloat)       // it sits on top: jump up through the top edge somewhere in lo…hi
    case down(CGFloat, CGFloat)     // it's underneath: drop through the bottom edge somewhere in lo…hi
}

extension World {
    /// Is there a display at this point? Cats and the yarn ball move freely between displays that touch.
    func onAnyScreen(_ p: CGPoint) -> Bool { screens.contains { $0.frame.contains(p) } }

    func screenIndex(of ref: SurfaceRef) -> Int? {
        if case .floor(let i) = ref { return i }
        guard let s = surface(ref) else { return nil }
        return screenIndex(at: CGPoint(x: (s.minX + s.maxX) / 2, y: s.y - 2))
    }

    func crossing(from i: Int, to j: Int) -> Crossing? {
        guard i != j, i < screens.count, j < screens.count else { return nil }
        let a = screens[i].frame, b = screens[j].frame
        let xlo = max(a.minX, b.minX) + 60, xhi = min(a.maxX, b.maxX) - 60
        let ylo = max(a.minY, b.minY), yhi = min(a.maxY, b.maxY)
        if abs(a.maxX - b.minX) < 2 && yhi - ylo > 150 { return .side(1) }
        if abs(b.maxX - a.minX) < 2 && yhi - ylo > 150 { return .side(-1) }
        if abs(a.minY - b.maxY) < 2 && xhi - xlo > 80 { return .up(xlo, xhi) }
        if abs(a.maxY - b.minY) < 2 && xhi - xlo > 80 { return .down(xlo, xhi) }
        return nil
    }

    /// The first display to head for on the way from i to j, going only between displays that touch.
    func nextScreen(from i: Int, toward j: Int) -> Int? {
        var prev = [i: i], frontier = [i]
        while !frontier.isEmpty {
            var next: [Int] = []
            for k in frontier {
                for n in screens.indices where prev[n] == nil && crossing(from: k, to: n) != nil {
                    prev[n] = k
                    next.append(n)
                }
            }
            frontier = next
        }
        guard j != i, prev[j] != nil else { return nil }
        var step = j
        while let p = prev[step], p != i { step = p }
        return step
    }
}

extension Cat {
    /// Which display to visit: the one you're working on if it isn't this one, otherwise any other.
    var travelTarget: Int? {
        let n = world.screens.count
        guard n > 1 else { return nil }
        let here = screenIndex
        let you = world.screenIndex(at: Coords.mouse)
        if you != here { return you }
        return (0..<n).filter { $0 != here }.randomElement()
    }

    /// Head over to display `j`, then carry on with `then`. Returns false if there's no way to start from here.
    @discardableResult
    func travel(to j: Int, then: [Act] = []) -> Bool {
        let i = screenIndex
        guard j < world.screens.count, let s = currentSurface, let floorA = world.surface(.floor(i)) else { return false }
        if j == i { queue = then; return true }
        let again = TravelLater(j, then: then)
        let onFloor = s.ref == .floor(i)

        /// Everything starts from the floor (or a window top near the top edge, for going up).
        func getDown(_ dir: CGFloat? = nil) -> Bool {
            let d = dir ?? (Bool.random() ? 1 : -1)
            switch s.ref {
            case .window, .bowls:
                queue = [Walk(to: d < 0 ? s.minX : s.maxX, speed: 70), HopOff(dir: d), again]
            case .box:
                queue = [LeaveBox(dir: d), Jump(to: floorA.ref, x: floorA.clamp(pos.x + d * 130 * scale), crouch: 0.4, canSlip: false), again]
            case .floor:
                return false
            }
            return true
        }

        guard let k = world.nextScreen(from: i, toward: j), let cross = world.crossing(from: i, to: k),
              let floorB = world.surface(.floor(k)) else {
            return onFloor ? sneakAround(to: j, then: then) : getDown()
        }
        let rest: [Act] = k == j ? then : [TravelLater(j, then: then)]
        switch cross {
        case .side(let dir):
            guard onFloor else { return getDown(dir) }
            let edge = dir > 0 ? floorA.maxX : floorA.minX
            let entry = (dir > 0 ? floorB.minX : floorB.maxX) + dir * .random(in: 40...160) * scale
            let rise = floorA.y - floorB.y           // how much higher the floor over there is
            if abs(rise) < 4 {
                // Same height: just stroll across.
                queue = [Walk(to: edge, speed: 65), StepOnto(.floor(k)), Walk(to: entry, speed: 65)] + rest
            } else if rise < 0 {
                queue = [Walk(to: edge, speed: 65), HopOff(dir: dir)] + rest
            } else if rise < 400 {
                queue = [Walk(to: edge - dir * 50 * scale, speed: 65), Jump(to: .floor(k), x: entry, crouch: 0.7, canSlip: false)] + rest
            } else {
                return sneakAround(to: j, then: then)
            }
            return true
        case .up(let lo, let hi):
            if climbUp(floor: floorB, lo: lo, hi: hi, from: s, rest: rest, again: again) { return true }
            return onFloor ? sneakAround(to: j, then: then) : getDown()
        case .down(let lo, let hi):
            guard onFloor else { return getDown() }
            // Somewhere over the display below, preferably where nothing hides the cat.
            let spots = (0..<12).map { _ in floorA.clamp(min(hi, max(lo, pos.x + .random(in: -300...300)))) }
            let x = spots.first { !world.covered(CGPoint(x: $0, y: floorA.y - 20), above: z) } ?? spots[0]
            queue = [Walk(to: x, speed: 65), DropDown(through: i)] + rest
            return true
        }
    }

    /// The display above is reached by jumping up from a window top close to the top edge.
    private func climbUp(floor fb: Surface, lo: CGFloat, hi: CGFloat, from s: Surface, rest: [Act], again: Act) -> Bool {
        let reach: CGFloat = 400 * max(1, scale)
        /// A visible spot on `t` from which the display above is within a jump.
        func launch(on t: Surface) -> CGFloat? {
            let a = max(t.minX + 20, lo), b = min(t.maxX - 20, hi)
            guard b > a, t.y - fb.y < reach, t.y - fb.y > 30 else { return nil }
            let near = min(b, max(a, pos.x))
            let tries = [near] + (0..<10).map { _ in CGFloat.random(in: a...b) }
            return tries.first { !world.covered(CGPoint(x: $0, y: t.y - 20), above: t.z) }
        }
        if case .window = s.ref, let x = launch(on: s) {
            let lx = fb.clamp(x + .random(in: -140...140) * scale)
            queue = [Walk(to: x, speed: 65), SetDepth(.top), Jump(to: fb.ref, x: lx, crouch: 0.8, canSlip: false)] + rest
            return true
        }
        guard s.ref == .floor(screenIndex) else { return false }
        // Climb up the back of a tall window first, and set off from its top.
        let options = world.windowSurfaces(screen: screenIndex).filter { t in
            launch(on: t) != nil && min(s.maxX, t.maxX - 20) > max(s.minX, t.minX + 20)
        }
        guard let t = options.min(by: { abs(($0.minX + $0.maxX) / 2 - pos.x) < abs(($1.minX + $1.maxX) / 2 - pos.x) }),
              let id = t.ref.windowID else { return false }
        let lo2 = max(s.minX, t.minX + 20), hi2 = min(s.maxX, t.maxX - 20)
        let cx = min(hi2, max(lo2, pos.x + .random(in: -150...150)))
        if t.z > z {
            queue = [Walk(to: cx, speed: 65), Climb(id), again]
        } else if let (sx, d) = sneakSpot(on: s, behind: id) {
            queue = [Walk(to: sx, speed: 65), SetDepth(d), Walk(to: cx, speed: 65), Climb(id), again]
        } else {
            return false
        }
        return true
    }

    /// No way across from here: slip off the side of this display and stroll in from the side of the other.
    private func sneakAround(to j: Int, then: [Act]) -> Bool {
        let i = screenIndex
        guard let fa = world.surface(.floor(i)), let fb = world.surface(.floor(j)) else { return false }
        let a = world.screens[i].frame, b = world.screens[j].frame
        func open(_ f: CGRect, _ d: CGFloat, _ y: CGFloat) -> Bool {
            !world.onAnyScreen(CGPoint(x: d < 0 ? f.minX - 80 : f.maxX + 80, y: y))
        }
        let exits = [CGFloat(-1), 1].filter { open(a, $0, fa.y - 30) }
        let entries = [CGFloat(-1), 1].filter { open(b, $0, fb.y - 30) }
        guard let side = entries.randomElement(),
              let out = exits.min(by: { abs(($0 < 0 ? fa.minX : fa.maxX) - pos.x) < abs(($1 < 0 ? fa.minX : fa.maxX) - pos.x) })
        else { return false }
        queue = [Walk(to: out < 0 ? fa.minX : fa.maxX, speed: 65), Offstage(dir: out, to: j, enterFrom: side)] + then
        return true
    }
}

/// Re-plans the rest of a trip once the cat has got somewhere.
final class TravelLater: Act {
    let dest: Int
    let then: [Act]
    init(_ dest: Int, then: [Act]) {
        self.dest = dest
        self.then = then
    }
    override func begin(_ c: Cat) { if !c.travel(to: dest, then: then) { c.queue = [] } }
}

/// Step from one floor onto the next one along, at the same height.
final class StepOnto: Act {
    let ref: SurfaceRef
    init(_ ref: SurfaceRef) { self.ref = ref }
    override func begin(_ c: Cat) { if let s = c.world.surface(ref) { c.stand(on: s, x: c.pos.x) } }
}

/// Peer down over the bottom edge, wiggle, and drop through onto the display below.
final class DropDown: Act {
    let from: Int
    init(through i: Int) { from = i }
    override var status: String { "Off to the other screen" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 12
        c.lookAtCursor = false
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        c.target = .crouch(wiggle: t > 0.35 ? sin(t * 17) : 0)
        c.target.lookY = -0.7
        if t < 0.8 { return true }
        c.effects.dust(at: .zero, strength: 0.5)
        c.interrupt(with: [Fall(vx: c.facing * 60, vy: -380, through: from)] + c.queue)
        return true
    }
}

/// Wander off the edge of the screen, then stroll in from the side of another display.
final class Offstage: Act {
    let dir: CGFloat
    let dest: Int
    let side: CGFloat
    private var away: CGFloat?
    private var goal: CGFloat = 0
    init(dir: CGFloat, to dest: Int, enterFrom side: CGFloat) {
        self.dir = dir
        self.dest = dest
        self.side = side
    }
    override var status: String { "Off to the other screen" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 14
        c.lookAtCursor = false
        let f = c.world.screen(at: c.pos).frame
        goal = dir < 0 ? f.minX - 120 * c.scale : f.maxX + 120 * c.scale
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        let w = c.world
        if let since = away {
            // Out of sight for a moment, then pop up beside the other display.
            guard t - since > 1.2 else { return true }
            guard dest < w.screens.count, let fb = w.surface(.floor(dest)) else { return false }
            let f = w.screens[dest].frame
            let x = side < 0 ? f.minX - 120 * c.scale : f.maxX + 120 * c.scale
            c.stand(on: fb, x: x)
            c.depth = .desktop
            c.facing = -side
            c.snapTurn()
            let inside = side < 0 ? fb.minX + .random(in: 60...260) : fb.maxX - .random(in: 60...260)
            c.queue.insert(Walk(to: inside, speed: 65), at: 0)
            return false
        }
        if c.trot(to: goal, speed: 65, dt) { away = t }
        return true
    }
}
