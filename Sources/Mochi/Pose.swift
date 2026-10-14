import CoreGraphics

/// Which way we are looking at the cat.
enum ViewKind { case side, front }

enum EyeStyle {
    case open       // big shiny eyes
    case happy      // ^ ^
    case sleep      // ◡ ◡
    case wide       // O O  (surprised: white eyes, tiny pupils)
    case struggle   // > <
    case none       // back of the head, no face
}

/// Every drawable parameter of the cat. Cat-local coordinates: origin is the contact point
/// (feet on a surface, paws on an edge, or the scruff when held), y points up, cat faces +x.
/// Poses are blended field-by-field every frame, which keeps all motion soft and squishy.
struct Pose {
    var view: ViewKind = .side

    // Face (shared by both views)
    var eyes: EyeStyle = .open
    var eyeOpen: CGFloat = 1
    var lookX: CGFloat = 0
    var lookY: CGFloat = 0
    var mouthOpen: CGFloat = 0
    var tongue: CGFloat = 0
    var earPerk: CGFloat = 1       // 1 = up, 0 = flattened
    var earTwitch: CGFloat = 0
    var blush: CGFloat = 0.55
    var headTilt: CGFloat = 0
    var headTurn: CGFloat = 1      // -1 three-quarter left, 0 facing viewer, 1 three-quarter right
    var brow: CGFloat = 0          // 1 = furious brows
    var frown: CGFloat = 0         // 1 = grumpy mouth
    var puff: CGFloat = 0          // 1 = bottle-brush tail
    var back = false               // front view, but seen from behind (sulking)

    // Tail (shared). Angle in radians, pi/2 = straight up.
    var tailAngle: CGFloat = 2.2
    var tailCurl: CGFloat = -0.6
    var tailLen: CGFloat = 1
    var tailSway: CGFloat = 0.15
    var tailSwaySpeed: CGFloat = 2.2

    // Whole-body
    var shadow: CGFloat = 1
    var squashX: CGFloat = 1
    var squashY: CGFloat = 1
    var rotation: CGFloat = 0
    var purr: CGFloat = 0

    // Side view
    var body = CGPoint(x: 0, y: 17)
    var bodyW: CGFloat = 44
    var bodyH: CGFloat = 26
    var bodyAngle: CGFloat = 0
    var head = CGPoint(x: 23, y: 33)
    var headScale: CGFloat = 1
    var footFN = CGPoint(x: 12, y: 0)   // front near
    var footFF = CGPoint(x: 15, y: 0)   // front far
    var footBN = CGPoint(x: -13, y: 0)  // back near
    var footBF = CGPoint(x: -10, y: 0)  // back far
    var haunch: CGFloat = 0
    var tuck: CGFloat = 0               // 1 = legs folded away under the body (loaf / sleep)

    // Front view
    var fBody = CGPoint(x: 0, y: 17)
    var fBodyW: CGFloat = 34
    var fBodyH: CGFloat = 32
    var fHead = CGPoint(x: 0, y: 42)
    var pawL = CGPoint(x: -7, y: 1)
    var pawR = CGPoint(x: 7, y: 1)
    var footL = CGPoint(x: -13, y: 1)
    var footR = CGPoint(x: 13, y: 1)
    var shoulderY: CGFloat = 9          // shoulders sit this far above fBody's center
    var pawsFront = false               // draw front paws over the chin (peeking)
    var tailFront = false               // draw the tail over the body (wrapped round)
    var fHaunch: CGFloat = 1
    var grip: CGFloat = 0               // 1 = paws shown gripping an edge from above

