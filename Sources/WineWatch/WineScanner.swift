import Darwin
import Foundation

/// One wine-hosted process on the machine.
struct WineProcess: Hashable {
    enum Kind: Int, Comparable {
        /// A real Windows application: the game, its launcher, helpers.
        case app = 0
        /// Wine's own Windows-side plumbing: services.exe, plugplay.exe, ...
        case service = 1
        /// wineserver and the unix-side loaders that host everything else.
        case server = 2

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    let pid: pid_t
    let ppid: pid_t
    /// Short name shown in the menu, e.g. "services.exe".
    let name: String
    /// Longer context for the tooltip: the Windows-side argv[0] when we have it.
    let detail: String
    let kind: Kind

    var isAlive: Bool { kill(pid, 0) == 0 || errno == EPERM }

    /// A process keeps its identity when its parent dies and it is reparented
    /// to launchd, so the cached entry is reused with the fresh ppid.
    func reparented(to ppid: pid_t) -> WineProcess {
        WineProcess(pid: pid, ppid: ppid, name: name, detail: detail, kind: kind)
    }
}

/// Result of one sweep of the process table.
struct WineScan {
    var processes: [WineProcess] = []
    /// The CrossOver / Wine GUI apps themselves. Never counted, never killed --
    /// they are the thing you are quitting by hand, not a leftover.
    var hosts: [String] = []

    var count: Int { processes.count }
    var services: [WineProcess] { processes.filter { $0.kind != .app } }
    var apps: [WineProcess] { processes.filter { $0.kind == .app } }
}

/// Sweeps the process table for wine-hosted processes.
///
/// This runs every few seconds forever, so it is written to do as little as
/// possible in the steady state. Two things keep it cheap:
///
/// 1. **Identity caching.** A process cannot change what it is, so each one is
///    classified once and the verdict is remembered against its (pid, start
///    time) identity. A quiet machine therefore does no per-process work at
///    all after the first sweep -- just one `sysctl` and a dictionary lookup
///    per process.
/// 2. **Byte matching.** Classification compares raw C strings with
///    `strcasestr` / `strcasecmp` rather than building Swift `String`s and
///    using `lowercased()` and `contains`. Those are Unicode-correct and
///    accordingly slow: on a 1300-process machine they cost ~30ms per sweep,
///    which is most of a menu bar app's entire energy budget.
final class WineScanner {

    /// One scanner per process; it owns the classification cache.
    static let shared = WineScanner()

    /// Identifies a process across sweeps. The start time is what makes this
    /// safe -- pids are recycled, and a recycled pid is a different program.
    private struct Identity: Hashable {
        let pid: pid_t
        let startSeconds: Int
        let startMicroseconds: Int32

        init(_ proc: kinfo_proc) {
            pid = proc.kp_proc.p_pid
            startSeconds = proc.kp_proc.p_starttime.tv_sec
            startMicroseconds = proc.kp_proc.p_starttime.tv_usec
        }
    }

    private enum Verdict {
        case ignored
        case host(String)
        case wine(WineProcess)
    }

    /// What the byte-level matching can decide on its own, before anything is
    /// allocated. Naming a wine process needs its argv, so that is left to
    /// `classify`, which can afford Swift strings for the handful of matches.
    private enum Match {
        case ignored
        case host(String)
        case wine
    }

    private var known: [Identity: Verdict] = [:]
    private let lock = NSLock()

    private var pathBuffer = [CChar](repeating: 0, count: 4096)
    /// Allocated on first use: a machine that never runs wine never pays for it.
    private lazy var argsBuffer = [CChar](repeating: 0, count: WineScanner.argMax())

    // MARK: - Scanning

