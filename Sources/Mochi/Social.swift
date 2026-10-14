import Foundation

enum SocialKind { case boop, groom, wrestle, tag }

extension Cat {
    /// Free to be approached by a friend.
    var isSociable: Bool {
        guard overlay == nil, !paused, !dragging, grumpy < 0.6, let a = action, currentSurface != nil,
              surface != .box, surface != .bowls else { return false }
        return a is Idle || a is Walk || a is Groom || a is Stretch
    }

    /// Maybe go and hang out with another cat on the same ledge. Returns true if a plan was made.
    func planSocial() -> Bool {
        guard time - lastSocial > (Cat.testMode ? 6 : 18), let s = currentSurface, !isHidden else { return false }
        let friends = Den.shared.others(than: self).filter { f in
            f.isSociable && f.surface == s.ref && abs(f.pos.x - pos.x) < 700 && !f.isHidden
        }
        guard let f = friends.randomElement() else { return false }
        lastSocial = time
        f.lastSocial = f.time
        let lively = energy > 0.45 && f.energy > 0.45
        let kind = pick([
            (SocialKind.boop, 3.0),
            (.groom, 2.0),
            (.wrestle, lively && s.width > 220 ? 1.6 : 0.2),
            (.tag, lively && s.width > 420 ? 1.6 : 0),
        ]) ?? .boop
        queue = depth != f.depth ? [SetDepth(f.depth)] : []
        queue.append(Approach(f, kind: kind))
        return true
    }
}

/// Walk over to a friend, then start the interaction (the friend joins in).
final class Approach: Act {
    let friend: Cat
    let kind: SocialKind
    init(_ friend: Cat, kind: SocialKind) {
        self.friend = friend
        self.kind = kind
    }
    override var status: String { "Going to see \(friend.name)" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 14
        c.lookAtCursor = false
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        guard t < 12, friend.isSociable || friend.action is Approach, friend.surface == c.surface,
              let s = c.currentSurface else { return false }
        let side: CGFloat = c.pos.x < friend.pos.x ? -1 : 1
        let gap: CGFloat
        switch kind {
        case .boop: gap = 54
        case .groom: gap = 30
        case .wrestle: gap = 80
        case .tag: gap = 150
        }
        let goal = s.clamp(friend.pos.x + side * gap * c.scale)
        let speed: CGFloat = kind == .boop || kind == .groom ? 60 : 85
        if !c.trot(to: goal, speed: speed, dt) {
            c.look(at: friend.headWorld)
            return true
        }
        c.facing = -side
        if friend.grumpy > 0.5 {
            // A grumpy friend wants none of it.
            friend.interrupt(with: [Hiss(at: c.headWorld), Sulk(5)])
            c.queue.insert(contentsOf: [Idle(.stand, 0.6), Walk(to: s.clamp(c.pos.x + side * 160 * c.scale), speed: 160)], at: 0)
            c.spawn(.sweat, dx: 14, dy: 12, v: CGPoint(x: 8, y: 10), life: 0.9)
            return false
        }
        switch kind {
        case .boop:
            friend.interrupt(with: [Boop(c, leader: false)])
            c.queue.insert(Boop(friend, leader: true), at: 0)
        case .groom:
            friend.interrupt(with: [BeGroomed(c)])
            c.queue.insert(GroomFriend(friend), at: 0)
        case .wrestle:
            friend.interrupt(with: [BeWrestled(c)])
            c.queue.insert(PounceFriend(friend), at: 0)
        case .tag:
            friend.interrupt(with: [Flee(from: c)])
            c.queue.insert(ChaseFriend(friend), at: 0)
        }
        return false
    }
}

// MARK: - Nose boop

final class Boop: Act {
    let friend: Cat
    let leader: Bool
    private var booped = false
    init(_ friend: Cat, leader: Bool) {
        self.friend = friend
        self.leader = leader
    }
    override var status: String { "Nose boop with \(friend.name) ♥" }
    override var grounded: Bool { true }
    override var showsMood: Bool { false }

    override func begin(_ c: Cat) {
        if abs(friend.pos.x - c.pos.x) > 2 { c.facing = friend.pos.x > c.pos.x ? 1 : -1 }
        c.blendRate = 8
        c.lookAtCursor = false
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        guard t < 0.3 || friend.action is Boop || booped else { return false }
        let lean = ease(t / 0.6) * (1 - ease((t - 1.7) / 0.4))
        c.target = .boop(lean)
        if leader && !booped && t > 0.65 {
            booped = true
            c.effects.hearts(at: CGPoint(x: c.facing * 34, y: 36), count: 2)
        }
        if t > 2.2 {
            if leader && chance(0.45) && friend.action is Boop {
                friend.interrupt(with: [BeGroomed(c)])
                c.queue.insert(GroomFriend(friend), at: 0)
            } else {
                c.queue.insert(Idle(leader ? .sit : .loaf, .random(in: 2...4)), at: 0)
            }
            return false
        }
        return true
    }
}

