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

enum WineScanner {

    // Unix-side wine binaries. Matched against the executable's base name.
    private static let loaderNames: Set<String> = [
        "wine", "wine64", "wine-preloader", "wine64-preloader",
        "wineloader", "wineloader64", "wineserver", "winedbg",
        "cxstart", "cxrun", "cxsetup", "cxdiag",
    ]

    // Windows-side processes that wine always brings up for itself.
    private static let serviceNames: Set<String> = [
        "services.exe", "plugplay.exe", "rpcss.exe", "svchost.exe",
        "winedevice.exe", "explorer.exe", "conhost.exe", "wineboot.exe",
        "winemenubuilder.exe", "start.exe", "rundll32.exe", "tabtip.exe",
        "sihost.exe", "dllhost.exe", "cmd.exe",
    ]

    /// Bundles that manage wine but are not themselves wine.
    private static func hostAppName(forExecutablePath path: String) -> String? {
        let lower = path.lowercased()
        for (marker, label) in [
            ("/crossover.app/contents/macos/", "CrossOver"),
            ("/wine stable.app/contents/macos/", "Wine Stable"),
            ("/wine devel.app/contents/macos/", "Wine Devel"),
            ("/wine staging.app/contents/macos/", "Wine Staging"),
            ("/whisky.app/contents/macos/", "Whisky"),
            ("/porting kit.app/contents/macos/", "Porting Kit"),
        ] where lower.contains(marker) {
            return label
        }
        return nil
    }

    // MARK: - Scanning

    static func scan() -> WineScan {
        var scan = WineScan()
        let me = getpid()
        let uid = getuid()
        var seenHosts = Set<String>()

        var pathBuffer = [CChar](repeating: 0, count: 4096)
        var argsBuffer = [CChar](repeating: 0, count: argMax())

        for proc in allProcesses() {
            let pid = proc.kp_proc.p_pid
            guard pid > 0, pid != me else { continue }
            guard proc.kp_eproc.e_ucred.cr_uid == uid else { continue }
            // Zombies still appear in the process table and still answer
            // kill(pid, 0); counting them would pin the badge above zero long
            // after the bottle is actually gone.
            guard proc.kp_proc.p_stat != SZOMB else { continue }

            let comm = commName(proc)
            let execPath = executablePath(pid, &pathBuffer)

            if let host = hostAppName(forExecutablePath: execPath) {
                if seenHosts.insert(host).inserted { scan.hosts.append(host) }
                continue
            }

            let lowerExec = execPath.lowercased()
            if let own = ownExecutable, lowerExec == own { continue }
            if let bundle = ownBundle, lowerExec.hasPrefix(bundle) { continue }

            guard looksLikeWine(comm: comm, execPath: execPath) else { continue }

            // Only now is it worth the (much more expensive) argv read, which is
            // what gives us the real, untruncated name and the Windows path.
            let args = processArguments(pid, &argsBuffer)
            let windowsPath = args.argv.first ?? ""
            let name = displayName(comm: comm, execPath: execPath, windowsPath: windowsPath)

            scan.processes.append(
                WineProcess(
                    pid: pid,
                    ppid: proc.kp_eproc.e_ppid,
                    name: name,
                    detail: windowsPath.isEmpty ? (args.execPath.isEmpty ? execPath : args.execPath) : windowsPath,
                    kind: classify(name)
                ))
        }

        scan.processes.sort {
            $0.kind == $1.kind
                ? ($0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame
                    ? $0.pid < $1.pid
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending)
                : $0.kind < $1.kind
        }
        scan.hosts.sort()
        return scan
    }

    /// Cheap first pass. `proc_pidpath` reports the wine loader image, which for
    /// every wine-hosted process lives either in a "winetemp-*" directory or
    /// inside the wine/CrossOver install, so the directory alone is a reliable
    /// marker even when the file name itself is stale.
    ///
    /// The markers are deliberately anchored rather than bare "wine" substring
    /// tests -- WineWatch's own path contains "winewatch", and so might yours.
    private static func looksLikeWine(comm: String, execPath: String) -> Bool {
        let path = execPath.lowercased()
        let base = (path as NSString).lastPathComponent
        let name = comm.lowercased()

        if isOwnProgram(base: base, comm: name) { return false }

        // Directory markers: where wine puts its loaders and prefixes.
        for marker in ["winetemp-", "/crossover.app/", "/crossover/", "/wine/", "/wineprefix",
                       "/dosdevices/", "/wineskin", "/whisky.app/", "/winehq"]
        where path.contains(marker) {
            return true
        }

        // Binary names, from the executable path or -- when that is unreadable --
        // from p_comm, which truncates at 16 characters.
        for candidate in [base, name] where !candidate.isEmpty {
            if loaderNames.contains(candidate) { return true }
            if candidate.hasPrefix("wine-") || candidate.hasPrefix("wine64") { return true }
            if candidate.hasSuffix(".exe") { return true }
        }
        return false
    }

    /// WineWatch itself, or another copy of it, is not a wine process.
    private static func isOwnProgram(base: String, comm: String) -> Bool {
        base.hasPrefix("winewatch") || comm.hasPrefix("winewatch")
    }

    private static let ownExecutable: String? =
        Bundle.main.executableURL?.resolvingSymlinksInPath().path.lowercased()

    private static let ownBundle: String? = {
        let path = Bundle.main.bundlePath.lowercased()
        return path.hasSuffix(".app") ? path + "/" : nil
    }()

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

    private static func classify(_ name: String) -> WineProcess.Kind {
        let lower = name.lowercased()
        if loaderNames.contains(lower) || lower.hasPrefix("wineserver") { return .server }
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

    // MARK: - sysctl / libproc plumbing

    private static func allProcesses() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
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

    private static func executablePath(_ pid: pid_t, _ buffer: inout [CChar]) -> String {
        buffer[0] = 0
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
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
