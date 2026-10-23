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
  <img src="https://img.shields.io/badge/dependencies-MCP%20Swift%20SDK-2EA043?style=flat-square" alt="One dependency: the MCP Swift SDK">
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
| **User Defaults** | Shows an app's UserDefaults on a booted simulator, live; strings, numbers and booleans can be edited in place |
| **HTTP Request** | Turns a pasted `curl` command into an editable request, sends it and shows the response — a pocket Postman |
| **Release Notes** | Builds "What's New" from your commits, optionally rewritten by Claude CLI into one paragraph |
| **Derived Data** | Wipes the folder with one button |
| **MCP** | A local MCP server for Claude: it keeps your tokens in Keychain and lets Claude read GitLab pipelines, job logs and merge requests, and post to LinkedIn as you |

## Install

Download `Toolbelt-<version>.dmg` from the
[latest release](https://github.com/artdima/Toolbelt/releases/latest), open it and drag
Toolbelt to Applications. It needs macOS 26.3 or later, and it is signed with Developer ID
and notarized by Apple.

## Build

```bash
open Toolbelt.xcodeproj      # Xcode 26+, macOS 26.3+
swift test                   # pure-logic tests, no Xcode needed
```

## Release

`scripts/release.sh` builds a release at `build/release`: the app signed with Developer ID
and notarized, inside a signed and notarized `Toolbelt-<version>.dmg`. Once, on the Mac that
builds:

- a *Developer ID Application* certificate: Xcode → Settings → Accounts → Manage
  Certificates → **+** → Developer ID Application;
- a notarytool profile with an [app-specific password](https://account.apple.com):
  `xcrun notarytool store-credentials toolbelt --apple-id <Apple ID> --team-id <Team ID>`
  (`NOTARY_PROFILE` names another profile).

Then, for every release:

1. Add a `## X.Y.Z` section to `CHANGELOG.md`, set `MARKETING_VERSION` in the project to
   `X.Y.Z`, commit.
2. `scripts/release.sh` — the DMG and its SHA-256 are printed at the end.
3. Tag the commit and publish the DMG with the changelog section as the notes:

   ```bash
   git tag -a vX.Y.Z -m "Toolbelt X.Y.Z" && git push origin vX.Y.Z
   gh release create vX.Y.Z build/release/Toolbelt-X.Y.Z.dmg --title "Toolbelt X.Y.Z" \
     --notes-file <(awk '/^## /{ p = ($0 == "## X.Y.Z") } p && !/^## /' CHANGELOG.md)
   ```

## Architecture

```
Toolbelt/
├── App/            entry point, menu bar panel, window registry
├── Core/           infrastructure: processes, windows, Keychain, logging
├── DesignSystem/   reusable views and formatters
├── Features/       one folder per tool: model → service → view model → view
└── Settings/       shared settings screen
toolbelt-mcp/       the stdio relay Claude starts; copied into Toolbelt.app/Contents/MacOS
Tests/              pure-logic tests
```

The rule that shapes everything: **a view never knows about transport**. It talks to an
`@Observable` view model, the view model talks to a protocol — `TrackerService`,
`GitConfigService`, `GitRepositoryReading`, `ReleaseNotesGenerating`, `DeepLinkOpening`,
`SimulatorControlling`, `UserDefaultsControlling`, `DerivedDataCleaning`, `HTTPRequestSending` —
and the concrete implementation arrives through the initializer. That is also where
testability comes from: tests swap in a stub instead of the network and the shell.

All arithmetic lives outside the views, in plain value types: `WeekReport` (week
aggregation), `IssuesBoard` (status columns), `ReleaseNotesBuilder` (commit parsing),
`TrackerDuration` (ISO 8601), `CurlParser` and `CurlBuilder` (curl commands in and out),
`JSONPretty` (response formatting), `UserDefaultsParsing` (`listapps` and exported domains). They are computed once after a load rather than on
every redraw, and they are what the tests cover.

## MCP for Claude

Toolbelt is a local MCP server. Claude Desktop and Claude Code start
`Toolbelt.app/Contents/MacOS/toolbelt-mcp` over stdio; the helper relays the JSON-RPC lines
to `~/Library/Application Support/Toolbelt/mcp.sock`, where the app answers. If Toolbelt is
not running, the helper starts it in the background and waits up to 10 seconds for the socket.

1. Menu bar → **MCP** → **Add Resource**: a name, the GitLab address (`https://gitlab.com` by
   default) and a legacy personal access token with the `read_api` scope. **Check** shows the
   user, the scopes and when the token expires; **Save** stores it.
2. **Connect to Claude Desktop** adds the server to `claude_desktop_config.json` next to the
   ones already there, with a backup of the old file. Restart Claude Desktop afterwards.
   For Claude Code, **Copy Command** gives
   `claude mcp add --scope user toolbelt -- <path to toolbelt-mcp>`.

The tools are read-only: `gitlab_instances`, `gitlab_resolve_url` (any pasted pipeline, job,
merge request or commit link), `gitlab_pipelines`, `gitlab_pipeline` (every job and trigger,
failed first, with the downstream pipeline or a note that none was created), `gitlab_job_log`
(ANSI and section markers stripped, the last lines or `grep` with context),
`gitlab_merge_requests` and `gitlab_merge_request` (changed files with line counts; one file's
diff on request). Answers are compact text with web links, at most 20,000 characters.
Turning a resource off removes its tools and notifies the connected clients
(`tools/list_changed`); the MCP window shows the clients and the last 200 calls.

### LinkedIn

LinkedIn goes through its official API with an app of your own:

1. On [linkedin.com/developers](https://www.linkedin.com/developers/apps) create an app — it has
   to be tied to a LinkedIn Page; a basic one you admin will do — and add the products
   **Sign In with LinkedIn using OpenID Connect** and **Share on LinkedIn**.
2. Copy **Client ID** and **Client Secret** from the app's Auth tab.
3. In [OAuth Token Generator](https://www.linkedin.com/developers/tools/oauth/token-generator)
   pick the app and the scopes `openid profile email w_member_social`.
4. In Toolbelt → MCP → **Add Resource** choose **LinkedIn**, fill in the name, Client ID, Client
   Secret and the access token, then **Check** and **Save**. Check shows the member, the scopes
   and the expiry; the token lasts 60 days, then it is generated again the same way.

Reading tools: `linkedin_accounts`, `linkedin_profile` and `linkedin_recent_posts` — the posts
published through Toolbelt, since the API does not let a member's app read the member's own
posts. With **Allow write** on the resource (off by default, turned on after a confirmation)
Claude also gets `linkedin_create_post` (text posts, `PUBLIC` or `CONNECTIONS`, `dry_run` to
see the text first) and `linkedin_delete_post` (by URN or a `feed/update` link). Toolbelt
escapes LinkedIn's reserved characters itself, keeps `#hashtags`, and publishes at most 10
posts a day per resource.

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

**HTTP requests go through an ephemeral session.** No cookie jar, no cache: the response
on screen is the one the server sent for exactly the request in the form, and sending it
twice gives the same answer. `-k` is deliberately not honoured — certificates are always
verified. Request history keeps headers as they were, `Authorization` included, so a
request can be replayed; it lives in `UserDefaults` like the deep link history.

**The MCP server lives in the app, the helper only relays.** Tokens, HTTP and the call log
are in one process, so a switch in the window applies to the very next call, and the helper
never touches Keychain — no ACL prompts, no second signature to keep in sync. Each socket
connection is a session with an MCP `Server` of its own, so Claude Desktop, Claude Code and a
cloud session linked to this Mac can be connected at once.

**LinkedIn only through its official API.** Open-source servers drive a logged-in
browser session instead; that breaks LinkedIn's terms, risks a restricted account, and would
mean keeping session cookies that open the whole account. The API gives less — the profile
and the member's own posts, nothing to read — and that is what Toolbelt offers.

**Every user brings their own LinkedIn app.** A client secret inside a distributed binary is
no longer a secret, and LinkedIn's daily limit of 100,000 requests per app would be shared by
everyone. Client ID stays with the resource, Client Secret goes to Keychain next to the token:
together they let Check ask LinkedIn when the token expires and what scopes it has.

**Writing has three locks.** Allow write on the resource, off by default; the same switch
checked again on every call, because a client may hold a tool list from before it went off;
and the `readOnlyHint`/`destructiveHint` annotations clients use to ask before a call.

**The socket admits the user only.** It sits in a 0700 directory with mode 0600, and every
connection's peer is checked with `getpeereid`. GitLab is called over https only (plain http
just for `localhost`), redirects to another host are refused so the token never follows them,
and every tool answer and log entry is scrubbed of the tokens in use.

**JSON is pretty-printed by hand.** `JSONSerialization` would reorder keys, and a response
with its keys shuffled is harder to compare with the docs. The formatter walks the text
character by character instead, and only after `JSONSerialization` has confirmed it is JSON.

## Tests

`swift test` compiles the SwiftUI-free files out of `Toolbelt/` into a `ToolbeltCore`
module and runs Swift Testing suites against it. The Xcode project is untouched — it
builds the same folder as a whole through `PBXFileSystemSynchronizedRootGroup`.

Covered: Conventional Commits parsing, ISO 8601 durations in Tracker's "working" days,
week boundaries, report aggregation, board column ordering, `simctl`, `emulator` and `adb`
output parsing, argument quoting for `adb shell`, the Claude prompt, HTTP status mapping,
pluralization, bash-style splitting of `curl` commands and their options, the exported
`curl` command (including a parse → export → parse round trip), `URLRequest` building,
JSON pretty-printing, `simctl listapps` and exported defaults domains with their plist types,
GitLab link parsing, job log cleanup with `tail` and `grep`, the pipeline and merge request
text Claude gets, LinkedIn's Little Text escaping, post links and URNs, token introspection,
the post body, HTTP status mapping, the write switch and the journal of published posts,
response truncation, newline framing on the MCP socket, the socket's permissions, and merging
`claude_desktop_config.json`.

## Known limitations

- Tracker responses are decoded on the main actor; with a thousand entries that is tens
  of milliseconds. Moving it off requires marking the domain models `nonisolated`.
- Worklog is fetched as a single 1000-entry page — hitting the limit logs a warning, but
  there is no pagination.
- The UI is English only; there is no localization layer.
- HTTP Request understands the common `curl` options; `-F` multipart forms, `@file` bodies
  and `-k` are reported as warnings rather than supported. Plain `http://` hosts other than
  `localhost` need an App Transport Security exception in the target's Info.

## License

MIT — take it and use it.
