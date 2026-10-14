import Foundation

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// A cat's colouring. Optional layers are simply skipped when nil.
struct Coat {
    let id: String
    let name: String
    let base: CGColor
    let shade: CGColor        // far-side legs, inner shadows
    let outline: CGColor
    var belly: CGColor? = nil
    var stripes: CGColor? = nil
    var points: CGColor? = nil    // siamese ears / paws / tail / mask
    var patchA: CGColor? = nil    // calico patches
    var patchB: CGColor? = nil
    var muzzle: CGColor? = nil
    var socks: CGColor? = nil
    var tailTip: CGColor? = nil
    var faceLine: CGColor? = nil  // mouth / whisker colour when the outline would vanish into dark fur
    var iris: CGColor? = nil      // coloured eyes for dark coats (nil = classic black shiny eyes)
    var nose: CGColor = rgb(0xF2879A)
    var innerEar: CGColor = rgb(0xF7AFC0)
    var blush: CGColor = rgb(0xFF8FA6)

    static let all: [Coat] = [
        Coat(id: "ginger", name: "Ginger Tabby",
             base: rgb(0xF6AE5C), shade: rgb(0xE08F3E), outline: rgb(0x6E3B1A),
             belly: rgb(0xFFE7C4), stripes: rgb(0xE0853A), muzzle: rgb(0xFFF1DC),
             tailTip: rgb(0xE0853A)),
        Coat(id: "gray", name: "Blue-Gray Tabby",
             base: rgb(0xA4AEBA), shade: rgb(0x8893A0), outline: rgb(0x3D4652),
             belly: rgb(0xE9EDF1), stripes: rgb(0x7D8896), muzzle: rgb(0xF2F4F6),
             iris: rgb(0xF2C14E)),
        Coat(id: "black", name: "Midnight",
             base: rgb(0x34313B), shade: rgb(0x23212A), outline: rgb(0x121016),
             faceLine: rgb(0x9A90A6), iris: rgb(0xF4D35E), nose: rgb(0x8A6A78), innerEar: rgb(0x8C5A6E), blush: rgb(0xD16D8A)),
        Coat(id: "tuxedo", name: "Tuxedo",
             base: rgb(0x2F2D35), shade: rgb(0x201E26), outline: rgb(0x0F0E12),
             belly: rgb(0xFBFAF7), muzzle: rgb(0xFBFAF7), socks: rgb(0xFBFAF7),
             iris: rgb(0x9CD67A), innerEar: rgb(0x9C6A7C)),
        Coat(id: "white", name: "Snowball",
             base: rgb(0xFCFBF8), shade: rgb(0xE6E2DB), outline: rgb(0x6F6A72),
             iris: rgb(0x7EB8F0)),
        Coat(id: "calico", name: "Calico",
             base: rgb(0xFDF8F1), shade: rgb(0xE9E1D4), outline: rgb(0x5B4031),
             patchA: rgb(0xF0A04B), patchB: rgb(0x3B3238), tailTip: rgb(0xF0A04B)),
        Coat(id: "siamese", name: "Siamese",
             base: rgb(0xF5E9D6), shade: rgb(0xE4D3B8), outline: rgb(0x5A4636),
             points: rgb(0x6B4F3E), iris: rgb(0x6FB3F2), innerEar: rgb(0xB88A8F)),
    ]

    static func named(_ id: String) -> Coat { all.first { $0.id == id } ?? all[0] }
}
