import SwiftUI

/// The single source of truth for the arc-house mark's geometry, in a 32×32 design space.
///
/// ## The system
/// Every dimension derives from the stroke width `W` (the base unit):
/// - **Half-widths on the integer ladder**: door 1W · shackle 2W · body 3W · roof 5W.
///   Every gap between neighboring strokes is exactly 1W by construction.
/// - **One shared center** `O` (the "wifi origin", on the axis at `base − 4.5W`): the body
///   cap and the roof arc are concentric around it, so their radial gap is a uniform 1W.
/// - **Roof flare**: the 5W arc swept ±60° from the apex, then extended tangentially by
///   1.5W — the eaves are the arc's own tangents, not a drawn flourish.
/// - **The fold**: the padlock's seam sits on the body cap's center line (the arch
///   collapses onto its own diameter); shackle legs are 1.5W; the socket floats 1.5W
///   off the bottom.
///
/// Both poses are three strokes with matched point counts (roof⇄shackle, walls⇄body,
/// door⇄socket), so any pose in between is a pointwise interpolation. Everything that
/// draws the mark — the popover's `MorphingMark`, the menu bar's `MenuBarIcon`, the app
/// icon's layer sources — derives from this.
nonisolated enum MarkGeometry {
    /// Side length of the square design space the strokes are expressed in.
    static let space: CGFloat = 32
    /// The base unit: everything else is a multiple of this.
    static let strokeWidth: CGFloat = 2.1

    private static let w = strokeWidth
    private static let axis: CGFloat = 16
    private static let base: CGFloat = 27
    /// The shared center of the body cap and roof arc — the wifi origin.
    private static let originY = base - 4.5 * w

    /// Home pose: roof (flared 5W arc), body (3W arch), door (1W arch).
    static let homeStrokes: [[CGPoint]] = {
        let roofR = 5 * w
        let sweep: CGFloat = .pi / 3 // ±60° from apex
        let kick = 1.5 * w
        let arc = arcPoints(cy: originY, r: roofR, from: .pi / 2 + sweep, to: .pi / 2 - sweep, n: 36)
        let leftKick = tangentKick(cy: originY, r: roofR, at: .pi / 2 + sweep, length: kick, n: 6)
        let rightKick = tangentKick(cy: originY, r: roofR, at: .pi / 2 - sweep, length: kick, n: 6)
        let roof = leftKick.reversed() + arc + rightKick

        // Legs split so their lower quarter has its own points: those morph into the
        // locked pose's bottom seal (the feet folding inward under the body).
        let footY = base - 2.5 * w
        let body = line((axis - 3 * w, base), (axis - 3 * w, footY), 6)
            + line((axis - 3 * w, footY), (axis - 3 * w, originY), 12)
            + arcPoints(cy: originY, r: 3 * w, from: .pi, to: 0, n: 28)
            + line((axis + 3 * w, originY), (axis + 3 * w, footY), 12)
            + line((axis + 3 * w, footY), (axis + 3 * w, base), 6)

        let doorC = base - 2.5 * w
        let door = line((axis - w, base), (axis - w, doorC + w), 6)
            + line((axis - w, doorC + w), (axis - w, doorC), 6)
            + arcPoints(cy: doorC, r: w, from: .pi, to: 0, n: 24)
            + line((axis + w, doorC), (axis + w, doorC + w), 6)
            + line((axis + w, doorC + w), (axis + w, base), 6)

        return [Array(roof), body, door]
    }()

    /// Locked pose, matched point counts: shackle (2W dome, 1.5W legs), body (a CLOSED
    /// rounded rect — the chain starts and ends at bottom center, so the home pose's leg
    /// feet visibly fold inward and seal the underside), keyhole (the door, closed at the
    /// bottom and slid down into the body).
    static let lockedStrokes: [[CGPoint]] = {
        let seam = originY
        let shackleC = seam - 1.5 * w
        let shackle = line((axis - 2 * w, seam), (axis - 2 * w, shackleC), 6)
            + arcPoints(cy: shackleC, r: 2 * w, from: .pi, to: 0, n: 36)
            + line((axis + 2 * w, shackleC), (axis + 2 * w, seam), 6)

        let corner = 0.5 * w
        let left = axis - 3 * w
        let right = axis + 3 * w
        let body = line((axis, base), (left + corner, base), 6)
            + arcPoints(cx: left + corner, cy: base - corner, r: corner, from: 1.5 * .pi, to: .pi, n: 4)
            + line((left, base - corner), (left, seam), 8)
            + line((left, seam), (right, seam), 28)
            + line((right, seam), (right, base - corner), 8)
            + arcPoints(cx: right - corner, cy: base - corner, r: corner, from: 0, to: -0.5 * .pi, n: 4)
            + line((right - corner, base), (axis, base), 6)

        let keyholeC = seam + 2.5 * w
        let keyholeBase = keyholeC + 0.5 * w
        let keyhole = line((axis, keyholeBase), (axis - w, keyholeBase), 6)
            + line((axis - w, keyholeBase), (axis - w, keyholeC), 6)
            + arcPoints(cy: keyholeC, r: w, from: .pi, to: 0, n: 24)
            + line((axis + w, keyholeC), (axis + w, keyholeBase), 6)
            + line((axis + w, keyholeBase), (axis, keyholeBase), 6)

        return [shackle, body, keyhole]
    }()

    /// Center of the locked body — the anchor for reduced-detail lock variants
    /// (the menu bar's dot keyhole sits here, at the body's optical center).
    static let lockBodyCenter = CGPoint(x: axis, y: originY + 2.25 * w)

    /// Union bounding box of both poses, expanded by the stroke, in design space.
    /// Canvas fitting derives from this so it can never drift from the geometry.
    static let designBounds: CGRect = {
        let all = (homeStrokes + lockedStrokes).flatMap(\.self)
        let xs = all.map(\.x)
        let ys = all.map(\.y)
        let inset = strokeWidth / 2
        return CGRect(
            x: xs.min()! - inset,
            y: ys.min()! - inset,
            width: xs.max()! - xs.min()! + strokeWidth,
            height: ys.max()! - ys.min()! + strokeWidth,
        )
    }()

    /// The pose at `progress` (0 = home, 1 = locked), interpolated pointwise.
    static func strokes(progress: CGFloat) -> [[CGPoint]] {
        zip(homeStrokes, lockedStrokes).map { home, locked in
            zip(home, locked).map { h, l in
                CGPoint(x: h.x + (l.x - h.x) * progress, y: h.y + (l.y - h.y) * progress)
            }
        }
    }

    // MARK: - Constructors

    /// Points along a circular arc centered on (`cx`, `cy`); angles in standard math
    /// orientation (screen y grows downward, so `y = cy − r·sin(φ)`).
    private static func arcPoints(cx: CGFloat = axis, cy: CGFloat, r: CGFloat, from a0: CGFloat, to a1: CGFloat, n: Int) -> [CGPoint] {
        (0 ..< n).map { i in
            let a = a0 + (a1 - a0) * CGFloat(i) / CGFloat(n - 1)
            return CGPoint(x: cx + r * cos(a), y: cy - r * sin(a))
        }
    }

    /// A straight extension continuing the arc's tangent at angle `a`, moving away from
    /// the apex (downward/outward) — the roof's eave kick.
    private static func tangentKick(cy: CGFloat, r: CGFloat, at a: CGFloat, length: CGFloat, n: Int) -> [CGPoint] {
        let start = CGPoint(x: axis + r * cos(a), y: cy - r * sin(a))
        // Tangent direction pointing away from the apex, i.e. outward in x, downward in y.
        let dx = abs(sin(a))
        let dy = abs(cos(a))
        let sign: CGFloat = cos(a) >= 0 ? 1 : -1
        return (1 ... n).map { i in
            let t = length * CGFloat(i) / CGFloat(n)
            return CGPoint(x: start.x + sign * dx * t, y: start.y + dy * t)
        }
    }

    private static func line(_ p0: (CGFloat, CGFloat), _ p1: (CGFloat, CGFloat), _ n: Int) -> [CGPoint] {
        (0 ..< n).map { i in
            let t = CGFloat(i) / CGFloat(n - 1)
            return CGPoint(x: p0.0 + (p1.0 - p0.0) * t, y: p0.1 + (p1.1 - p0.1) * t)
        }
    }
}