// MARK: - Grooming each other

final class GroomFriend: Act {
    let friend: Cat
    private let duration = CGFloat.random(in: 3.5...5.5)
    private var heartClock: CGFloat = 1
    init(_ friend: Cat) { self.friend = friend }
    override var status: String { "Grooming \(friend.name)" }
    override var grounded: Bool { true }
    override var showsMood: Bool { false }

    override func begin(_ c: Cat) {
        c.blendRate = 9
        c.lookAtCursor = false
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        guard t < 0.4 || friend.action is BeGroomed else { return false }
        if abs(friend.pos.x - c.pos.x) > 2 { c.facing = friend.pos.x > c.pos.x ? 1 : -1 }
        // Scoot in close enough to reach the top of the friend's head.
        let want = friend.pos.x - c.facing * 30 * c.scale
        c.pos.x += (want - c.pos.x) * min(1, dt * 4)
        c.target = .lickFriend((sin(t * 9) + 1) / 2)
        heartClock -= dt
        if heartClock <= 0 {
            heartClock = .random(in: 1.1...1.8)
            friend.effects.hearts(at: CGPoint(x: friend.headLocal.x, y: friend.headLocal.y + 16), count: 1)
        }
        return t < duration
    }
}

final class BeGroomed: Act {
    let friend: Cat
    init(_ friend: Cat) { self.friend = friend }
    override var status: String { "Being groomed by \(friend.name) ♥" }
    override var grounded: Bool { true }
    override var showsMood: Bool { false }

    override func begin(_ c: Cat) {
        if abs(friend.pos.x - c.pos.x) > 2 { c.facing = friend.pos.x > c.pos.x ? 1 : -1 }
        c.blendRate = 8
        c.lookAtCursor = false
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        guard t < 1 || friend.action is GroomFriend || friend.action is Boop else {
            c.queue.insert(Idle(.loaf, .random(in: 2...4)), at: 0)
            return false
        }
        c.target = .sit()
        c.target.eyes = .happy
        c.target.headTilt = 0.22
        c.target.purr = 1
        c.target.blush = 1.1
        c.target.earPerk = 0.75
        return t < 9
    }
}

// MARK: - Wrestling (a cartoon scuffle cloud)

final class PounceFriend: Act {
    let friend: Cat
    private var stage = 0
    private var stageT: CGFloat = 0
    private var p0 = CGPoint.zero
    private var mid: CGFloat = 0
    private let fightFor = CGFloat.random(in: 1.8...2.8)
    private var dustClock: CGFloat = 0
    init(_ friend: Cat) { self.friend = friend }
    override var status: String { "Wrestling with \(friend.name)!" }
    override var grounded: Bool { stage != 1 }
    override func onPet(_ c: Cat) -> Bool { false }

    override func begin(_ c: Cat) {
        c.blendRate = 16
        c.lookAtCursor = false
        if abs(friend.pos.x - c.pos.x) > 2 { c.facing = friend.pos.x > c.pos.x ? 1 : -1 }
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        stageT += dt
        guard friend.action is BeWrestled else { return false }
        switch stage {
        case 0: // wiggle
            c.target = .crouch(wiggle: stageT > 0.2 ? sin(stageT * 18) : 0)
            c.look(at: friend.headWorld)
            if stageT > 0.6 { stage = 1; stageT = 0; p0 = c.pos }
        case 1: // leap onto them
            let k = min(1, stageT / 0.32)
            let goal = friend.pos.x - c.facing * 16 * c.scale
            c.pos.x = p0.x + (goal - p0.x) * k
            c.pos.y = p0.y - sin(.pi * k) * 26 * c.scale
            c.target = .leap(t: k)
            if k >= 1 {
                c.pos.y = p0.y
                stage = 2; stageT = 0
                mid = (c.pos.x + friend.pos.x) / 2
                c.pos.x = mid
                c.overlay = .fight(friend.coat)
                friend.overlay = .hidden
            }
        case 2: // scuffle!
            c.pos.x = mid + sin(stageT * 23) * 3
            dustClock -= dt
            if dustClock <= 0 {
                dustClock = 0.25
                c.effects.dust(at: CGPoint(x: .random(in: -20...20), y: 0), strength: 0.8)
            }
            if stageT > fightFor { finish(c) ; return false }
        default: break
        }
        return true
    }

