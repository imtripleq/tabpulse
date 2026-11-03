import Cocoa

// MARK: - Menu bar pill: animated mark, working count, orange dot = needs you, green dot = finished

/// Styles draw into `fx` (or animate `star`) from build(); the bigger ones live in the Bar*.swift extensions.
/// fx space is y-up, 0...markWidth × 0...13, with the mark's centre at `mid`.
final class PillView: NSView {
    let star = CAShapeLayer()
    let fx = CALayer()          // the current style's extra layers, rebuilt whenever the style changes
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
    private(set) var working = 0
    private(set) var waiting = 0
    private(set) var finished = 0
    var style = BarStyle.spin { didSet { if style != oldValue { applied = ""; needsLayout = true } } }
    var speedsUp = true
    private var applied = ""            // style the running animation was built for
    private var appliedSpeed: CGFloat = 1
    private var speedBound = false      // the build used pinned() or capped(), so a speed change has to rebuild it
    private var previewUntil = Date.distantPast
    private var laidOut: (width: CGFloat, lit: Bool) = (13, false)
    private(set) var ink = NSColor.labelColor.cgColor       // both resolved for the current appearance in layout()
    private(set) var accent = Palette.accent.cgColor
    /// For features drawn on an accent body: ink turns white on the dark-mode lavender and disappears.
    let faceInk = Palette.rgb(0x241240).cgColor
    /// No need for ProMotion's 120 Hz on a 13 pt mark, but much under 60 and a fast Comet visibly steps.
    static let frameRate = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Drawn as a path rather than the ✳ glyph so it turns around its true centre.
        let path = CGMutablePath()
        for i in 0..<4 {
            let a = CGFloat(i) * .pi / 4, dx = 5.6 * cos(a), dy = 5.6 * sin(a)
            path.move(to: CGPoint(x: 6.5 + dx, y: 6.5 + dy))
            path.addLine(to: CGPoint(x: 6.5 - dx, y: 6.5 - dy))
        }
        star.path = path
        star.bounds = CGRect(x: 0, y: 0, width: 13, height: 13)
        star.lineWidth = 1.5
        star.lineCap = .round
        star.fillColor = nil
        star.shadowOffset = .zero
        layer?.addSublayer(star)
        layer?.addSublayer(fx)
    }
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // clicks belong to the status button

    private var previewing: Bool { Date() < previewUntil }
    private var showing: Bool { working > 0 || previewing }
    /// Pinned by the gallery (TABPULSE_STILL=1) and --render-preview, so their images don't depend on this Mac's setting.
    static var stillOverride: Bool?
    /// Read on every tick, so turning Reduce Motion on or off applies within one.
    var still: Bool { Self.stillOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Pixels per point for bitmap layers. Unlike backingScaleFactor it includes the gallery's zoom.
    var rasterScale: CGFloat { max(2, convertToBacking(NSSize(width: 1, height: 1)).width) }
    private var animating: Bool { showing && !still }
    /// 1, 2, 3 and 4+ sessions working; flat when "speed up when busy" is off.
    var speed: CGFloat { speedsUp ? [1, 1, 1.35, 1.6, 1.8][min(working, 4)] : 1 }
    /// Wide styles need a longer track than the 13 pt star, still poses included.
    var markWidth: CGFloat { showing && style.isWide ? 22 : 13 }
    /// The mark's centre in fx space.
    var mid: CGPoint { CGPoint(x: markWidth / 2, y: 6.5) }

    private var count: NSAttributedString {
        NSAttributedString(string: "\(working)", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
    }
    private var dots: [NSColor] { (waiting > 0 ? [Palette.warn] : []) + (finished > 0 ? [Palette.ok] : []) }
    private var active: Bool { working + waiting + finished > 0 }
    /// A preview looks the way a working session will, not the grey idle star.
    private var lit: Bool { active || previewing }

    var width: CGFloat {
        var w: CGFloat = 8 + markWidth + 8
        if working > 0 { w += 5 + count.size().width }
        w += CGFloat(dots.count) * (5 + 7)
        return ceil(w)
    }

    func set(working: Int, waiting: Int, finished: Int) {
        if working != self.working || waiting != self.waiting || finished != self.finished {
            self.working = working
            self.waiting = waiting
            self.finished = finished
            needsDisplay = true
            needsLayout = true
        }
        animate()
    }

    /// Runs the current style for a few seconds even with nothing working, so a new pick shows itself.
    func preview(for seconds: TimeInterval = 3) {
        previewUntil = Date().addingTimeInterval(seconds)
        needsLayout = true
        needsDisplay = true
    }

    // MARK: Animation

    /// Runs every tick: rebuilds when the style or colours change, and when Core Animation has
    /// dropped the animation, which it does after sleep or a display change.
    private func animate() {
        // set() only re-lays out on count changes; a preview starting or ending changes width and ink too.
        if markWidth != laidOut.width || lit != laidOut.lit { needsLayout = true; needsDisplay = true }
        // Under Reduce Motion a style still builds, as its still pose: play() adds no animations.
        let key = showing ? style.rawValue + (still ? "-still" : "") : "idle"
        let dropped = animating && !hasAnimation(star) && !hasAnimation(fx)
        let rebuild = key != applied || dropped || (speed != appliedSpeed && speedBound)
        guard rebuild || speed != appliedSpeed else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if rebuild {
            applied = key
            speedBound = false
            star.removeAllAnimations()
            fx.sublayers?.forEach { $0.removeFromSuperlayer() }
            star.transform = CATransform3DIdentity
            star.isHidden = false
            star.opacity = 1
            star.strokeColor = showing && still ? accent : ink
            star.shadowOpacity = 0
            if showing { build() }
        }
        if speed != appliedSpeed {
            // Animations run at base speed; retiming the layers keeps each one at the same point in its cycle.
            appliedSpeed = speed
            let now = CACurrentMediaTime()
            for l in [star, fx] {
                let local = l.convertTime(now, from: nil), parent = l.superlayer?.convertTime(now, from: nil) ?? now
                l.beginTime = parent
                l.timeOffset = local
                l.speed = Float(speed)
            }
        }
        CATransaction.commit()
    }

    private func hasAnimation(_ l: CALayer) -> Bool {
        !(l.animationKeys() ?? []).isEmpty || (l.sublayers ?? []).contains { hasAnimation($0) }
    }

    private func build() {
        switch style {
        case .spin:
            play(loop("transform.rotation.z", from: 0, to: -2 * .pi, seconds: 1.6), on: star)

        case .bloom:
            // Swapped by Core Animation rather than per tick, so layer speed paces the frames evenly.
            star.isHidden = true
            let px = rasterScale
            let images = TabStyle.sparkleFrames.map { sprite($0, size: 18, scale: px, color: still ? accent : ink) as Any }
            let flower = CALayer()
            flower.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
            flower.position = mid
            flower.contentsScale = px
            flower.contents = images[images.count / 2]
            fx.addSublayer(flower)
            let a = keyframes("contents", images, times: (0...images.count).map { CGFloat($0) / CGFloat(images.count) })
            a.calculationMode = .discrete
            a.duration = 0.12 * Double(images.count)
            a.repeatCount = .infinity
            a.isRemovedOnCompletion = false
            a.preferredFrameRateRange = Self.frameRate
            play(a, on: flower)

        case .breathe:
            let grow = loop("transform.scale", from: 0.7, to: 1.06, seconds: 0.9), fade = loop("opacity", from: 0.55, to: 1, seconds: 0.9)
            for a in [grow, fade] { a.autoreverses = true; a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut) }
            play(grow, on: star)
            play(fade, on: star, key: "b")

        case .hop:
            play(hop(), on: star)

        case .orbit:
            star.transform = CATransform3DMakeScale(0.62, 0.62, 1)
            let wheel = holder(at: mid)
            wheel.addSublayer(dot(at: CGPoint(x: 6.5, y: 12.4), radius: 1.6, color: ink))
            play(loop("transform.rotation.z", from: 0, to: -2 * .pi, seconds: 1.4), on: wheel)

        case .wave:
            star.isHidden = true
            for i in 0..<3 {
                let d = dot(at: CGPoint(x: mid.x + CGFloat(i - 1) * 4.5, y: mid.y), radius: 1.75, color: ink)
                fx.addSublayer(d)
                play(group([keyframes("transform.translation.y", [-2, 3, -2]), keyframes("opacity", [0.5, 1, 0.5])],
                           seconds: 0.9, phase: CGFloat(i) * -0.17, smooth: true), on: d)
            }

        case .radar:
            // A small star sends out sonar rings that grow and fade.
            star.transform = CATransform3DMakeScale(0.5, 0.5, 1)
            for i in 0..<2 {
                let ring = CAShapeLayer()
                ring.bounds = CGRect(x: 0, y: 0, width: 13, height: 13)
                ring.position = mid
                ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 0.7, dy: 0.7), transform: nil)
                ring.fillColor = nil
                ring.strokeColor = ink
                ring.lineWidth = 1.2
                ring.opacity = 0
                fx.addSublayer(ring)
                let g = group([keyframes("transform.scale", [0.3, 1.15]), keyframes("opacity", [0.95, 0])],
                              seconds: 1.6, phase: CGFloat(i) * 0.5, smooth: false)
                g.timingFunction = CAMediaTimingFunction(name: .easeOut)
                play(g, on: ring)
            }

        case .comet:
            // A bright head with a fading tail of smaller dots, going round.
            star.isHidden = true
            let wheel = holder(at: mid)
            for k in 0..<8 {
                let a = CGFloat.pi / 2 + CGFloat(k) * 0.36
                let d = dot(at: CGPoint(x: 6.5 + 5 * cos(a), y: 6.5 + 5 * sin(a)), radius: 1.6 - CGFloat(k) * 0.13, color: ink)
                d.opacity = Float(1 - CGFloat(k) / 8.5)
                wheel.addSublayer(d)
            }
            play(loop("transform.rotation.z", from: 0, to: -2 * .pi, seconds: 0.9), on: wheel)

        case .equalizer:
            star.isHidden = true
            let levels: [[CGFloat]] = [[0.3, 1, 0.5, 0.8, 0.3], [0.75, 0.35, 1, 0.45, 0.75], [0.5, 0.9, 0.3, 1, 0.5], [0.9, 0.4, 0.7, 0.3, 0.9]]
            let seconds: [CGFloat] = [0.9, 0.75, 1.05, 0.85]
            for i in 0..<4 {
                let bar = CAShapeLayer()
                bar.bounds = CGRect(x: 0, y: 0, width: 2.2, height: 10)
                bar.anchorPoint = CGPoint(x: 0.5, y: 0)
                bar.position = CGPoint(x: mid.x - 4.8 + CGFloat(i) * 3.2, y: 1.5)
                bar.path = CGPath(roundedRect: bar.bounds, cornerWidth: 1.1, cornerHeight: 1.1, transform: nil)
                bar.fillColor = ink
                bar.transform = CATransform3DMakeScale(1, levels[i][1], 1)   // the still pose: uneven, not a solid block
                fx.addSublayer(bar)
                play(group([keyframes("transform.scale.y", levels[i])], seconds: seconds[i], phase: 0, smooth: true), on: bar)
            }

        case .pulse:
            // A heart-monitor trace: a bright stretch runs along a faint copy of the line.
            star.isHidden = true
            let path = CGMutablePath()
            let pts: [(CGFloat, CGFloat)] = [(0, 6.5), (5, 6.5), (6.5, 8.3), (8, 6.5), (9.5, 6.5), (11, 12.2), (12.8, 0.8),
                                             (14.4, 8.6), (15.6, 6.5), (22, 6.5)]
            path.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
            for faint in [true, false] {
                let line = CAShapeLayer()
                line.frame = CGRect(x: 0, y: 0, width: 22, height: 13)
                line.path = path
                line.fillColor = nil
                line.strokeColor = ink
                line.lineWidth = 1.4
                line.lineJoin = .round
                line.lineCap = .round
                line.opacity = faint ? 0.22 : 1
                fx.addSublayer(line)
                if !faint {
                    let run = group([keyframes("strokeEnd", [0, 1, 1], times: [0, 0.6, 1]),
                                     keyframes("strokeStart", [0, 0, 1], times: [0, 0.3, 1])], seconds: 1.4, phase: 0, smooth: false)
                    play(run, on: line)
                }
            }

        case .neon:
            // An accent-coloured star that glows in and out, with the odd flicker of a neon tube.
            star.strokeColor = accent
            star.shadowColor = accent
            star.shadowPath = star.path?.copy(strokingWithWidth: 1.5, lineCap: .round, lineJoin: .round, miterLimit: 1)
            let glow = group([keyframes("shadowOpacity", [0.25, 1, 0.25]), keyframes("shadowRadius", [0.8, 3.5, 0.8])],
                             seconds: 1.4, phase: 0, smooth: true)
            play(glow, on: star)
            play(group([keyframes("opacity", [1, 1, 0.35, 1, 0.6, 1, 1], times: [0, 0.7, 0.72, 0.75, 0.77, 0.8, 1])],
                       seconds: 3.1, phase: 0, smooth: false), on: star, key: "b")

        case .rainbow:
            // Pastels vanish on a light bar, so light mode gets deeper, darker hues.
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (sat, bri): (CGFloat, CGFloat) = dark ? (0.65, 0.95) : (0.9, 0.55)
            let hues = stride(from: 0.0, through: 1.0, by: 1.0 / 7).map {
                NSColor(hue: CGFloat($0.truncatingRemainder(dividingBy: 1)), saturation: sat, brightness: bri, alpha: 1).cgColor
            }
            play(loop("transform.rotation.z", from: 0, to: -2 * .pi, seconds: 3.2), on: star)
            play(group([keyframes("strokeColor", hues)], seconds: 2.4, phase: 0, smooth: false), on: star, key: "b")

        case .scanner:
            // A light sweeping back and forth, trailing an afterglow.
            star.isHidden = true
            let track = CAShapeLayer()
            track.path = CGPath(rect: CGRect(x: 1, y: 6, width: 20, height: 1), transform: nil)
            track.fillColor = accent
            track.opacity = 0.25
            fx.addSublayer(track)
            for k in (0..<4).reversed() {
                let d = dot(at: CGPoint(x: 3, y: mid.y), radius: 1.9 - CGFloat(k) * 0.25, color: accent)
                d.opacity = Float([1, 0.55, 0.3, 0.15][k])
                fx.addSublayer(d)
                play(group([keyframes("position.x", [3, 19, 3])], seconds: 1.3, phase: CGFloat(k) * -0.035, smooth: true), on: d)
            }

        case .helix:
            // Three rungs of dot pairs turning in step, offset like a strand of DNA.
            star.isHidden = true
            for row in 0..<3 {
                for side in 0..<2 {
                    let d = dot(at: CGPoint(x: mid.x, y: 2.5 + CGFloat(row) * 4), radius: 1.35, color: ink)
                    fx.addSublayer(d)
                    let x = mid.x
                    play(group([keyframes("position.x", [x - 4.5, x, x + 4.5, x, x - 4.5]),
                                keyframes("transform.scale", [1, 1.35, 1, 0.6, 1]),
                                keyframes("opacity", [0.75, 1, 0.75, 0.35, 0.75])],
                               seconds: 1.3, phase: CGFloat(side) * 0.5 + CGFloat(row) * 0.12, smooth: true), on: d)
                }
            }

        case .morph: buildMorph()
        case .sketch: buildSketch()
        case .chomp: buildChomp()
        case .mochi: buildMochi()
        case .kitty: buildKitty()
        case .brainstorm: buildBrainstorm()
        case .rocket: buildRocket()
        case .cradle: buildCradle()
        case .prompt: buildPrompt()
        case .cube: buildCube()
        }
    }

    // MARK: Animation helpers

    /// Adds a style's animation, except under Reduce Motion. Styles set their layers' model values to
    /// their still pose, so a build without animations is the Reduce Motion frame.
    func play(_ a: CAAnimation, on l: CALayer, key: String = "a") {
        guard !still else { return }
        l.add(a, forKey: key)
    }

    /// A duration that stays `s` real seconds however many sessions work (layer speed would shorten it).
    func pinned(_ s: CGFloat) -> CGFloat {
        speedBound = true
        return s * speed
    }

    /// A duration that speeds up with the session count like the rest, but no faster than `top`×.
    func capped(_ s: CGFloat, _ top: CGFloat) -> CGFloat {
        speedBound = true
        return s * speed / min(speed, top)
    }

    func loop(_ keyPath: String, from: CGFloat, to: CGFloat, seconds: CGFloat) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: keyPath)
        a.fromValue = from
        a.toValue = to
        a.duration = seconds
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        a.preferredFrameRateRange = Self.frameRate
        return a
    }

    /// Discrete animations take values.count + 1 times. group(smooth: true) makes every part cubic,
    /// so use smooth: false for a group with discrete parts.
    func keyframes(_ keyPath: String, _ values: [Any], times: [CGFloat]? = nil,
                   curves: [CAMediaTimingFunction]? = nil, discrete: Bool = false) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = values
        a.keyTimes = times?.map { NSNumber(value: Double($0)) }
        a.timingFunctions = curves
        if discrete { a.calculationMode = .discrete }
        return a
    }

    /// Repeating group. `phase` is a fraction of one cycle, so staggered layers start already in motion.
    func group(_ parts: [CAAnimation], seconds: CGFloat, phase: CGFloat, smooth: Bool) -> CAAnimationGroup {
        let g = CAAnimationGroup()
        g.animations = parts.map { p in p.duration = seconds; return p }
        if smooth { parts.forEach { ($0 as? CAKeyframeAnimation)?.calculationMode = .cubic } }
        g.duration = seconds
        g.repeatCount = .infinity
        g.isRemovedOnCompletion = false
        g.preferredFrameRateRange = Self.frameRate
        let offset = (phase.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        g.timeOffset = Double(offset * seconds)
        return g
    }

    /// Jump, squash on landing, spring back. Scaling keeps the star's feet on the ground.
    func hop() -> CAKeyframeAnimation {
        func pose(_ up: CGFloat, _ sx: CGFloat, _ sy: CGFloat) -> NSValue {
            NSValue(caTransform3D: CATransform3DScale(CATransform3DMakeTranslation(0, up - (1 - sy) * 6.5, 0), sx, sy, 1))
        }
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = [pose(0, 1.15, 0.8), pose(0, 0.9, 1.1), pose(4.5, 1, 1), pose(0, 1.05, 0.92), pose(0, 1.15, 0.8)]
        a.keyTimes = [0, 0.15, 0.45, 0.8, 1]
        a.duration = 1.1
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        a.preferredFrameRateRange = Self.frameRate
        return a
    }

    /// One Bloom frame as a bitmap, centred the way the glyph sits on the mark.
    private func sprite(_ glyph: String, size: CGFloat, scale: CGFloat, color: CGColor) -> CGImage? {
        let px = Int((size * scale).rounded(.up))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let g = NSAttributedString(string: glyph, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor(cgColor: color) ?? .labelColor])
        let s = g.size()
        g.draw(at: NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Not added anywhere: the caller adds it.
    func dot(at p: CGPoint, radius r: CGFloat, color: CGColor) -> CAShapeLayer {
        let d = CAShapeLayer()
        d.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
        d.position = p
        d.path = CGPath(ellipseIn: d.bounds, transform: nil)
        d.fillColor = color
        return d
    }

    /// A 13×13 layer centred on `p` in its parent (fx by default), for things that turn as one.
    @discardableResult
    func holder(at p: CGPoint, in parent: CALayer? = nil) -> CALayer {
        let l = CALayer()
        l.bounds = CGRect(x: 0, y: 0, width: 13, height: 13)
        l.position = p
        (parent ?? fx).addSublayer(l)
        return l
    }

    /// A shape layer covering its parent, so the path is in the parent's coordinates, added to that parent.
    @discardableResult
    func shape(_ path: CGPath, in parent: CALayer, fill: CGColor? = nil, stroke: CGColor? = nil,
               width: CGFloat = 1.5) -> CAShapeLayer {
        let l = CAShapeLayer()
        // build() runs from set() before layout() has sized fx.
        l.frame = parent === fx ? CGRect(x: 0, y: 0, width: markWidth, height: 13) : parent.bounds
        l.path = path
        l.fillColor = fill
        l.strokeColor = stroke
        l.lineWidth = width
        l.lineCap = .round
        l.lineJoin = .round
        parent.addSublayer(l)
        return l
    }

    /// Moves the anchor to local point `p` without moving the layer, so it turns and scales about `p`.
    /// Call it before giving the layer a transform: it reads the frame.
    func pivot(_ l: CALayer, at p: CGPoint) {
        let f = l.frame
        l.anchorPoint = CGPoint(x: p.x / l.bounds.width, y: p.y / l.bounds.height)
        l.position = CGPoint(x: f.minX + p.x, y: f.minY + p.y)
    }

    func segment(_ a: CGPoint, _ b: CGPoint) -> CGPath {
        let p = CGMutablePath()
        p.move(to: a)
        p.addLine(to: b)
        return p
    }

    func poly(_ points: [CGPoint], closed: Bool = true) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: points)
        if closed { p.closeSubpath() }
        return p
    }

    /// A pie slice from angle `a` to `b`, counter-clockwise in y-up space.
    func pie(_ a: CGFloat, _ b: CGFloat, center c: CGPoint = CGPoint(x: 6.5, y: 6.5), radius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: c)
        p.addArc(center: c, radius: r, startAngle: a, endAngle: b, clockwise: false)
        p.closeSubpath()
        return p
    }

    // MARK: Layout and drawing

    override func layout() {
        super.layout()
        var newInk = ink, newAccent = accent
        effectiveAppearance.performAsCurrentDrawingAppearance {
            newInk = (self.lit ? NSColor.labelColor : NSColor.secondaryLabelColor).cgColor
            newAccent = Palette.accent.cgColor
        }
        laidOut = (markWidth, lit)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let centre = CGPoint(x: 8 + markWidth / 2, y: bounds.midY)
        star.position = centre
        fx.bounds = CGRect(x: 0, y: 0, width: markWidth, height: 13)
        fx.position = centre
        CATransaction.commit()
        if newInk != ink || newAccent != accent {
            ink = newInk
            accent = newAccent
            applied = ""
            animate()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        needsLayout = true
        needsDisplay = true
    }

    /// Also runs on joining a window, so bitmaps built before that are redrawn at the real scale.
    override func viewDidChangeBackingProperties() {
        applied = ""
        needsLayout = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard lit else { return }
        Palette.pillTint.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: (bounds.height - 18) / 2, width: bounds.width, height: 18),
                     xRadius: 5, yRadius: 5).fill()
        var x: CGFloat = 8 + markWidth
        if working > 0 {
            let s = count, size = s.size()
            s.draw(at: NSPoint(x: x + 5, y: (bounds.height - size.height) / 2))
            x += 5 + size.width
        }
        for color in dots {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x + 5, y: (bounds.height - 7) / 2, width: 7, height: 7)).fill()
            x += 5 + 7
        }
    }

    /// Offscreen snapshots skip Core Animation sublayers, so the preview draws the star itself.
    func renderStar(in ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: frame.minX + star.position.x - 6.5, y: frame.minY + star.position.y - 6.5)
        star.render(in: ctx)
        ctx.restoreGState()
    }
}