/// The arc-house mark as an animatable shape: `progress` 0 = home, 1 = locked.
///
/// The fold is a real morph — the roof arc closing into the shackle — rather than a
/// symbol swap (symbol replace transitions can't morph unannotated custom symbols).
struct MorphingMark: View {
    var progress: CGFloat
    var animation: Animation? = .smooth(duration: 0.45)

    /// The fold is animated through private state so only the shape's `progress` ever
    /// animates. Animating the external value (e.g. `.animation(_:value:)` at the call
    /// site) would also animate concurrent layout changes in the same transaction —
    /// switching the mode to Off resizes the popover, and the icon would slide instead
    /// of morphing.
    @State private var displayedProgress: CGFloat

    init(progress: CGFloat, animation: Animation? = .smooth(duration: 0.45)) {
        self.progress = progress
        self.animation = animation
        _displayedProgress = State(initialValue: progress)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / MarkGeometry.space
            MorphingMarkShape(progress: displayedProgress)
                .stroke(style: StrokeStyle(lineWidth: MarkGeometry.strokeWidth * scale, lineCap: .round, lineJoin: .round))
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(animation) {
                displayedProgress = newValue
            }
        }
    }
}

private struct MorphingMarkShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / MarkGeometry.space
        var path = Path()
        for points in MarkGeometry.strokes(progress: progress) {
            path.move(to: CGPoint(x: points[0].x * scale + rect.minX, y: points[0].y * scale + rect.minY))
            for p in points.dropFirst() {
                path.addLine(to: CGPoint(x: p.x * scale + rect.minX, y: p.y * scale + rect.minY))
            }
        }
        return path
    }
}
