// WineGlassPath.swift
//
// The glass outline traced from the official Wine logo, WINE-logo.svg:
//   https://commons.wikimedia.org/wiki/File:WINE-logo.svg
//   Original image designed by Jon Parshall; SVG by Joel Holdsworth,
//   from wine.git/programs/winecfg/logo.svg.
//
// Because the control points below are derived from that artwork, THIS FILE
// ALONE is licensed under the LGPL, not under the MIT license that covers the
// rest of WineWatch (see LICENSE):
//
//   This library is free software; you can redistribute it and/or modify it
//   under the terms of the GNU Lesser General Public License as published by
//   the Free Software Foundation; either version 2.1 of the License, or (at
//   your option) any later version.
//
//   This library is distributed in the hope that it will be useful, but
//   WITHOUT ANY WARRANTY; without even the implied warranty of
//   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
//   General Public License for more details.
//
//   You should have received a copy of the GNU Lesser General Public License
//   along with this library; if not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: LGPL-2.1-or-later

import AppKit

/// The Wine glass as Bezier geometry, in its own normalised coordinate box.
/// Drawing, colouring and badging all live in `GlassIcon`, which is MIT — this
/// file is only the shape.
enum WineGlassPath {

    /// The traced outline's own bounding box, origin at the bottom-left.
    static let width: CGFloat = 10.63
    static let height: CGFloat = 18

    /// A tall flute tilted so the rim leans left over an offset, foreshortened
    /// foot. Traced from the logo's body outline (`path9863`) and foot ellipse
    /// (`ellipse9861`), with the group and ellipse transforms applied and the
    /// result normalised to the box above and flipped into AppKit's y-up space.
    ///
    /// Body and foot are kept separate and filled separately: they overlap at
    /// the stem, and a single non-zero fill would punch a hole there if the two
    /// subpaths happened to wind in opposite directions.
    static func body() -> NSBezierPath {
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

    static func foot() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 6.79, y: 2.08))
        path.curve(to: NSPoint(x: 3.33, y: 0.45), controlPoint1: NSPoint(x: 4.78, y: 1.69), controlPoint2: NSPoint(x: 3.23, y: 0.95))
        path.curve(to: NSPoint(x: 7.16, y: 0.25), controlPoint1: NSPoint(x: 3.43, y: -0.06), controlPoint2: NSPoint(x: 5.14, y: -0.15))
        path.curve(to: NSPoint(x: 10.63, y: 1.89), controlPoint1: NSPoint(x: 9.17, y: 0.65), controlPoint2: NSPoint(x: 10.73, y: 1.38))
        path.curve(to: NSPoint(x: 6.79, y: 2.08), controlPoint1: NSPoint(x: 10.53, y: 2.4), controlPoint2: NSPoint(x: 8.81, y: 2.48))
        path.close()
        return path
    }
}
