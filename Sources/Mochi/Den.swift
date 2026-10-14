import Foundation

/// The household: every cat plus their box, bowls and toy.
final class Den {
    static let shared = Den()
    var cats: [Cat] = []
    var home: HomeBox!
    var bowls: Bowls!
    var toy: Toy!

    /// Speeds up hunger, thirst and grumpiness while testing.
    static let needsSpeed: CGFloat = ProcessInfo.processInfo.environment["MOCHI_FAST_NEEDS"] != nil ? 25 : 1

    func others(than c: Cat) -> [Cat] { cats.filter { $0 !== c && !$0.paused } }
}
