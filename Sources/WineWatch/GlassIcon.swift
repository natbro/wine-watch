import AppKit

/// Draws the status-bar icon: a monochrome wine-glass silhouette with an
/// optional count badge in its top-right corner.
enum GlassIcon {

    static let height: CGFloat = 18
    private static let glassWidth: CGFloat = 10.63
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

    /// The Wine project's glass: a tall flute tilted so the rim leans left over
    /// an offset, foreshortened foot. Traced from the outline and foot ellipse
    /// of the official logo (WINE-logo.svg, Wikimedia Commons), normalised to a
    /// 10.63 x 18 box with the origin at the bottom-left.
    ///
    /// Body and foot are kept as separate paths and filled separately: they
    /// overlap at the stem, and a single non-zero fill would punch a hole there
    /// if the two subpaths happened to wind in opposite directions.
    private static func glassBodyPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 6.74, y: 1.36))
        path.curve(to: NSPoint(x: 7.99, y: 2.18), controlPoint1: NSPoint(x: 7.15, y: 1.46), controlPoint2: NSPoint(x: 7.73, y: 1.79))
        path.curve(to: NSPoint(x: 6.17, y: 5.76), controlPoint1: NSPoint(x: 6.43, y: 2.8), controlPoint2: NSPoint(x: 6.38, y: 4.47))
        path.line(to: NSPoint(x: 6.19, y: 6.06))
        path.curve(to: NSPoint(x: 6.96, y: 7.85), controlPoint1: NSPoint(x: 6.28, y: 6.47), controlPoint2: NSPoint(x: 6.7, y: 7.4))
        path.curve(to: NSPoint(x: 6.06, y: 17.65), controlPoint1: NSPoint(x: 8.17, y: 9.94), controlPoint2: NSPoint(x: 6.97, y: 14.1))
        path.curve(to: NSPoint(x: 0.0, y: 16.25), controlPoint1: NSPoint(x: 5.07, y: 18.55), controlPoint2: NSPoint(x: 0.8, y: 17.58))
        path.curve(to: NSPoint(x: 3.53, y: 7.18), controlPoint1: NSPoint(x: 0.64, y: 13.85), controlPoint2: NSPoint(x: 1.52, y: 9.06))
        path.curve(to: NSPoint(x: 5.23, y: 5.85), controlPoint1: NSPoint(x: 3.98, y: 6.76), controlPoint2: NSPoint(x: 4.62, y: 6.59))
        path.line(to: NSPoint(x: 5.37, y: 5.61))
        path.curve(to: NSPoint(x: 5.47, y: 1.69), controlPoint1: NSPoint(x: 5.84, y: 4.31), controlPoint2: NSPoint(x: 6.44, y: 2.64))
        path.curve(to: NSPoint(x: 6.74, y: 1.37), controlPoint1: NSPoint(x: 5.8, y: 1.43), controlPoint2: NSPoint(x: 6.33, y: 1.27))
        path.close()
        return path
    }

    private static func glassFootPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 6.79, y: 2.08))
        path.curve(to: NSPoint(x: 3.33, y: 0.45), controlPoint1: NSPoint(x: 4.78, y: 1.69), controlPoint2: NSPoint(x: 3.23, y: 0.95))
        path.curve(to: NSPoint(x: 7.16, y: 0.25), controlPoint1: NSPoint(x: 3.43, y: -0.06), controlPoint2: NSPoint(x: 5.14, y: -0.15))
        path.curve(to: NSPoint(x: 10.63, y: 1.89), controlPoint1: NSPoint(x: 9.17, y: 0.65), controlPoint2: NSPoint(x: 10.73, y: 1.38))
        path.curve(to: NSPoint(x: 6.79, y: 2.08), controlPoint1: NSPoint(x: 10.53, y: 2.4), controlPoint2: NSPoint(x: 8.81, y: 2.48))
        path.close()
        return path
    }

    /// Fills both paths as one group. Body and foot overlap at the stem, so
    /// filling them separately at less than full alpha would double-darken the
    /// overlap; a transparency layer applies the alpha to the composite.
    private static func fillGlass(alpha: CGFloat = 1) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        glassBodyPath().fill()
        glassFootPath().fill()
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
