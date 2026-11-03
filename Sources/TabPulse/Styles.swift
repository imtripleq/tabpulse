import AppKit

/// The spinner in front of a working tab's title, also used beside working sessions in the menu.
enum TabStyle: String, CaseIterable {
    case braille, bounce, arc, equalizer, sparkle, sine, typing, snake
    case moon, garden, heartbeat, magic, monkeys, duck, hatch, slots

    var name: String {
        switch self {
        case .braille: "Braille"
        case .bounce: "Bounce"
        case .arc: "Arc"
        case .equalizer: "Equalizer"
        case .sparkle: "Sparkle"
        case .sine: "Sine"
        case .typing: "Typing"
        case .snake: "Snake"
        case .moon: "Moon"
        case .garden: "Garden"
        case .heartbeat: "Heartbeat"
        case .magic: "Magic"
        case .monkeys: "Monkeys"
        case .duck: "Duck"
        case .hatch: "Hatch"
        case .slots: "Slots"
        }
    }

    /// Heading the style sits under in the Style menu.
    var section: String {
        switch self {
        case .braille, .bounce, .arc, .equalizer, .sparkle, .sine, .typing, .snake: "Glyph"
        case .moon, .garden, .heartbeat, .magic, .monkeys, .duck, .hatch, .slots: "Emoji"
        }
    }

    /// One frame per 0.12 s tick. Garden doesn't cycle: it grows with how long the turn has run.
    private var frames: [String] {
        switch self {
        case .braille: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        case .bounce: ["⠁", "⠂", "⠄", "⡀", "⢀", "⠠", "⠐", "⠈"]
        case .arc: ["◜", "◠", "◝", "◞", "◡", "◟"]
        case .equalizer: ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", "▇", "▆", "▅", "▄", "▃", "▂"]
        case .sparkle: Self.sparkleFrames
        case .sine: ["⠊⠑⢄", "⠉⠢⣀", "⠑⢄⡠", "⠢⣀⠔", "⢄⡠⠊", "⣀⠔⠉", "⡠⠊⠑", "⠔⠉⠢"]
        case .typing: ["⡀⡀⡀", "⠄⡀⡀", "⠂⡀⡀", "⠄⠄⡀", "⡀⠂⡀", "⡀⠄⠄", "⡀⡀⠂", "⡀⡀⠄", "⡀⡀⡀"]
        case .snake: ["▘", "▀", "▜", "▟", "▙", "▛", "▐", "▖"]
        case .moon: ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]
        case .garden: Self.gardenStages.map(\.glyph)
        case .heartbeat: ["💜", "💜", "💜", "💖", "💜", "💖", "💜", "💜"]
        case .magic: ["🎩", "🎩", "🪄", "🪄", "💫", "🐰", "🐰", "🐰", "🐰", "💫"]
        case .monkeys: ["🙊", "🙊", "🙊", "🙈", "🙈", "🙈", "🙉", "🙉", "🙉"]
        case .duck: ["💡", "💡", "🦆", "🦆", "🦆", "🦆", "🦆", "💬", "💬", "🦆", "🦆", "💡"]
        case .hatch: ["🥚", "🥚", "🥚", "🐣", "🐥", "🐥", "🐤", "🐤", "🐥", "🐣"]
        // The reel slows down onto the jackpot instead of strobing six symbols at full speed.
        case .slots: ["🍒", "🔔", "🍋", "🍋", "🍉", "🍉", "🍉", "💎", "💎", "💎", "💎", "💎"]
        }
    }

    static let sparkleFrames = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]
    private static let gardenStages: [(after: TimeInterval, glyph: String)] = [(0, "🌱"), (60, "🌿"), (180, "🌷"), (600, "🌻")]

    func glyph(tick: Int, elapsed: TimeInterval) -> String {
        if self == .garden { return Self.gardenStages.last { elapsed >= $0.after }?.glyph ?? "🌱" }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return sample }
        return frames[tick % frames.count]
    }

    /// A glyph that stands for the style in the Style menu, and the one a tab holds under Reduce Motion.
    /// It must be one of the style's frames so TabSync can strip it, and never ✳, Claude's idle mark.
    var sample: String {
        switch self {
        case .braille: "⠹"
        case .bounce: "⠂"
        case .arc: "◠"
        case .equalizer: "▅"
        case .sparkle: "✽"
        case .sine: "⢄⡠⠊"
        case .typing: "⡀⠂⡀"
        case .snake: "▙"
        case .moon: "🌓"
        case .garden: "🌻"
        case .heartbeat: "💜"
        case .magic: "🐰"
        case .monkeys: "🙈"
        case .duck: "🦆"
        case .hatch: "🐥"
        case .slots: "💎"
        }
    }

    /// Every mark any style can put in front of a title, whole, so TabSync strips exactly one and no more.
    static let allFrames: Set<String> = Set(allCases.flatMap { $0.frames })
}

/// How the ✳ in the menu bar pill moves while sessions are working.
/// Declared in Style menu order: each section's styles together.
enum BarStyle: String, CaseIterable {
    case spin, breathe, hop, bloom, neon, rainbow, morph, sketch
    case orbit, comet, radar, wave, helix, equalizer, pulse, scanner
    case chomp, mochi, kitty, brainstorm, rocket, cradle, prompt, cube

    var name: String {
        switch self {
        case .spin: "Spin"
        case .breathe: "Breathe"
        case .hop: "Hop"
        case .bloom: "Bloom"
        case .neon: "Neon"
        case .rainbow: "Rainbow"
        case .morph: "Morph"
        case .sketch: "Sketch"
        case .orbit: "Orbit"
        case .comet: "Comet"
        case .radar: "Radar"
        case .wave: "Wave"
        case .helix: "Helix"
        case .equalizer: "Equalizer"
        case .pulse: "Pulse"
        case .scanner: "Scanner"
        case .chomp: "Chomp"
        case .mochi: "Mochi"
        case .kitty: "Kitty"
        case .brainstorm: "Brainstorm"
        case .rocket: "Rocket"
        case .cradle: "Cradle"
        case .prompt: "Prompt"
        case .cube: "Cube"
        }
    }

    /// Heading the style sits under in the Style menu and the gallery.
    var section: String {
        switch self {
        case .spin, .breathe, .hop, .bloom, .neon, .rainbow, .morph, .sketch: "Star"
        case .orbit, .comet, .radar, .wave, .helix, .equalizer, .pulse, .scanner: "Signal"
        case .chomp, .mochi, .kitty, .brainstorm, .rocket, .cradle, .prompt, .cube: "Playful"
        }
    }

    /// Needs a wider spot in the menu bar than the star.
    var isWide: Bool { [.pulse, .scanner, .chomp, .cradle, .prompt].contains(self) }
}

/// Choices from the Style menu, kept in the app's defaults. `defaults write dev.tabpulse.TabPulse tabStyle moon` works too.
enum Prefs {
    private static let store = UserDefaults.standard

    static var tabStyle = TabStyle(rawValue: store.string(forKey: "tabStyle") ?? "") ?? .braille {
        didSet { store.set(tabStyle.rawValue, forKey: "tabStyle") }
    }
    static var barStyle = BarStyle(rawValue: store.string(forKey: "barStyle") ?? "") ?? .spin {
        didSet { store.set(barStyle.rawValue, forKey: "barStyle") }
    }
    /// The menu bar animation runs faster the more sessions are working.
    static var speedsUp = store.object(forKey: "speedsUp") as? Bool ?? true {
        didSet { store.set(speedsUp, forKey: "speedsUp") }
    }
}
