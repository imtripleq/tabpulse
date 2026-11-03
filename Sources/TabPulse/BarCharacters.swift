import Cocoa

extension PillView {
    /// A chomper munching along a row of dots, one bite per dot.
    func buildChomp() {
        star.isHidden = true
        // Left edge at the mouth's apex, so no clip edge ever shows between the jaws.
        let track = CALayer()
        track.frame = CGRect(x: 5.5, y: 0, width: 16.5, height: 13)
        track.masksToBounds = true
        fx.addSublayer(track)
        // Past 1.35x the bite turns into a buzz.
        let bite = capped(0.36, 1.35)
        // Each dot slides one pitch per bite; the newest grows in rather than appearing clipped at the edge.
        for k in 0..<4 {
            let d = dot(at: CGPoint(x: 4 + 4 * CGFloat(k), y: 6.5), radius: 1.2, color: ink)
            d.opacity = k == 3 ? 0 : 0.8
            track.addSublayer(d)
            var parts: [CAAnimation] = [keyframes("transform.translation.x", [0, -4])]
            if k == 0 {
                // Swallowed: gone by the time the jaws shut on it.
                parts.append(keyframes("opacity", [0.8, 0.8, 0, 0], times: [0, 0.3, 0.5, 1]))
            } else if k == 3 {
                parts += [keyframes("transform.scale", [0, 1.15, 1], times: [0, 0.75, 1]),
                          keyframes("opacity", [0, 0.8, 0.8], times: [0, 0.5, 1])]
            }
            play(group(parts, seconds: bite, phase: 0, smooth: false), on: d)
        }

        let head = holder(at: CGPoint(x: 5.5, y: 6.5))
        let top = shape(pie(0, .pi, radius: 4.6), in: head, fill: accent)
        let bottom = shape(pie(.pi, 2 * .pi, radius: 4.6), in: head, fill: accent)
        // Open is the model value, so the still pose is mid-bite rather than a closed circle.
        top.transform = CATransform3DMakeRotation(0.62, 0, 0, 1)
        bottom.transform = CATransform3DMakeRotation(-0.62, 0, 0, 1)
        play(group([keyframes("transform.rotation.z", [0.62, 0.04, 0.62])], seconds: bite, phase: 0, smooth: true), on: top)
        play(group([keyframes("transform.rotation.z", [-0.62, -0.04, -0.62])], seconds: bite, phase: 0, smooth: true), on: bottom)
        top.addSublayer(dot(at: CGPoint(x: 7.8, y: 9.1), radius: 0.7, color: faceInk))
    }

    /// A blushing mochi that boings, wobbles like jelly and scrunches its eyes on the squish.
    func buildMochi() {
        star.isHidden = true
        // Base at 1.6 puts the blob's feet on the count's baseline.
        let body = shape(CGPath(roundedRect: CGRect(x: 1.4, y: 1.6, width: 10.2, height: 8.0), cornerWidth: 4.0,
                                cornerHeight: 3.8, transform: nil), in: fx, fill: accent)
        pivot(body, at: CGPoint(x: 6.5, y: 1.6))

        let blush = CGMutablePath()
        blush.addEllipse(in: CGRect(x: 2.4, y: 4.25, width: 1.6, height: 0.9))
        blush.addEllipse(in: CGRect(x: 9.0, y: 4.25, width: 1.6, height: 0.9))
        shape(blush, in: body, fill: Palette.rgb(0xFF6FA8, alpha: 0.75).cgColor)
        shape(CGPath(ellipseIn: CGRect(x: 3.0, y: 7.5, width: 1.7, height: 0.9), transform: nil), in: body,
              fill: CGColor(gray: 1, alpha: 0.5))
        let mouth = CGMutablePath()
        mouth.addArc(center: CGPoint(x: 6.5, y: 5.2), radius: 0.85, startAngle: 1.15 * .pi, endAngle: 1.85 * .pi, clockwise: false)
        shape(mouth, in: body, stroke: faceInk, width: 0.8)

        // Past 1.35x the wobble turns into a twitch.
        let t = capped(1.4, 1.35)
        let k: [CGFloat] = [0, 0.1, 0.24, 0.38, 0.52, 0.64, 1]
        play(group([keyframes("transform.scale.x", [1, 1.18, 0.88, 1.07, 0.97, 1, 1], times: k),
                    keyframes("transform.scale.y", [1, 0.8, 1.14, 0.94, 1.03, 1, 1], times: k)],
                   seconds: t, phase: 0, smooth: true), on: body)
        for x: CGFloat in [4.6, 8.4] {
            let eye = dot(at: CGPoint(x: x, y: 6.1), radius: 0.85, color: faceInk)
            body.addSublayer(eye)
            play(group([keyframes("transform.scale.y", [1, 1, 0.15, 0.15, 1, 1], times: [0, 0.04, 0.1, 0.16, 0.26, 1])],
                       seconds: t, phase: 0, smooth: false), on: eye)
        }
    }