    mutating func blend(toward t: Pose, _ k: CGFloat) {
        func m(_ a: inout CGFloat, _ b: CGFloat) { a += (b - a) * k }
        func p(_ a: inout CGPoint, _ b: CGPoint) { a.x += (b.x - a.x) * k; a.y += (b.y - a.y) * k }
        view = t.view
        pawsFront = t.pawsFront
        tailFront = t.tailFront
        back = t.back
        m(&brow, t.brow); m(&frown, t.frown); m(&puff, t.puff)
        eyes = t.eyes
        m(&eyeOpen, t.eyeOpen); m(&lookX, t.lookX); m(&lookY, t.lookY)
        m(&mouthOpen, t.mouthOpen); m(&tongue, t.tongue); m(&earPerk, t.earPerk)
        m(&earTwitch, t.earTwitch); m(&blush, t.blush); m(&headTilt, t.headTilt); m(&headTurn, t.headTurn)
        m(&tailAngle, t.tailAngle); m(&tailCurl, t.tailCurl); m(&tailLen, t.tailLen)
        m(&tailSway, t.tailSway); m(&tailSwaySpeed, t.tailSwaySpeed)
        m(&shadow, t.shadow); m(&squashX, t.squashX); m(&squashY, t.squashY)
        m(&rotation, t.rotation); m(&purr, t.purr)
        p(&body, t.body); m(&bodyW, t.bodyW); m(&bodyH, t.bodyH); m(&bodyAngle, t.bodyAngle)
        p(&head, t.head); m(&headScale, t.headScale)
        p(&footFN, t.footFN); p(&footFF, t.footFF); p(&footBN, t.footBN); p(&footBF, t.footBF)
        m(&haunch, t.haunch); m(&tuck, t.tuck)
        p(&fBody, t.fBody); m(&fBodyW, t.fBodyW); m(&fBodyH, t.fBodyH); p(&fHead, t.fHead)
        p(&pawL, t.pawL); p(&pawR, t.pawR); p(&footL, t.footL); p(&footR, t.footR)
        m(&shoulderY, t.shoulderY); m(&fHaunch, t.fHaunch); m(&grip, t.grip)
    }
}

// MARK: - Pose library

extension Pose {
    /// Standing on all fours.
    static func stand() -> Pose { Pose() }

    /// Walking / trotting. `phase` advances with distance travelled.
    static func walk(phase: CGFloat, speed: CGFloat) -> Pose {
        var p = Pose()
        let run = min(1, max(0, (speed - 70) / 160))
        let stride: CGFloat = 6 + 5 * run
        let lift: CGFloat = 4 + 3 * run
        func foot(_ hipX: CGFloat, _ ph: CGFloat) -> CGPoint {
            CGPoint(x: hipX - stride * cos(ph), y: lift * max(0, sin(ph)))
        }
        p.footFN = foot(12, phase)
        p.footBF = foot(-10, phase + 0.25)
        p.footFF = foot(15, phase + .pi)
        p.footBN = foot(-13, phase + .pi + 0.25)
        let bob = abs(sin(phase)) * (1.2 + run)
        p.body.y = 17 + bob
        p.head.y = 33 + bob * 0.8 + sin(phase * 2) * 0.4
        p.head.x = 23 + run * 3
        p.bodyW = 44 + run * 6
        p.bodyH = 26 - run * 2
        p.bodyAngle = -0.04 * run
        // Happy question-mark tail while walking; streams behind when running.
        p.tailAngle = 1.75 + run * 0.9
        p.tailCurl = -0.9 + run * 0.7
        p.tailSway = 0.12
        p.tailSwaySpeed = 3
        p.earPerk = 1 - run * 0.35
        p.headTurn = 1
        return p
    }

    /// Sitting upright, side view, tail wrapped round the paws.
    static func sit() -> Pose {
        var p = Pose()
        p.body = CGPoint(x: -3, y: 20)
        p.bodyW = 40; p.bodyH = 27
        p.bodyAngle = 0.95
        p.head = CGPoint(x: 6, y: 45)
        p.footFN = CGPoint(x: 7, y: 0); p.footFF = CGPoint(x: 10, y: 0)
        p.footBN = CGPoint(x: 0, y: 0); p.footBF = CGPoint(x: 3, y: 0)
        p.haunch = 1
        p.tailAngle = 3.25; p.tailCurl = -0.85; p.tailLen = 1.05
        p.tailSway = 0.06; p.tailSwaySpeed = 1.6
        p.headTurn = 0.55
        return p
    }

    /// The loaf: legs tucked, perfectly bread-shaped.
    static func loaf() -> Pose {
        var p = Pose()
        p.body = CGPoint(x: -2, y: 12.5)
        p.bodyW = 46; p.bodyH = 25
        p.head = CGPoint(x: 18, y: 28)
        p.tuck = 1
        p.footFN = CGPoint(x: 15, y: 1); p.footFF = CGPoint(x: 18, y: 1)
        p.footBN = CGPoint(x: -14, y: 2); p.footBF = CGPoint(x: -11, y: 2)
        p.tailAngle = 3.2; p.tailCurl = -0.7; p.tailLen = 0.95
        p.tailSway = 0.05; p.tailSwaySpeed = 1.2
        p.headTurn = 0.45
        return p
    }

