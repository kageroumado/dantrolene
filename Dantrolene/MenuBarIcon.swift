import AppKit
import SwiftUI

/// Menu-bar icon: the arc-house (preventing lock) / padlock (locking normally).
///
/// `MenuBarExtra` resolves its label down to a bare `NSImage` and discards every other
/// modifier — the status item's width tracks the image itself. Both states therefore draw
/// into one **constant-size canvas** in the shared `MarkGeometry` space, so the item never
/// changes width when the state flips and the popover anchors to a stable point. (Same
/// technique as Adrafinil's `MenuBarIcon`; see the long rationale there.) Template image,
/// so the menu bar tints it for light/dark and for the highlighted state.
enum MenuBarIcon {
    /// How much interior detail the locked pose carries at menu bar size, where the full
    /// keyhole arch reads as noise. The popover's morph keeps the keyhole; only this
    /// static rendering simplifies.
    enum LockedDetail: String, CaseIterable {
        /// Shackle and sealed body only — a plain padlock silhouette.
        case plain
        /// Plain, plus a single filled dot at the body's optical center.
        case dot
        /// The full morph-target pose, keyhole and all.
        case keyhole
    }

    /// The shipping choice for the locked state.
    static let lockedDetail: LockedDetail = .plain

    /// Sized so the mark matches the visual height of chunky neighbors (the input-source
    /// "A" card), with the width fixed to the widest pose (the house's eaves) so the item
    /// never resizes. Aspect follows `MarkGeometry.designBounds`.
    private static let canvasSize = NSSize(width: 19.5, height: 18)

    private static var cache: [String: NSImage] = [:]

    static func image(locked: Bool) -> NSImage {
        image(locked: locked, detail: lockedDetail)
    }

    static func image(locked: Bool, detail: LockedDetail) -> NSImage {
        let key = locked ? "locked-\(detail.rawValue)" : "home"
        if let cached = cache[key] {
            return cached
        }

        let image = NSImage(size: canvasSize, flipped: true) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }

            // Fit the union bounds of both poses (mark extents plus stroke) to the canvas,
            // identically for both poses, centered on the mark's vertical axis.
            let bounds = MarkGeometry.designBounds
            let scale = min(rect.height / bounds.height, rect.width / bounds.width)
            let tx = rect.width / 2 - bounds.midX * scale
            let ty = rect.height / 2 - bounds.midY * scale

            var strokes = MarkGeometry.strokes(progress: locked ? 1 : 0)
            if locked, detail != .keyhole {
                strokes.removeLast()
            }

            cg.setStrokeColor(NSColor.black.cgColor)
            cg.setLineWidth(MarkGeometry.strokeWidth * scale)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                let path = CGMutablePath()
                path.addLines(between: stroke.map { CGPoint(x: $0.x * scale + tx, y: $0.y * scale + ty) })
                cg.addPath(path)
                cg.strokePath()
            }

            if locked, detail == .dot {
                let c = MarkGeometry.lockBodyCenter
                let r = MarkGeometry.strokeWidth * scale
                cg.setFillColor(NSColor.black.cgColor)
                cg.fillEllipse(in: CGRect(
                    x: c.x * scale + tx - r,
                    y: c.y * scale + ty - r,
                    width: 2 * r,
                    height: 2 * r,
                ))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dantrolene"
        cache[key] = image
        return image
    }
}