    func scan() -> WineScan {
        lock.lock()
        defer { lock.unlock() }

        var result = WineScan()
        let me = getpid()
        var seenHosts = Set<String>()

        // Rebuilt rather than mutated, which prunes dead processes for free.
        var live: [Identity: Verdict] = [:]
        live.reserveCapacity(known.count + 16)

        for proc in Self.processesForCurrentUser() {
            let pid = proc.kp_proc.p_pid
            guard pid > 0, pid != me else { continue }
            // Zombies still appear in the process table and still answer
            // kill(pid, 0); counting them would pin the badge above zero long
            // after the bottle is actually gone.
            guard proc.kp_proc.p_stat != SZOMB else { continue }

            let identity = Identity(proc)
            let verdict = known[identity] ?? classify(proc, pid: pid)
            live[identity] = verdict

            switch verdict {
            case .ignored:
                break
            case .host(let name):
                if seenHosts.insert(name).inserted { result.hosts.append(name) }
            case .wine(let process):
                result.processes.append(process.reparented(to: proc.kp_eproc.e_ppid))
            }
        }

        known = live

        result.processes.sort {
            $0.kind == $1.kind
                ? ($0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame
                    ? $0.pid < $1.pid
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending)
                : $0.kind < $1.kind
        }
        result.hosts.sort()
        return result
    }

    /// Everything expensive happens here, and only once per process.
    private func classify(_ proc: kinfo_proc, pid: pid_t) -> Verdict {
        var proc = proc

        pathBuffer[0] = 0
        _ = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))

        let match: Match = pathBuffer.withUnsafeBufferPointer { buffer in
            let path = buffer.baseAddress!
            return withUnsafePointer(to: &proc.kp_proc.p_comm) { tuple in
                tuple.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { comm in
                    Self.match(path: path, comm: comm)
                }
            }
        }

        // A wine process still needs its argv read for a usable name; that is
        // the one remaining expensive call, and it runs for matches only.
        switch match {
        case .ignored: return .ignored
        case .host(let label): return .host(label)
        case .wine: break
        }

        let execPath = String(cString: pathBuffer)
        let comm = Self.commName(proc)
        let args = Self.processArguments(pid, &argsBuffer)
        let windowsPath = args.argv.first ?? ""
        let name = Self.displayName(comm: comm, execPath: execPath, windowsPath: windowsPath)

