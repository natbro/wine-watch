import AppKit

/// Command-line modes, useful for checking detection without the menu bar and
/// for generating the app icon at build time.
switch CommandLine.arguments.dropFirst().first {
case "--list", "-l":
    let scan = WineScanner.shared.scan()
    for host in scan.hosts { print("[host]    \(host)") }
    for process in scan.processes {
        print(String(format: "%-8s %-6d %-28s %@",
                     ("[\(process.kind)]" as NSString).utf8String!,
                     process.pid,
                     (process.name as NSString).utf8String!,
                     process.detail))
    }
    print("\(scan.count) wine process(es)")
    exit(0)

case "--export-icon":
    guard let directory = CommandLine.arguments.dropFirst(2).first else {
        FileHandle.standardError.write(Data("usage: WineWatch --export-icon <dir.iconset>\n".utf8))
        exit(2)
    }
    let iconset = URL(fileURLWithPath: directory)
    try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for entry in GlassIcon.iconsetEntries {
        let image = GlassIcon.appIcon(size: entry.pixels)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { continue }
        try? png.write(to: iconset.appendingPathComponent(entry.name))
    }
    exit(0)

case "--preview":
    // Development aid: renders the status icon at 10x onto light and dark
    // strips so the silhouette and badge can be checked without a menu bar.
    let output = CommandLine.arguments.dropFirst(2).first ?? "winewatch-preview.png"
    let counts: [Int?] = [nil, 0, 1, 3, 12, 137]
    let scale = CGFloat(Double(CommandLine.arguments.dropFirst(3).first ?? "") ?? 10)
    let pad: CGFloat = 6
    let cell = NSSize(width: 34 * scale, height: GlassIcon.height * scale)
    let size = NSSize(
        width: cell.width * CGFloat(counts.count) + pad * 2,
        height: cell.height * 2 + pad * 3)

    let sheet = NSImage(size: size, flipped: false) { _ in
        for (row, appearance) in [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!].enumerated() {
            let y = pad + (cell.height + pad) * CGFloat(1 - row)
            let strip = NSRect(x: pad, y: y, width: size.width - pad * 2, height: cell.height)
            (row == 0 ? NSColor.white : NSColor.black).setFill()
            strip.fill()
            appearance.performAsCurrentDrawingAppearance {
                for (column, count) in counts.enumerated() {
                    let image = GlassIcon.image(
                        count: count,
                        color: (count ?? 0) > 0 ? .systemRed : .systemGreen,
                        dimmed: (count ?? 0) == 0)
                    image.draw(
                        in: NSRect(
                            x: pad + cell.width * CGFloat(column),
                            y: y,
                            width: image.size.width * scale,
                            height: image.size.height * scale))
                }
            }
        }
        return true
    }
    if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
       let png = bitmap.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: output))
        print(output)
    }
    exit(0)

case "--kill", "--kill-services":
    let servicesOnly = CommandLine.arguments.contains("--kill-services")
    let force = CommandLine.arguments.contains("--force")
    let scan = WineScanner.shared.scan()
    let targets = servicesOnly ? scan.services : scan.processes
    guard !targets.isEmpty else {
        print("nothing to close")
        exit(0)
    }
    print("closing \(targets.count) process(es)\(force ? " (SIGKILL)" : "")…")
    let forced = WineScanner.terminate(targets, force: force)
    Thread.sleep(forTimeInterval: 0.3)  // let the kernel reap before reporting
    for target in targets {
        let outcome = target.isAlive
            ? "still running (not permitted?)"
            : (forced.contains(target.pid) ? "force quit" : "quit")
        print("  \(target.name) (\(target.pid)) — \(outcome)")
    }
    exit(0)

case "--benchmark":
    print(WineScanner.benchmark())
    exit(0)

case "--selftest":
    // Exercises menu construction headlessly; a menu bar app that crashes on
    // first click is not much of an improvement over `ps aux | grep wine`.
    _ = NSApplication.shared
    let delegate = AppDelegate()
    delegate.dumpMenu()
    print("")
    delegate.dumpBadgeBehaviour()
    exit(0)

case "--version", "-v":
    print("WineWatch \(WineWatchVersion.current)")
    exit(0)

case "--help", "-h":
    print("""
    WineWatch — menu bar indicator for lingering Wine / CrossOver processes.

      (no arguments)        run the menu bar app
      --version, -v         print the version
      --list, -l            print the wine processes WineWatch would count
      --kill [--force]      close every wine process (SIGTERM, then SIGKILL)
      --kill-services       close only wineserver and Wine's own services
      --export-icon <dir>   write app icon PNGs into an .iconset directory
    """)
    exit(0)

default:
    break
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