    /// Curled up asleep. `breath` is a slow 0...1 oscillation.
    static func sleep(breath: CGFloat) -> Pose {
        var p = loaf()
        p.body = CGPoint(x: -2, y: 11 + breath * 0.8)
        p.bodyW = 47 + breath * 1.2; p.bodyH = 22 + breath * 1.4
        p.head = CGPoint(x: 17, y: 16 + breath * 0.5)
        p.headTilt = -0.28
        p.headScale = 0.97
        p.eyes = .sleep
        p.earPerk = 0.75
        p.tailAngle = -0.12; p.tailCurl = 0.42; p.tailLen = 1.3
        p.tailFront = true
        p.tailSway = 0.02; p.tailSwaySpeed = 0.6
        p.blush = 0.75
        p.headTurn = 0.2
        p.shadow = 1.1
        return p
    }

    /// Low crouch, eyes locked on target, ready to pounce (`wiggle` drives the butt wiggle).
    static func crouch(wiggle: CGFloat) -> Pose {
        var p = Pose()
        p.body = CGPoint(x: -1 + wiggle * 2.2, y: 12)
        p.bodyW = 46; p.bodyH = 23
        p.bodyAngle = -0.12 + wiggle * 0.04
        p.head = CGPoint(x: 24, y: 23)
        p.footFN = CGPoint(x: 15, y: 0); p.footFF = CGPoint(x: 18, y: 0)
        p.footBN = CGPoint(x: -12, y: 0); p.footBF = CGPoint(x: -9, y: 0)
        p.tailAngle = 2.9 + wiggle * 0.2; p.tailCurl = -0.3
        p.tailSway = 0.25; p.tailSwaySpeed = 9
        p.earPerk = 0.85
        p.headTurn = 1
        p.lookX = 1
        p.eyeOpen = 1.1
        return p
    }

    /// In the air. `t` goes 0 (launch) -> 1 (landing).
    static func leap(t: CGFloat) -> Pose {
        var p = Pose()
        let reach = 1 - abs(t - 0.5) * 2 // 0 at ends, 1 at apex
        let up = t < 0.5
        p.body = CGPoint(x: 0, y: 20)
        p.bodyW = 52 - reach * 4; p.bodyH = 22
        p.bodyAngle = up ? 0.3 * (1 - t * 2) : -0.3 * (t * 2 - 1)
        p.head = CGPoint(x: 27, y: 33 + (up ? 4 : -2))
        p.footFN = CGPoint(x: 30, y: up ? 18 : 2)
        p.footFF = CGPoint(x: 33, y: up ? 16 : 4)
        p.footBN = CGPoint(x: -30, y: up ? 4 : 12)
        p.footBF = CGPoint(x: -27, y: up ? 6 : 14)
        p.tailAngle = 3.0; p.tailCurl = -0.25
        p.tailSway = 0.05
        p.earPerk = 0.8
        p.shadow = 0
        p.headTurn = 1
        return p
    }

    /// Big stretch: front paws reaching, bum in the air.
    static func stretch(yawn: CGFloat) -> Pose {
        var p = Pose()
        p.body = CGPoint(x: -2, y: 16)
        p.bodyW = 52; p.bodyH = 22
        p.bodyAngle = -0.38
        p.head = CGPoint(x: 26, y: 15 + yawn * 3)
        p.headTilt = 0.15 * yawn
        p.footFN = CGPoint(x: 30, y: 0); p.footFF = CGPoint(x: 34, y: 0)
        p.footBN = CGPoint(x: -15, y: 0); p.footBF = CGPoint(x: -12, y: 0)
        p.tailAngle = 1.9; p.tailCurl = -0.5
        p.tailSway = 0.08
        p.eyes = yawn > 0.3 ? .happy : .open
        p.eyeOpen = 1 - yawn
        p.mouthOpen = yawn
        p.tongue = yawn * 0.6
        p.earPerk = 1 - yawn * 0.4
        p.headTurn = 0.7
        return p
    }

