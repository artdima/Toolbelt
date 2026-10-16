# Changelog

## 0.2.0

A new look for every window, in Light and Dark appearance alike.

- **Menu bar panel.** Tools are grouped into sections that fold away, with
  Settings… (⌘,) and Quit (⌘Q) at the bottom. It is readable in Light
  appearance again: the panel used to force light text over a light
  background. Delete Derived Data asks for confirmation inside the panel.
- **Settings.** Sections switch from the toolbar, the way macOS settings do,
  and changes are saved as you go — no Save buttons. Tool paths can be picked
  in Finder.
- **Weekly Report.** Hours per day as bars on an 8-hour scale; every issue
  shows its share of the week.
- **My Issues.** Search and the Resolved toggle moved to the toolbar; columns
  are marked by stage, cards show the priority and the deadline.
- **Tracker errors.** Weekly Report and My Issues explain what went wrong, with
  Retry and the technical details to copy, instead of the raw response.
- **Simulators.** An All / iPhone / iPad / Android filter; OS versions fold
  away and stay folded.
- **Deep Link.** The history remembers which device a link was opened on and
  when, and opens it again in one click.
- **User Defaults.** Works with the plist inside the app's own data container,
  the one the app actually reads. Copy and Delete show up on hover.
- **HTTP Request.** The history is a sidebar, a pasted `curl` command has a tab
  of its own, and a request in flight can be cancelled with ⌘.
- **Release Notes.** Commits are listed with checkboxes, and the draft is built
  from the ticked ones only.

## 0.1.1

- **The installer.** The DMG opens over a picture of its own: Toolbelt on the
  left, Applications on the right, an arrow between them.
- The app declares its category, Developer Tools, so Launchpad files it where
  it belongs.

## 0.1.0

The first tagged build, signed with Developer ID and notarized by Apple. Toolbelt
needs macOS 26.3 or later.

- **Git profiles.** `user.name` and `user.email` switched in one click; the
  profiles live in Settings.
- **Weekly Report.** A week of worklog from Yandex Tracker: totals by day on an
  8-hour scale, a breakdown by issue or by day, every entry expandable.
- **My Issues.** A kanban of your Tracker issues, columns are statuses.
- **Simulators.** iOS simulators and Android emulators launched and stopped
  without Xcode or Android Studio, grouped by OS version, their boot state
  polled live.
- **Deep Link.** A link opened on a booted iOS simulator or a connected Android
  device, with a pinned history.
- **User Defaults.** The UserDefaults of an app on a booted simulator, refreshed
  every two seconds; strings, numbers and booleans edited in place, keys deleted.
- **HTTP Request.** A pasted `curl` command turned into an editable request,
  sent, with the response below and a history on the side.
- **Release Notes.** "What's New" built from Conventional Commits, optionally
  rewritten by Claude CLI into one paragraph in the language of your choice.
- **Delete Derived Data.** One button, with a confirmation.

Not sandboxed on purpose: the app runs `git`, `xcrun`, `adb` and `claude`. The
`adb` and `claude` paths from Settings are checked against an allowlist of
directories before anything is executed.
