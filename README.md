<p align="center">
  <img src="AppIcon-1024.png" width="140" alt="Toolbelt">
</p>

<h1 align="center">Toolbelt</h1>

<p align="center">
  A belt of tools in the macOS menu bar — the ones a mobile developer reaches for every day.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26.3+-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 26.3+">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/UI-SwiftUI-1575F9?style=flat-square" alt="SwiftUI">
  <img src="https://img.shields.io/badge/dependencies-none-2EA043?style=flat-square" alt="No dependencies">
  <img src="https://img.shields.io/badge/license-MIT-8A8A8A?style=flat-square" alt="MIT">
</p>

## What's inside

| Tool | What it does |
|---|---|
| **Git profiles** | Switches `user.name` and `user.email` in one click |
| **Weekly report** | Pulls worklog from Yandex Tracker, totals by day and by issue |
| **My issues** | A kanban of your Tracker issues, columns are statuses |
| **Simulators** | Launches an iOS simulator or an Android emulator, and stops it |
| **Deep Link** | Opens a link on a booted iOS simulator or a connected Android device |
| **Release Notes** | Builds "What's New" from your commits, optionally rewritten by Claude CLI into one paragraph |
| **Derived Data** | Wipes the folder with one button |

## Build

```bash
open Toolbelt.xcodeproj      # Xcode 26+, macOS 26.3+
swift test                   # pure-logic tests, no Xcode needed
```

## Architecture

```
Toolbelt/
├── App/            entry point, menu bar panel, window registry
├── Core/           infrastructure: processes, windows, Keychain, logging
├── DesignSystem/   reusable views and formatters
├── Features/       one folder per tool: model → service → view model → view
└── Settings/       shared settings screen
Tests/              pure-logic tests
```

The rule that shapes everything: **a view never knows about transport**. It talks to an
`@Observable` view model, the view model talks to a protocol — `TrackerService`,
`GitConfigService`, `GitRepositoryReading`, `ReleaseNotesGenerating`, `DeepLinkOpening`,
`SimulatorControlling`, `DerivedDataCleaning` —
and the concrete implementation arrives through the initializer. That is also where
testability comes from: tests swap in a stub instead of the network and the shell.

All arithmetic lives outside the views, in plain value types: `WeekReport` (week
aggregation), `IssuesBoard` (status columns), `ReleaseNotesBuilder` (commit parsing),
`TrackerDuration` (ISO 8601). They are computed once after a load rather than on
every redraw, and they are what the tests cover.

## Decisions worth explaining

**Not sandboxed.** A developer tool runs `git`, `xcrun` and `adb` and reads
`~/Library/Developer` by definition. That rules out the App Store, so the sandbox is off
on purpose — not by omission.

**`Shell.run` hops to `Task.detached`.** With `SWIFT_APPROACHABLE_CONCURRENCY` on,
`NonisolatedNonsendingByDefault` comes with it: a `nonisolated async` function inherits
the caller's isolation. Marking it `nonisolated` alone would have kept the process wait
on the main thread.

**stdout and stderr are drained in parallel.** Read them one after the other and a child
that fills the second pipe blocks on write and never exits. A watchdog covers the rest:
a hung `adb` must not freeze the window forever.

**The emulator is launched detached, with its output in a file.** `Shell.run` waits for
the process and kills it on timeout — right for `simctl`, fatal for an emulator that runs
for hours and would eventually fill a pipe nobody drains. `Shell.launch` starts it, sends
stdout and stderr to a file, and watches the first seconds: a broken AVD or a system image
of the wrong architecture dies at once, and that reason is worth showing.

**The `adb` path is validated on every read.** It comes from `UserDefaults`, and that
plist is writable by any process running as the user. Without a directory allowlist a
tampered preference would mean arbitrary code execution under a signed app.

**Claude CLI runs without tools.** Commit subjects come from a repository you may not
have written, and they go straight into the prompt. With `--disallowedTools "*"` the worst
they can do is change the wording. The `claude` path is validated the same way as `adb`.

**claude gets the login shell's environment.** An app started by launchd never sees what
`~/.zshrc` exports — `PATH`, proxies, `CLAUDE_CONFIG_DIR`. Without them claude looks for
credentials in the wrong place or cannot refresh its token, so `$SHELL -l -i` is asked once
and its environment is cached.

**git runs with `core.fsmonitor=false` and `core.hooksPath=/dev/null`.** git reads the
config of whatever repository it opens, and both of those hooks can launch external
commands — for a repository you did not write, that is code execution.

**One source of truth for credentials.** `TrackerCredentialsStore` is the only place that
knows about Keychain and `UserDefaults`; the UI and the network client both read from it.

## Tests

`swift test` compiles the SwiftUI-free files out of `Toolbelt/` into a `ToolbeltCore`
module and runs Swift Testing suites against it. The Xcode project is untouched — it
builds the same folder as a whole through `PBXFileSystemSynchronizedRootGroup`.

Covered: Conventional Commits parsing, ISO 8601 durations in Tracker's "working" days,
week boundaries, report aggregation, board column ordering, `simctl`, `emulator` and `adb`
output parsing, argument quoting for `adb shell`, the Claude prompt, HTTP status mapping and pluralization.

## Known limitations

- Tracker responses are decoded on the main actor; with a thousand entries that is tens
  of milliseconds. Moving it off requires marking the domain models `nonisolated`.
- Worklog is fetched as a single 1000-entry page — hitting the limit logs a warning, but
  there is no pagination.
- The UI is English only; there is no localization layer.

## License

MIT — take it and use it.