    /// Sitting and grooming. `lick` 0...1 is the licking cycle; `wash` blends into face-washing.
    static func groom(lick: CGFloat, wash: CGFloat) -> Pose {
        var p = sit()
        p.head = CGPoint(x: 7 + wash * 1, y: 43 - (1 - wash) * 2)
        p.headTilt = -0.25 + wash * 0.4 + lick * 0.06
        p.eyes = .sleep
        p.headTurn = 0.5
        // Paw raised to the mouth, or swiping over the ear when washing.
        let licking = CGPoint(x: 17, y: 30 + lick * 2)
        let washing = CGPoint(x: 14 + 4 * cos(lick * .pi), y: 40 + 7 * sin(lick * .pi))
        p.footFN = CGPoint(x: licking.x + (washing.x - licking.x) * wash,
                           y: licking.y + (washing.y - licking.y) * wash)
        p.tongue = (1 - wash) * (0.5 + 0.5 * sin(lick * .pi))
        p.mouthOpen = p.tongue * 0.35
        p.earPerk = 0.9 - wash * 0.2
        p.earTwitch = wash * sin(lick * .pi) * 0.5
        p.blush = 0.7
        return p
    }

    /// Facing the viewer, sitting. The cutest pose.
    static func sitFront() -> Pose {
        var p = Pose()
        p.view = .front
        p.headTurn = 0
        p.fBodyW = 37; p.fBodyH = 31
        p.shoulderY = 6
        p.pawL = CGPoint(x: -6.5, y: 0.5); p.pawR = CGPoint(x: 6.5, y: 0.5)
        p.footL = CGPoint(x: -15, y: 0.5); p.footR = CGPoint(x: 15, y: 0.5)
        p.fHead = CGPoint(x: 0, y: 40)
        p.tailAngle = 0.2; p.tailCurl = 1.4; p.tailLen = 1
        p.tailSway = 0.05; p.tailSwaySpeed = 1.5
        return p
    }

    /// Dangling from an edge by the front paws (origin = the edge).
    static func hang(kick: CGFloat, effort: CGFloat) -> Pose {
        var p = Pose()
        p.view = .front
        p.headTurn = 0
        p.grip = 1
        p.fHead = CGPoint(x: 0, y: -17 + effort * 5)
        p.fBody = CGPoint(x: kick * 1.5, y: -41 + effort * 5)
        p.fBodyW = 27; p.fBodyH = 33
        p.shoulderY = 12
        p.pawL = CGPoint(x: -16, y: 0.5); p.pawR = CGPoint(x: 16, y: 0.5)
        p.footL = CGPoint(x: -8 + kick * 3, y: -63 + effort * 7 + max(0, kick) * 7)
        p.footR = CGPoint(x: 8 + kick * 3, y: -63 + effort * 7 + max(0, -kick) * 7)
        p.fHaunch = 0
        p.tailAngle = -1.57 + kick * 0.4; p.tailCurl = 0.4; p.tailLen = 0.95
        p.tailSway = 0.3; p.tailSwaySpeed = 6
        p.eyes = .struggle
        p.mouthOpen = 0.35
        p.earPerk = 0.55
        p.blush = 0.9
        p.shadow = 0
        return p
    }

    /// Peeking over an edge from behind (origin = the edge).
    static func peek(rise: CGFloat) -> Pose {
        var p = Pose()
        p.view = .front
        p.headTurn = 0
        p.grip = rise
        let sink = (1 - rise) * 30
        p.fHead = CGPoint(x: 0, y: 14.5 - sink)
        p.pawsFront = true
        p.fBody = CGPoint(x: 0, y: -18 - sink)
        p.fBodyW = 30; p.fBodyH = 32
        p.shoulderY = 12
        p.pawL = CGPoint(x: -9.5, y: 0.5 - sink * 1.2); p.pawR = CGPoint(x: 9.5, y: 0.5 - sink * 1.2)
        p.footL = CGPoint(x: -9, y: -52 - sink); p.footR = CGPoint(x: 9, y: -52 - sink)
        p.fHaunch = 0
        p.tailAngle = -1.4; p.tailCurl = 0.3
        p.shadow = 0
        return p
    }

    /// Climbing up a vertical surface, facing the viewer (origin = between the front paws).
    static func climb(phase: CGFloat) -> Pose {
        var p = Pose()
        p.view = .front
        p.headTurn = 0
        p.grip = 0
        let a = sin(phase), b = sin(phase + .pi)
        p.fHead = CGPoint(x: 0, y: -12)
        p.fBody = CGPoint(x: 0, y: -38)
        p.fBodyW = 28; p.fBodyH = 32
        p.shoulderY = 12
        p.pawL = CGPoint(x: -11, y: 2 + a * 5); p.pawR = CGPoint(x: 11, y: 2 + b * 5)
        p.footL = CGPoint(x: -11, y: -55 + b * 5); p.footR = CGPoint(x: 11, y: -55 + a * 5)
        p.fHaunch = 0
        p.tailAngle = -1.6; p.tailCurl = 0.5; p.tailSway = 0.25; p.tailSwaySpeed = 4
        p.earPerk = 0.8
        p.shadow = 0
        return p
    }

