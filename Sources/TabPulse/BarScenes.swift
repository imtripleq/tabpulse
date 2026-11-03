import Cocoa

extension PillView {
    func buildPrompt() {
        star.isHidden = true
        let clip = CALayer()
        clip.frame = CGRect(x: 0, y: 0, width: markWidth, height: 13)
        clip.masksToBounds = true
        fx.addSublayer(clip)
        let line = CALayer()
        line.frame = clip.bounds
        clip.addSublayer(line)
        shape(poly([CGPoint(x: 2, y: 9.5), CGPoint(x: 5, y: 6.5), CGPoint(x: 2, y: 3.5)], closed: false),
              in: line, stroke: accent, width: 1.5)

        let seconds: CGFloat = 1.9
        let typed: [CGFloat] = [0.10, 0.17, 0.27, 0.33]
        // A 2.5 pt character pitch on the half-point grid keeps every edge on a Retina pixel.
        let cells: [CGFloat] = [7.5, 10, 13.5, 16]
        for (x, f) in zip(cells, typed) {
            let c = CALayer()
            c.backgroundColor = ink
            c.cornerRadius = 0.4
            c.frame = CGRect(x: x, y: 3.5, width: 2, height: 1.5)
            c.opacity = 0
            line.addSublayer(c)
            play(group([keyframes("opacity", [0, 1, 0], times: [0, f, 0.86, 1], discrete: true)],
                       seconds: seconds, phase: 0, smooth: false), on: c)
        }

        let cursor = CALayer()
        cursor.backgroundColor = accent
        cursor.bounds = CGRect(x: 0, y: 0, width: 2, height: 6)
        cursor.anchorPoint = CGPoint(x: 0.5, y: 0)
        cursor.position = CGPoint(x: 8.5, y: 3.5)
        line.addSublayer(cursor)
        play(group([keyframes("position.x", [8.5, 11, 14.5, 17, 19.5, 8.5], times: [0] + typed + [0.86, 1], discrete: true),
                    keyframes("opacity", [1, 0, 1, 0, 1], times: [0, 0.45, 0.58, 0.70, 0.80, 1], discrete: true)],
                   seconds: seconds, phase: 0, smooth: false), on: cursor)

        // Enter scrolls two lines together: the typed one up and out, a fresh prompt parked a line below up into
        // its place. They snap back at 0.861, when the reset typed line looks exactly like the fresh one.
        let fresh = CALayer()
        fresh.frame = clip.bounds.offsetBy(dx: 0, dy: -11)
        clip.addSublayer(fresh)
        shape(poly([CGPoint(x: 2, y: 9.5), CGPoint(x: 5, y: 6.5), CGPoint(x: 2, y: 3.5)], closed: false),
              in: fresh, stroke: accent, width: 1.5)
        let idle = CALayer()
        idle.backgroundColor = accent
        idle.frame = CGRect(x: 7.5, y: 3.5, width: 2, height: 6)
        fresh.addSublayer(idle)
        let lin = CAMediaTimingFunction(name: .linear), ease = CAMediaTimingFunction(name: .easeInEaseOut)
        for l in [line, fresh] {
            play(group([keyframes("transform.translation.y", [0, 0, 11, 0, 0], times: [0, 0.74, 0.86, 0.861, 1],
                                  curves: [lin, ease, lin, lin])],
                       seconds: seconds, phase: 0, smooth: false), on: l)
        }
    }

