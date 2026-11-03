import Cocoa

extension PillView {
    /// A pen nib writes the ✳ stroke by stroke over a faint tracing, flashes it purple, then erases it in order.
    func buildSketch() {
        star.isHidden = true
        shape(star.path!, in: fx, stroke: ink, width: 1.5).opacity = 0.16
        let pen = holder(at: mid)
        // The order a hand writes ✳: down, across, then the two diagonals from the top.
        let ends = [CGFloat.pi / 2, .pi, 3 * .pi / 4, .pi / 4].map { a -> (CGPoint, CGPoint) in
            let dx = 5.6 * cos(a), dy = 5.6 * sin(a)
            return (CGPoint(x: 6.5 + dx, y: 6.5 + dy), CGPoint(x: 6.5 - dx, y: 6.5 - dy))
        }
        // Above 1.3x each stroke takes about 0.13 s and reads as flicker.
        let T = capped(2.4, 1.3)
        let D = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1), lin = CAMediaTimingFunction(name: .linear)
        // The erase speeds up into its end: an eased-out one crawls and leaves a round-cap dot behind.
        let wipe = CAMediaTimingFunction(name: .easeIn)
        for (i, (a, b)) in ends.enumerated() {
            let s = 0.03 + 0.12 * CGFloat(i), e = 0.66 + 0.06 * CGFloat(i)
            // Reduce Motion shows the finished star in accent, like the other star styles' still pose.
            let stroke = shape(segment(a, b), in: pen, stroke: still ? accent : ink)
            play(group([keyframes("strokeEnd", [0, 0, 1, 1], times: [0, s, s + 0.1, 1], curves: [lin, D, lin]),
                        keyframes("strokeStart", [0, 0, 1, 1], times: [0, e, e + 0.1, 1], curves: [lin, wipe, lin]),
                        // A quick return: the accent-to-ink blend is a muddy aubergine on light bars.
                        keyframes("strokeColor", [ink, ink, accent, ink, ink], times: [0, 0.49, 0.52, 0.56, 1])],
                       seconds: T, phase: 0, smooth: false), on: stroke)
        }
        play(group([keyframes("transform.scale", [1, 1, 1.08, 1, 1], times: [0, 0.49, 0.53, 0.6, 1])],
                   seconds: T, phase: 0, smooth: false), on: pen)
        let nib = dot(at: ends[0].0, radius: 1.15, color: accent)
        nib.opacity = 0
        pen.addSublayer(nib)
        let K: [CGFloat] = [0] + (0..<4).flatMap { i -> [CGFloat] in let s = 0.03 + 0.12 * CGFloat(i); return [s, s + 0.1] } + [1]
        let route = [ends[0].0] + ends.flatMap { [$0.0, $0.1] } + [ends[3].1]
        play(group([keyframes("position", route.map { NSValue(point: $0) }, times: K,
                              curves: [lin] + (0..<4).flatMap { _ in [D, lin] }),
                    keyframes("opacity", [0, 1, 0, 1, 0, 1, 0, 1, 0], times: K, discrete: true)],
                   seconds: T, phase: 0, smooth: false), on: nib)
    }

    /// The same 96 vertices on fixed rays, so the star and ring morph without self-intersecting.
    private static func radial(_ r: (CGFloat) -> CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: (0..<96).map { i in
            let t = 2 * CGFloat.pi * CGFloat(i) / 96
            return CGPoint(x: 6.5 + r(t) * cos(t), y: 6.5 + r(t) * sin(t))
        })
        p.closeSubpath()
        return p
    }
    private static let morphStar = radial { 0.6 + 5.2 * pow(abs(cos(4 * $0)), 14) }
    private static let morphRing = radial { _ in 4.5 }

    /// The ✳ melts into a purple ring and sharpens back, turning an eighth each way; the star holds longest.
    func buildMorph() {
        star.isHidden = true
        let m = shape(Self.morphStar, in: fx, stroke: still ? accent : ink, width: 1.3)
        let T: [CGFloat] = [0, 0.2, 0.4, 0.6, 1]
        let E = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1), lin = CAMediaTimingFunction(name: .linear)
        let tf = [E, lin, E, lin]
        let q = CGFloat.pi / 4
        play(group([keyframes("path", [Self.morphStar, Self.morphRing, Self.morphRing, Self.morphStar, Self.morphStar],
                              times: T, curves: tf),
                    // The star's eighth-turn symmetry hides the snap from -π/2 back to 0.
                    keyframes("transform.rotation.z", [0, -q, -q, -2 * q, -2 * q], times: T, curves: tf),
                    keyframes("strokeColor", [ink, accent, accent, ink, ink], times: T, curves: tf)],
                   seconds: 2.4, phase: 0, smooth: false), on: m)
    }

    /// A purple wireframe cube turning in perspective, its hidden edges dimmed.
    func buildCube() {
        star.isHidden = true
        let view = holder(at: mid)
        var persp = CATransform3DIdentity
        persp.m34 = -1.0 / 45
        view.sublayerTransform = CATransform3DConcat(CATransform3DMakeRotation(0.45, 1, 0, 0), persp)
        let cube = CATransformLayer()
        cube.bounds = CGRect(x: 0, y: 0, width: 13, height: 13)
        cube.position = CGPoint(x: 6.5, y: 6.5)
        cube.transform = CATransform3DMakeRotation(.pi / 6, 0, 1, 0)
        view.addSublayer(cube)
        let turns = [CATransform3DIdentity, CATransform3DMakeRotation(.pi, 0, 1, 0),
                     CATransform3DMakeRotation(.pi / 2, 0, 1, 0), CATransform3DMakeRotation(-.pi / 2, 0, 1, 0),
                     CATransform3DMakeRotation(.pi / 2, 1, 0, 0), CATransform3DMakeRotation(-.pi / 2, 1, 0, 0)]
        let px = max(3, rasterScale)
        for r in turns {
            let f = CATransform3DTranslate(r, 0, 0, 3.5)
            // Back-face culling shows each face's bright copy only when it faces you, its dim twin only when it doesn't.
            for (transform, width, opacity) in [(f, 0.9, 1), (CATransform3DRotate(f, .pi, 0, 1, 0), 0.6, 0.3)] as [(CATransform3D, CGFloat, Float)] {
                let face = CAShapeLayer()
                face.bounds = CGRect(x: 0, y: 0, width: 7, height: 7)
                face.position = CGPoint(x: 6.5, y: 6.5)
                face.path = CGPath(rect: face.bounds, transform: nil)
                face.fillColor = nil
                // Opaque accent, since every edge is stroked by two faces: translucent ink drew them darker and doubled.
                face.strokeColor = accent
                face.lineWidth = width
                face.lineJoin = .round
                face.opacity = opacity
                face.isDoubleSided = false
                face.contentsScale = px   // 3D-transformed shape layers are rasterised and go soft at 1x
                face.transform = transform
                cube.addSublayer(face)
            }
        }
        // A quarter turn looks identical, so the loop is seamless.
        play(loop("transform.rotation.y", from: 0, to: .pi / 2, seconds: 1.2), on: cube)
    }
}