    /// Held by the scruff (origin = the scruff). Limp, content noodle.
    static func held(kick: CGFloat) -> Pose {
        var p = Pose()
        p.view = .front
        p.headTurn = 0
        p.fHead = CGPoint(x: 0, y: -13)
        p.fBody = CGPoint(x: 0, y: -42)
        p.fBodyW = 27; p.fBodyH = 36
        p.shoulderY = 12
        p.pawL = CGPoint(x: -7, y: -45); p.pawR = CGPoint(x: 7, y: -45)
        p.footL = CGPoint(x: -8 + kick * 2, y: -66 + max(0, kick) * 4)
        p.footR = CGPoint(x: 8 + kick * 2, y: -66 + max(0, -kick) * 4)
        p.fHaunch = 0
        p.tailAngle = -1.57; p.tailCurl = 0.25; p.tailLen = 1.05
        p.tailSway = 0.2; p.tailSwaySpeed = 2
        p.eyes = .sleep
        p.earPerk = 0.7
        p.blush = 0.85
        p.shadow = 0
        return p
    }

    /// Falling, front view, all four legs out (origin = feet).
    static func fall() -> Pose {
        var p = Pose()
        p.view = .front
        p.headTurn = 0
        p.fBody = CGPoint(x: 0, y: 20)
        p.fBodyW = 30; p.fBodyH = 30
        p.fHead = CGPoint(x: 0, y: 44)
        p.shoulderY = 8
        p.pawL = CGPoint(x: -24, y: 30); p.pawR = CGPoint(x: 24, y: 30)
        p.footL = CGPoint(x: -18, y: 4); p.footR = CGPoint(x: 18, y: 4)
        p.fHaunch = 0
        p.tailAngle = 1.4; p.tailCurl = -0.6; p.tailSway = 0.4; p.tailSwaySpeed = 9
        p.eyes = .wide
        p.mouthOpen = 0.6
        p.earPerk = 0.3
        p.shadow = 0
        return p
    }
}

// MARK: - Moods, food, toys and friends

extension Pose {
    /// Layer grumpiness on top of any pose.
    func grumpy(_ k: CGFloat) -> Pose {
        guard k > 0.01 else { return self }
        var p = self
        p.brow = max(p.brow, k)
        if p.mouthOpen < 0.2 { p.frown = max(p.frown, k) }
        p.earPerk = min(p.earPerk, 1 - 0.65 * k)
        p.blush *= 1 - 0.6 * k
        if p.eyes == .open { p.eyeOpen = min(p.eyeOpen, 1 - 0.35 * k) }
        p.tailSway = max(p.tailSway, 0.25 * k)
        p.tailSwaySpeed = max(p.tailSwaySpeed, 6 * k)
        return p
    }

    /// Head down in the bowl. `chew` 0...1 cycles.
    static func eat(chew: CGFloat, drinking: Bool) -> Pose {
        var p = Pose()
        p.body = CGPoint(x: -4, y: 15)
        p.bodyW = 44; p.bodyH = 24
        p.bodyAngle = -0.2
        p.head = CGPoint(x: 23, y: drinking ? 10 : 12 + chew * 1.5)
        p.headTilt = -0.38
        p.footFN = CGPoint(x: 11, y: 0); p.footFF = CGPoint(x: 14, y: 0)
        p.footBN = CGPoint(x: -16, y: 0); p.footBF = CGPoint(x: -13, y: 0)
        p.eyes = drinking ? .sleep : .happy
        p.mouthOpen = drinking ? 0 : 0.14 + chew * 0.2
        p.tongue = drinking ? chew : 0
        p.tailAngle = 1.8; p.tailCurl = -0.9; p.tailSway = 0.14; p.tailSwaySpeed = 3
        p.headTurn = 0.8
        p.blush = 0.8
        return p
    }