    /// A cat head vibing side to side, with a blink and an ear flick every third bop.
    func buildKitty() {
        star.isHidden = true
        let head = holder(at: mid)
        pivot(head, at: CGPoint(x: 6.5, y: 1.2))
        shape(poly([CGPoint(x: 1.8, y: 7.0), CGPoint(x: 2.4, y: 12.4), CGPoint(x: 5.6, y: 9.5)]), in: head, fill: accent)
        let rightEar = shape(poly([CGPoint(x: 11.2, y: 7.0), CGPoint(x: 10.6, y: 12.4), CGPoint(x: 7.4, y: 9.5)]),
                             in: head, fill: accent)
        pivot(rightEar, at: CGPoint(x: 9.3, y: 8.2))

        shape(CGPath(ellipseIn: CGRect(x: 1.2, y: 1.2, width: 10.6, height: 8.4), transform: nil), in: head, fill: accent)
        func features(eyeHeight h: CGFloat) -> CGPath {
            let p = CGMutablePath()
            for x: CGFloat in [4.5, 8.5] { p.addEllipse(in: CGRect(x: x - 0.85, y: 5.9 - h / 2, width: 1.7, height: h)) }
            p.addPath(poly([CGPoint(x: 5.9, y: 4.4), CGPoint(x: 7.1, y: 4.4), CGPoint(x: 6.5, y: 3.7)]))
            return p
        }
        let open = features(eyeHeight: 2.3), shut = features(eyeHeight: 0.35)
        let face = shape(open, in: head, fill: faceInk)

        // Eased half swings: the head dwells at each side and whips through the middle, dropping onto every beat.
        let sway = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.4, 1)
        let rise = CAMediaTimingFunction(name: .easeOut), drop = CAMediaTimingFunction(name: .easeIn)
        play(group([keyframes("transform.rotation.z", [0.15, -0.15, 0.15], curves: [sway, sway]),
                    keyframes("transform.translation.y", [-0.6, 0, -0.6, 0, -0.6], curves: [rise, drop, rise, drop])],
                   seconds: 1.3, phase: 0, smooth: false), on: head)
        // 3.9 s is three bops, so the whole style loops exactly.
        play(group([keyframes("path", [open, open, shut, open, open], times: [0, 0.86, 0.89, 0.93, 1])],
                   seconds: 3.9, phase: 0, smooth: false), on: face)
        play(group([keyframes("transform.rotation.z", [0, 0, -0.35, 0.05, -0.3, 0, 0], times: [0, 0.4, 0.43, 0.46, 0.49, 0.52, 1])],
                   seconds: 3.9, phase: 0, smooth: false), on: rightEar)
    }

    /// A rocket climbing up and to the right on a flickering flame, with speed streaks whipping past.
    func buildRocket() {
        star.isHidden = true
        // Maps (along the ship's axis, across it) to fx; the ship points up-right at 45 degrees.
        func at(_ a: CGFloat, _ p: CGFloat) -> CGPoint { CGPoint(x: 6.5 + 0.7071 * (a + p), y: 6.5 + 0.7071 * (a - p)) }
        // ink is translucent, so streaks run clear of the hull and fins rather than behind them.
        let streaks: [(p: CGFloat, a: CGFloat, run: CGFloat)] = [(-4.0, 5.0, 8.0), (3.6, 5.2, 8.4)]
        for (i, s) in streaks.enumerated() {
            let streak = shape(segment(at(s.a, s.p), at(s.a - 2.2, s.p)), in: fx, stroke: ink, width: 1.1)
            streak.opacity = 0
            let d = -s.run * 0.7071
            play(group([keyframes("transform.translation.x", [0, d]), keyframes("transform.translation.y", [0, d]),
                        keyframes("opacity", [0, 0.8, 0])], seconds: 0.6, phase: CGFloat(i) * 0.5, smooth: false), on: streak)
        }
        let shake = holder(at: mid)
        let ship = holder(at: CGPoint(x: 6.5, y: 6.5), in: shake)
        ship.transform = CATransform3DMakeRotation(-.pi / 4, 0, 0, 1)

        func teardrop(_ halfWidth: CGFloat, tip: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 6.5 - halfWidth, y: 4.0))
            p.addQuadCurve(to: CGPoint(x: 6.5, y: tip), control: CGPoint(x: 6.5 - halfWidth * 1.15, y: (4 + tip) / 2.4))
            p.addQuadCurve(to: CGPoint(x: 6.5 + halfWidth, y: 4.0), control: CGPoint(x: 6.5 + halfWidth * 1.15, y: (4 + tip) / 2.4))
            p.closeSubpath()
            return p
        }
        let flame = shape(teardrop(1.3, tip: -1.6), in: ship, fill: accent)
        // A white core reads as a hole in the deep light-mode purple, so that bar gets a lavender one.
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        shape(teardrop(0.6, tip: 0.6), in: flame, fill: dark ? CGColor(gray: 1, alpha: 0.9) : Palette.rgb(0xc4a1f5).cgColor)
        pivot(flame, at: CGPoint(x: 6.5, y: 4.0))

        // Hull, fins and window in one path: separate translucent layers show a seam where they meet.
        let hull = CGMutablePath()
        hull.move(to: CGPoint(x: 6.5, y: 12.2))
        hull.addQuadCurve(to: CGPoint(x: 8.4, y: 7.6), control: CGPoint(x: 8.4, y: 10.6))
        hull.addLine(to: CGPoint(x: 8.4, y: 4.0))
        hull.addLine(to: CGPoint(x: 4.6, y: 4.0))
        hull.addLine(to: CGPoint(x: 4.6, y: 7.6))
        hull.addQuadCurve(to: CGPoint(x: 6.5, y: 12.2), control: CGPoint(x: 4.6, y: 10.6))
        hull.closeSubpath()
        hull.addEllipse(in: CGRect(x: 5.5, y: 7.3, width: 2, height: 2))
        hull.addPath(poly([CGPoint(x: 4.6, y: 6.6), CGPoint(x: 2.8, y: 3.2), CGPoint(x: 4.6, y: 4.0)]))
        hull.addPath(poly([CGPoint(x: 8.4, y: 6.6), CGPoint(x: 10.2, y: 3.2), CGPoint(x: 8.4, y: 4.0)]))
        let body = shape(hull, in: ship, fill: ink)
        body.fillRule = .evenOdd

        play(group([keyframes("transform.scale.y", [1, 0.55, 1.05, 0.7, 1]), keyframes("transform.scale.x", [1, 0.85, 1, 0.9, 1])],
                   seconds: 0.24, phase: 0, smooth: false), on: flame)
        // Fixed real duration, so more sessions never turn the rumble into a buzz.
        play(group([keyframes("transform.translation.x", [0, 0.3, -0.25, 0.2, 0]),
                    keyframes("transform.translation.y", [0, -0.25, 0.3, -0.2, 0])], seconds: pinned(0.2), phase: 0, smooth: false),
             on: shake)
    }
}
