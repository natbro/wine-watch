/// The one place the version is written down. `make app` stamps it into the
/// bundle's Info.plist, so the app, `--version` and the Homebrew formula's
/// test can never drift apart.
enum WineWatchVersion {
    static let current = "0.1.0"
}