    /// Back arched, fur up, hissing.
    static func hiss() -> Pose {
        var p = Pose()
        p.body = CGPoint(x: -2, y: 22)
        p.bodyW = 42; p.bodyH = 29
        p.head = CGPoint(x: 23, y: 33)
        p.footFN = CGPoint(x: 13, y: 0); p.footFF = CGPoint(x: 16, y: 0)
        p.footBN = CGPoint(x: -15, y: 0); p.footBF = CGPoint(x: -12, y: 0)
        p.eyes = .open; p.eyeOpen = 0.75
        p.brow = 1; p.mouthOpen = 0.85; p.earPerk = 0; p.puff = 1
        p.tailAngle = 1.62; p.tailCurl = 0.05; p.tailSway = 0.04; p.tailSwaySpeed = 4
        p.headTurn = 0.45
        p.blush = 0.1
        return p
    }

    /// Sitting with its back to you, tail thumping. Very offended.
    static func sulk() -> Pose {
        var p = Pose.sitFront()
        p.back = true
        p.eyes = .none
        p.earPerk = 0.55
        p.tailFront = true
        p.tailAngle = -0.15; p.tailCurl = 1.2; p.tailLen = 1.05
        p.tailSway = 0.35; p.tailSwaySpeed = 5
        return p
    }

    /// Lying on its side hugging a toy and bunny-kicking it. The toy sits at `Pose.toyHug`.
    static func bunnyKick(_ phase: CGFloat) -> Pose {
        var p = Pose()
        p.body = CGPoint(x: -2, y: 13)
        p.bodyW = 44; p.bodyH = 24
        p.bodyAngle = 0.3
        p.head = CGPoint(x: 19, y: 25)
        p.headTilt = -0.45
        p.footFN = CGPoint(x: 17, y: 12); p.footFF = CGPoint(x: 21, y: 10)
        p.footBN = CGPoint(x: -2 + 9 * sin(phase), y: 5 + 4 * cos(phase))
        p.footBF = CGPoint(x: 1 + 9 * sin(phase + .pi), y: 6 + 4 * cos(phase + .pi))
        p.eyes = .open; p.eyeOpen = 1.15
        p.mouthOpen = 0.3
        p.tailAngle = 2.9; p.tailCurl = -0.5; p.tailSway = 0.4; p.tailSwaySpeed = 9
        p.earPerk = 0.7
        p.headTurn = 0.9
        return p
    }
    static let toyHug = CGPoint(x: 26, y: 12)

    /// Sitting and swiping at something on the ground in front. `swipe` 0...1.
    static func bat(_ swipe: CGFloat) -> Pose {
        var p = Pose.sit()
        p.footFN = CGPoint(x: 9 + 18 * swipe, y: 4 + 11 * sin(.pi * swipe))
        p.head = CGPoint(x: 9, y: 42)
        p.headTilt = -0.25
        p.lookX = 1; p.lookY = -0.8
        p.eyeOpen = 1.12
        p.headTurn = 0.9
        p.tailSway = 0.3; p.tailSwaySpeed = 7
        return p
    }
    static let toyBat = CGPoint(x: 34, y: 0)

    /// Leaning in to touch noses.
    static func boop(_ lean: CGFloat) -> Pose {
        var p = Pose.stand()
        p.head = CGPoint(x: 23 + 5 * lean, y: 32 - 3 * lean)
        p.headTilt = -0.12 * lean
        p.eyes = lean > 0.8 ? .sleep : .open
        p.blush = 0.6 + 0.6 * lean
        p.tailAngle = 1.7; p.tailCurl = -1; p.tailSway = 0.2
        p.headTurn = 1
        return p
    }

    /// Licking a friend's head. `lick` cycles 0...1.
    static func lickFriend(_ lick: CGFloat) -> Pose {
        var p = Pose.sit()
        p.head = CGPoint(x: 13, y: 47 + lick * 2)
        p.headTilt = -0.35 + lick * 0.12
        p.eyes = .sleep
        p.tongue = 0.4 + 0.6 * lick
        p.mouthOpen = 0.12
        p.headTurn = 1
        p.blush = 0.8
        return p
    }

    /// Wide-eyed alarm (a friend just pounced).
    static func startled() -> Pose {
        var p = Pose.stand()
        p.body.y = 20
        p.head = CGPoint(x: 23, y: 37)
        p.eyes = .wide; p.earPerk = 0.2; p.puff = 0.6
        p.tailAngle = 1.6; p.tailCurl = 0
        return p
    }
}