        return .wine(
            WineProcess(
                pid: pid,
                ppid: proc.kp_eproc.e_ppid,
                name: name,
                detail: windowsPath.isEmpty ? (args.execPath.isEmpty ? execPath : args.execPath) : windowsPath,
                kind: Self.kind(of: name)))
    }

    // MARK: - Matching
    //
    // All of this works on NUL-terminated C strings: `path` from proc_pidpath
    // and `comm` pointing straight into the kinfo_proc. Nothing here allocates.

    private static func match(path: UnsafePointer<CChar>, comm: UnsafePointer<CChar>) -> Match {
        for host in hostMarkers where contains(path, host.marker) {
            return .host(host.label)
        }
        if let own = ownExecutablePath, equals(path, own) { return .ignored }
        if let bundle = ownBundlePrefix, hasPrefix(path, bundle) { return .ignored }
        return looksLikeWine(path: path, comm: comm) ? .wine : .ignored
    }

    /// `proc_pidpath` reports the wine loader image, which for every
    /// wine-hosted process lives either in a "winetemp-*" directory or inside
    /// the wine/CrossOver install, so the directory alone is a reliable marker
    /// even when the file name itself is stale.
    ///
    /// The markers are deliberately anchored rather than bare "wine" substring
    /// tests -- WineWatch's own path contains "winewatch", and so might yours.
    private static func looksLikeWine(path: UnsafePointer<CChar>, comm: UnsafePointer<CChar>) -> Bool {
        let base = baseName(path)
        // WineWatch itself, or another copy of it, is not a wine process.
        if hasPrefix(base, ownNamePrefix) || hasPrefix(comm, ownNamePrefix) { return false }

        for marker in pathMarkers where contains(path, marker) { return true }

        // Binary names, from the executable path or -- when that is unreadable
        // -- from p_comm, which truncates at 16 characters.
        return isWineBinaryName(base) || isWineBinaryName(comm)
    }

    private static func isWineBinaryName(_ name: UnsafePointer<CChar>) -> Bool {
        guard name.pointee != 0 else { return false }
        for loader in loaderNames where equals(name, loader) { return true }
        if hasPrefix(name, winePrefix) || hasPrefix(name, wine64Prefix) { return true }
        return hasSuffix(name, exeSuffix)
    }

    // MARK: - C string helpers

    /// Interned for the process lifetime: these are compared thousands of times
    /// a minute, and converting a Swift literal at each call would defeat the
    /// point of matching on bytes.
    private static func intern(_ string: String) -> UnsafePointer<CChar> {
        UnsafePointer(strdup(string)!)
    }

    private static func contains(_ haystack: UnsafePointer<CChar>, _ needle: UnsafePointer<CChar>) -> Bool {
        strcasestr(haystack, needle) != nil
    }

    private static func equals(_ a: UnsafePointer<CChar>, _ b: UnsafePointer<CChar>) -> Bool {
        strcasecmp(a, b) == 0
    }

    private static func hasPrefix(_ string: UnsafePointer<CChar>, _ prefix: UnsafePointer<CChar>) -> Bool {
        strncasecmp(string, prefix, strlen(prefix)) == 0
    }

    private static func hasSuffix(_ string: UnsafePointer<CChar>, _ suffix: UnsafePointer<CChar>) -> Bool {
        let length = strlen(string), suffixLength = strlen(suffix)
        guard length >= suffixLength else { return false }
        return strcasecmp(string + length - suffixLength, suffix) == 0
    }

    private static func baseName(_ path: UnsafePointer<CChar>) -> UnsafePointer<CChar> {
        guard let slash = strrchr(path, Int32(UInt8(ascii: "/"))) else { return path }
        return UnsafePointer(slash).advanced(by: 1)
    }

    // MARK: - Markers

    /// Bundles that manage wine but are not themselves wine.
    private static let hostMarkers: [(marker: UnsafePointer<CChar>, label: String)] = [
        ("/crossover.app/contents/macos/", "CrossOver"),
        ("/wine stable.app/contents/macos/", "Wine Stable"),
        ("/wine devel.app/contents/macos/", "Wine Devel"),
        ("/wine staging.app/contents/macos/", "Wine Staging"),
        ("/whisky.app/contents/macos/", "Whisky"),
        ("/porting kit.app/contents/macos/", "Porting Kit"),
    ].map { (intern($0.0), $0.1) }

    /// Directory markers: where wine puts its loaders and prefixes.
    private static let pathMarkers: [UnsafePointer<CChar>] = [
        "winetemp-", "/crossover.app/", "/crossover/", "/wine/", "/wineprefix",
        "/dosdevices/", "/wineskin", "/whisky.app/", "/winehq",
    ].map(intern)

    /// Unix-side wine binaries, matched against the executable's base name.
    private static let loaderNamesText: Set<String> = [
        "wine", "wine64", "wine-preloader", "wine64-preloader",
        "wineloader", "wineloader64", "wineserver", "winedbg",
        "cxstart", "cxrun", "cxsetup", "cxdiag",
    ]
    private static let loaderNames: [UnsafePointer<CChar>] = loaderNamesText.map(intern)

    /// Windows-side processes that wine always brings up for itself.
    private static let serviceNames: Set<String> = [
        "services.exe", "plugplay.exe", "rpcss.exe", "svchost.exe",
        "winedevice.exe", "explorer.exe", "conhost.exe", "wineboot.exe",
        "winemenubuilder.exe", "start.exe", "rundll32.exe", "tabtip.exe",
        "sihost.exe", "dllhost.exe", "cmd.exe",
    ]

    private static let exeSuffix = intern(".exe")
    private static let winePrefix = intern("wine-")
    private static let wine64Prefix = intern("wine64")
    private static let ownNamePrefix = intern("winewatch")

    private static let ownExecutablePath: UnsafePointer<CChar>? =
        Bundle.main.executableURL.map { intern($0.resolvingSymlinksInPath().path) }

    private static let ownBundlePrefix: UnsafePointer<CChar>? = {
        let path = Bundle.main.bundlePath
        return path.hasSuffix(".app") ? intern(path + "/") : nil
    }()

    // MARK: - Naming

    private static func displayName(comm: String, execPath: String, windowsPath: String) -> String {
        // The Windows-side argv[0] ("C:\windows\system32\services.exe") is the
        // most faithful name; fall back through the unix paths.
        if !windowsPath.isEmpty {
            let base = windowsPath.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init)
            if let base, !base.isEmpty { return base }
        }
        let execBase = (execPath as NSString).lastPathComponent
        if !execBase.isEmpty, execBase.count > comm.count { return execBase }
        return comm
    }

    private static func kind(of name: String) -> WineProcess.Kind {
        let lower = name.lowercased()
        if loaderNamesText.contains(lower) || lower.hasPrefix("wineserver") { return .server }
        if serviceNames.contains(lower) { return .service }
        return .app
    }

    // MARK: - Killing

    /// Politely ask, then insist. Returns the pids that were still alive after
    /// the grace period and had to be forced.
    @discardableResult
    static func terminate(_ processes: [WineProcess], force: Bool = false, grace: TimeInterval = 2.0) -> [pid_t] {
        // Apps first, then wine's services, then the server that hosts them --
        // tearing the server down first would just orphan everything above it.
        let ordered = processes.sorted { $0.kind < $1.kind }
        let signal = force ? SIGKILL : SIGTERM
        for proc in ordered { _ = kill(proc.pid, signal) }
        guard !force else { return ordered.map(\.pid) }

        Thread.sleep(forTimeInterval: grace)

        let survivors = ordered.filter(\.isAlive)
        for proc in survivors { _ = kill(proc.pid, SIGKILL) }
        return survivors.map(\.pid)
    }

    // MARK: - Benchmarking

    /// Times a sweep cold (nothing cached, as at launch) and warm (the steady
    /// state, which is what actually runs all day). Used by `--benchmark`.
    static func benchmark(iterations: Int = 20) -> String {
        func time(_ n: Int, _ work: () -> Void) -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<n { work() }
            return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(n) / 1_000_000
        }

        let scanner = WineScanner()
        let all = processesForCurrentUser()
        let found = scanner.scan()

        let tList = time(iterations) { _ = processesForCurrentUser() }
        let tCold = time(iterations) {
            scanner.lock.lock()
            scanner.known.removeAll(keepingCapacity: true)
            scanner.lock.unlock()
            _ = scanner.scan()
        }
        let tWarm = time(iterations) { _ = scanner.scan() }

        return """
        \(all.count) processes for this user, \(found.count) wine, \(found.hosts.count) host app(s)

          sysctl KERN_PROC_UID      \(String(format: "%7.3f", tList)) ms
          scan(), cold cache        \(String(format: "%7.3f", tCold)) ms
          scan(), warm cache        \(String(format: "%7.3f", tWarm)) ms
        """
    }

    // MARK: - sysctl / libproc plumbing

    /// Filtered by the kernel rather than by us: on a busy machine a third of
    /// the process table belongs to root and never needs to cross into
    /// userspace at all.
    private static func processesForCurrentUser() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = procs.count * stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return Array(procs.prefix(size / stride))
    }

    private static func commName(_ proc: kinfo_proc) -> String {
        var copy = proc
        return withUnsafePointer(to: &copy.kp_proc.p_comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
        }
    }

    private static func argMax() -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0, value > 0 else { return 256 * 1024 }
        return Int(value)
    }

    private static func processArguments(_ pid: pid_t, _ buffer: inout [CChar]) -> (execPath: String, argv: [String]) {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var length = buffer.count
        guard sysctl(&mib, 3, &buffer, &length, nil, 0) == 0, length > MemoryLayout<Int32>.size else {
            return ("", [])
        }

        var argc: Int32 = 0
        memcpy(&argc, buffer, MemoryLayout<Int32>.size)
        var offset = MemoryLayout<Int32>.size

        func next() -> String {
            let start = offset
            while offset < length && buffer[offset] != 0 { offset += 1 }
            let string = buffer[start..<offset].withUnsafeBufferPointer {
                String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            while offset < length && buffer[offset] == 0 { offset += 1 }
            return string
        }

        let execPath = next()
        var argv: [String] = []
        for _ in 0..<max(0, argc) {
            guard offset < length else { break }
            argv.append(next())
        }
        return (execPath, argv)
    }
}