    private func finish(_ c: Cat) {
        c.overlay = nil
        friend.overlay = nil
        let s = c.currentSurface
        let left = s.map { $0.clamp(mid - 38 * c.scale) } ?? mid - 38 * c.scale
        let right = s.map { $0.clamp(mid + 38 * c.scale) } ?? mid + 38 * c.scale
        // Pop out on opposite sides, facing away, as if nothing happened.
        let leaderLeft = Bool.random()
        c.pos.x = leaderLeft ? left : right
        friend.pos.x = leaderLeft ? right : left
        c.facing = leaderLeft ? -1 : 1
        friend.facing = -c.facing
        c.target = .stand(); c.snapTurn()
        friend.target = .stand(); friend.snapTurn()
        c.spawn(.sweat, dx: 12, dy: 12, v: CGPoint(x: 6, y: 10), life: 0.8)
        friend.interrupt(with: [Land(0.4), Idle(.sit, 0.5), Groom(.random(in: 2.5...4))])
        c.queue.insert(contentsOf: [Land(0.4), Idle(.sit, 0.5), Groom(.random(in: 2.5...4))], at: 0)
    }

    override func end(_ c: Cat) {
        c.overlay = nil
        if case .hidden? = friend.overlay { friend.overlay = nil }
    }
}

final class BeWrestled: Act {
    let friend: Cat
    init(_ friend: Cat) { self.friend = friend }
    override var status: String { "Wrestling with \(friend.name)!" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        if abs(friend.pos.x - c.pos.x) > 2 { c.facing = friend.pos.x > c.pos.x ? 1 : -1 }
        c.blendRate = 18
        c.lookAtCursor = false
        c.spawn(.exclaim, dx: 12, dy: 18, v: CGPoint(x: 0, y: 20), life: 0.6)
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        c.target = .startled()
        return t < 6 && friend.action is PounceFriend
    }

    override func end(_ c: Cat) { c.overlay = nil }
}

// MARK: - Chasing each other

final class Flee: Act {
    let from: Cat
    private var goal: CGFloat = 0
    init(from: Cat) { self.from = from }
    override var status: String { "Running from \(from.name)!" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 16
        c.lookAtCursor = false
        c.spawn(.exclaim, dx: 12, dy: 18, v: CGPoint(x: 0, y: 20), life: 0.6)
        if let s = c.currentSurface {
            let away: CGFloat = c.pos.x > from.pos.x ? 1 : -1
            goal = s.clamp(c.pos.x + away * .random(in: 300...600) * c.scale)
            if abs(goal - c.pos.x) < 120 { goal = s.clamp(c.pos.x - away * 400 * c.scale) }
        }
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        if t < 0.35 {
            c.target = .startled()
            return true
        }
        if c.trot(to: goal, speed: 290, dt) {
            c.facing = from.pos.x > c.pos.x ? 1 : -1
            c.queue.insert(Idle(.sit, .random(in: 1.5...3)), at: 0)
            return false
        }
        c.target.earPerk = 0.2
        c.target.eyeOpen = 1.15
        c.target.tailAngle = 2.6
        return t < 8 && from.action is ChaseFriend
    }
}

final class ChaseFriend: Act {
    let friend: Cat
    init(_ friend: Cat) { self.friend = friend }
    override var status: String { "Chasing \(friend.name)!" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 16
        c.lookAtCursor = false
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        if t < 0.5 {
            c.target = .crouch(wiggle: sin(t * 18))
            c.look(at: friend.headWorld)
            return true
        }
        let fleeing = friend.action is Flee
        guard t < 9, fleeing || friend.action is Idle, friend.surface == c.surface else { return false }
        let dir: CGFloat = friend.pos.x > c.pos.x ? 1 : -1
        let arrived = c.trot(to: friend.pos.x - dir * 44 * c.scale, speed: fleeing ? 270 : 200, dt)
        c.target.earPerk = 0.35
        if arrived && !fleeing {
            // Caught up: tackle, or make up with a boop.
            if chance(0.6) {
                friend.interrupt(with: [BeWrestled(c)])
                c.queue.insert(PounceFriend(friend), at: 0)
            } else {
                friend.interrupt(with: [Boop(c, leader: false)])
                c.queue.insert(Boop(friend, leader: true), at: 0)
            }
            return false
        }
        return true
    }
}