    func buildBrainstorm() {
        star.isHidden = true
        // Pinned, so a busy bar never strobes.
        let seconds = pinned(2.4), strike: [CGFloat] = [0, 0.78, 0.8, 0.83, 0.86, 0.92, 1]
        let rain = holder(at: mid)
        for (i, x) in [4.0, 6.7, 9.4].enumerated() {
            let drop = shape(segment(CGPoint(x: x, y: 5.4), CGPoint(x: x - 0.45, y: 3.6)), in: rain, stroke: ink, width: 1.1)
            let p = CGFloat(i + 1) * 0.25
            drop.transform = CATransform3DMakeTranslation(-0.8 * p, -5 * p, 0)
            play(group([keyframes("transform.translation.y", [0, -5]), keyframes("transform.translation.x", [0, -0.8]),
                        keyframes("opacity", [0, 1, 1, 0], times: [0, 0.15, 0.8, 1])],
                       seconds: 0.6, phase: [0, 0.4, 0.75][i], smooth: false), on: drop)
        }
        // The rain dims while the bolt is out, so grey drops never cut across its zigzag. The still shows the bolt out.
        rain.opacity = 0.4
        play(group([keyframes("opacity", [1, 1, 0.25, 0.25, 0.25, 1, 1], times: strike)], seconds: seconds, phase: 0, smooth: false),
             on: rain)

        let bolt = shape(poly([CGPoint(x: 7.0, y: 6.4), CGPoint(x: 4.7, y: 2.6), CGPoint(x: 6.6, y: 2.6), CGPoint(x: 5.3, y: -0.8),
                               CGPoint(x: 9.2, y: 3.8), CGPoint(x: 7.3, y: 3.8), CGPoint(x: 8.9, y: 6.4)]), in: fx, fill: accent)
        play(group([keyframes("opacity", [0, 0, 1, 0.15, 1, 0, 0], times: strike)], seconds: seconds, phase: 0, smooth: false), on: bolt)

        let puff = CGMutablePath()
        for (x, y, r) in [(4.0, 8.3, 2.5), (7.0, 9.7, 3.0), (9.7, 8.1, 2.3)] as [(CGFloat, CGFloat, CGFloat)] {
            puff.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        puff.addRoundedRect(in: CGRect(x: 1.5, y: 5.8, width: 10.2, height: 3.2), cornerWidth: 1.6, cornerHeight: 1.6)
        let cloud = shape(puff, in: fx, fill: ink)
        pivot(cloud, at: CGPoint(x: 6.7, y: 8.4))
        play(group([keyframes("transform.scale", [1, 1.04, 1])], seconds: 1.2, phase: 0, smooth: true), on: cloud)
        // The strike lights the cloud up from inside, half strength so the solid bolt still stands out against it.
        let glow = accent.copy(alpha: 0.5) ?? accent
        play(group([keyframes("fillColor", [ink, ink, glow, ink, glow, ink, ink], times: strike)],
                   seconds: seconds, phase: 0, smooth: false), on: cloud, key: "b")
    }

    func buildCradle() {
        star.isHidden = true
        shape(segment(CGPoint(x: 3, y: 11.6), CGPoint(x: 19, y: 11.6)), in: fx, stroke: ink, width: 1).opacity = 0.6
        var arms: [CALayer] = []
        for k in 0..<5 {
            let p = CALayer()
            p.bounds = CGRect(x: 0, y: 0, width: 3.2, height: 8.6)
            p.anchorPoint = CGPoint(x: 0.5, y: 1)
            p.position = CGPoint(x: 4.6 + 3.2 * CGFloat(k), y: 11.6)
            fx.addSublayer(p)
            shape(segment(CGPoint(x: 1.6, y: 8.6), CGPoint(x: 1.6, y: 3.2)), in: p, stroke: ink, width: 0.8).opacity = 0.7
            p.addSublayer(dot(at: CGPoint(x: 1.6, y: 1.6), radius: 1.6, color: k == 0 || k == 4 ? accent : ink))
            arms.append(p)
        }
        // Capped: a desk toy swinging twice as fast stops looking like gravity.
        let seconds = capped(1.2, 1.35)
        let fall = CAMediaTimingFunction(name: .easeIn), climb = CAMediaTimingFunction(name: .easeOut)
        let lin = CAMediaTimingFunction(name: .linear)
        arms[0].transform = CATransform3DMakeRotation(-0.5, 0, 0, 1)
        play(group([keyframes("transform.rotation.z", [-0.5, 0, 0, -0.5], times: [0, 0.25, 0.75, 1], curves: [fall, lin, climb])],
                   seconds: seconds, phase: 0, smooth: false), on: arms[0])
        play(group([keyframes("transform.rotation.z", [0, 0, 0.5, 0, 0], times: [0, 0.25, 0.5, 0.75, 1],
                              curves: [lin, climb, fall, lin])],
                   seconds: seconds, phase: 0, smooth: false), on: arms[4])
    }
}
