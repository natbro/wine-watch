# WineWatch

A macOS menu bar indicator for lingering Wine / CrossOver processes.

Shows the Wine glass with a badge counting the wine processes currently
running, so you can watch it drop to zero before changing a bottle's
configuration and relaunching — instead of running `ps aux | grep wine`.

- Menu bar only: no Dock icon, no window.
- Badge is **red** with a count while wine processes are running, and
  disappears (leaving a dimmed glass) once everything is gone.
- Refreshes every 3, 4, or 5 seconds, and every half second for a few seconds
  after a kill so the count tracks the teardown.
- Cheap enough to leave running: a sweep costs ~0.2ms on a 1300-process
  machine, and the status item is only redrawn when the count changes, so
  Activity Monitor reports no measurable energy impact.
- Requires macOS 14 or later.

## Build

```sh
make app        # builds .dist/WineWatch.app (arm64, ad-hoc signed)
make run        # builds and launches it
make install    # installs to /Applications and launches it
make universal  # arm64 + x86_64
```

Install to `/Applications` before turning on **Launch Automatically at
Startup** — `SMAppService` registers the app by its path, so a login item
pointing into `.dist/` breaks as soon as you `make clean`.

## The menu

| Item | What it does |
| --- | --- |
| *header* | Count of wine processes, and whether CrossOver itself is open |
| *process list* | Each running process with its pid; submenu offers Quit / Force Quit for that one process |
| **Close Wine Processes** | Everything: apps, Wine's services, then wineserver. `SIGTERM` first, `SIGKILL` for anything still alive after 2s. Hold ⌥ to go straight to `SIGKILL` |
| **Close Wine Services Only** | wineserver and Wine's own Windows services, leaving application processes alone |
| **Launch Automatically at Startup** | Login item, via `SMAppService` |
| **Update Every** | Refresh interval: 3, 4, or 5 seconds |
| **Show Green Badge When Clear** | Show a green `0` instead of no badge when nothing is running |

Processes are killed apps-first, wineserver-last — tearing down the server
first would just orphan everything above it.

## What counts as a wine process

A process owned by you (zombies excluded) whose executable path sits in a
`winetemp-*` directory, a wine prefix, or a wine/CrossOver install — or whose
name is a wine loader (`wineserver`, `wine64-preloader`, `wineloader`, …) or
ends in `.exe`.

Both `proc_pidpath` and `KERN_PROCARGS2` are consulted: wine rewrites `argv[0]`
to the Windows path (`C:\windows\system32\services.exe`), which gives the nice
display name, while the unix executable path is what reliably identifies the
process as wine-hosted.

The **CrossOver app itself is never counted and never killed** — it is the
thing you are quitting by hand, so it is listed for information only.

## Command line

The same binary works headlessly, which is handy from a terminal or a script:

```sh
WineWatch --list             # print what WineWatch would count
WineWatch --kill             # close every wine process
WineWatch --kill --force     # ... skipping the polite SIGTERM
WineWatch --kill-services    # close only wineserver and Wine's services
WineWatch --selftest         # build the menu headlessly, and check badge redraws
WineWatch --benchmark        # time a sweep, cold cache and warm
WineWatch --preview out.png 10   # render the status icon at 10x
```

Inside the repo, `make list` and `make preview` wrap the first and last.

## License

WineWatch is **MIT** licensed — see [LICENSE](LICENSE) — with one file excepted.

The status icon is a monochrome silhouette traced from the official Wine logo
([`WINE-logo.svg`](https://commons.wikimedia.org/wiki/File:WINE-logo.svg) on
Wikimedia Commons — original design by Jon Parshall, SVG by Joel Holdsworth,
from `wine.git/programs/winecfg/logo.svg`), which is **LGPL-2.1-or-later**.
Because the traced control points are derived from that artwork, they are kept
in their own file — `Sources/WineWatch/WineGlassPath.swift` — which is licensed
LGPL-2.1-or-later rather than MIT. Everything else, including all the drawing,
colouring and badging in `GlassIcon.swift`, is MIT.

WineWatch is not affiliated with or endorsed by the Wine project or WineHQ.

## Notes

The bundle is ad-hoc signed (`codesign -s -`). If macOS refuses the login item,
approve WineWatch in System Settings › General › Login Items; the menu offers to
open that pane when registration fails.
