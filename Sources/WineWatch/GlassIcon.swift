import AppKit

/// Draws the status-bar icon: a monochrome wine-glass silhouette with an
/// optional count badge in its top-right corner. The glass geometry itself
/// lives in `WineGlassPath`, which carries its own (LGPL) license.
enum GlassIcon {

    static let height: CGFloat = WineGlassPath.height
    private static let glassWidth: CGFloat = WineGlassPath.width
    private static let badgeHeight: CGFloat = 11
    private static let badgeOverlap: CGFloat = 2  // how far the badge sits over the glass

    /// - Parameters:
    ///   - count: number to show in the badge; `nil` draws the bare glass.
    ///   - color: badge fill.
    ///   - dimmed: draws the glass at reduced contrast, for the idle state.
    static func image(count: Int?, color: NSColor, dimmed: Bool) -> NSImage {
        let label = count.map(badgeText)
        let badgeWidth = label.map(badgeWidth) ?? 0
        let width = label == nil ? glassWidth : glassWidth - badgeOverlap + badgeWidth

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            // Resolved at draw time, so the icon follows the menu bar's
            // light/dark appearance without any explicit observation.
            NSColor.labelColor.setFill()
            fillGlass(alpha: dimmed ? 0.55 : 1.0)

            if let label {
                drawBadge(label, width: badgeWidth, color: color)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = count.map { "\($0) wine processes" } ?? "No wine processes"
        return image
    }

    private static func badgeText(_ count: Int) -> String {
        count > 99 ? "99+" : String(count)
    }

    private static func badgeFont() -> NSFont {
        .monospacedDigitSystemFont(ofSize: 9, weight: .bold)
    }

    private static func badgeWidth(for label: String) -> CGFloat {
        let text = label.size(withAttributes: [.font: badgeFont()]).width
        return max(badgeHeight, ceil(text) + 5)
    }

    private static func drawBadge(_ label: String, width: CGFloat, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let rect = NSRect(
            x: glassWidth - badgeOverlap,
            y: height - badgeHeight,
            width: width,
            height: badgeHeight)
        let capsule = NSBezierPath(roundedRect: rect, xRadius: badgeHeight / 2, yRadius: badgeHeight / 2)

        // Punch a thin gap out of the glass so the badge reads as a separate
        // element instead of merging into the silhouette.
        context.saveGState()
        context.setBlendMode(.clear)
        capsule.lineWidth = 2.5
        capsule.stroke()
        context.restoreGState()

        color.setFill()
        capsule.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: badgeFont(),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2 + 0.5),
            withAttributes: attributes)
    }

    /// Fills the glass as one group. Body and foot overlap at the stem, so
    /// filling them separately at less than full alpha would double-darken the
    /// overlap; a transparency layer applies the alpha to the composite.
    private static func fillGlass(alpha: CGFloat = 1) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        WineGlassPath.body().fill()
        WineGlassPath.foot().fill()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    // MARK: - App icon

    /// The same glass on a rounded slab, for the .icns / Finder / Login Items.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            // macOS draws app icons with a margin inside their canvas.
            let inset = size * 0.09
            let slab = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
            let corner = slab.width * 0.225

            let background = NSBezierPath(roundedRect: slab, xRadius: corner, yRadius: corner)
            background.addClip()
            NSGradient(
                colors: [
                    NSColor(calibratedRed: 0.24, green: 0.23, blue: 0.27, alpha: 1),
                    NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.10, alpha: 1),
                ])?.draw(in: slab, angle: -90)

            let glassHeight = slab.height * 0.72
            let scale = glassHeight / height
            let transform = NSAffineTransform()
            transform.translateX(
                by: slab.midX - (glassWidth * scale) / 2,
                yBy: slab.midY - glassHeight / 2)
            transform.scale(by: scale)
            transform.concat()

            NSColor.white.setFill()
            fillGlass()
            return true
        }
    }

    /// The file names `iconutil` expects inside an .iconset directory, paired
    /// with the pixel size each one is rendered at.
    static var iconsetEntries: [(name: String, pixels: CGFloat)] {
        [16, 32, 128, 256, 512].flatMap { base -> [(String, CGFloat)] in
            [("icon_\(base)x\(base).png", CGFloat(base)),
             ("icon_\(base)x\(base)@2x.png", CGFloat(base * 2))]
        }
    }
}
