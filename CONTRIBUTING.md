# Contributing to Cassette

## Development Rules

### B2 — No SwiftSonic bypass, ever

All Subsonic API calls MUST go through `SwiftSonic`. No `URLSession` calls to server
endpoints directly from Cassette code.

If a SwiftSonic API is missing or awkward:
1. Note it in `APP_FEEDBACK.md` (never committed — see `.gitignore`)
2. Work around it using existing SwiftSonic methods, even if inelegant
3. Keep building — SwiftSonic 0.6.x will address the friction points

**Single exception**: a critical security bug in SwiftSonic → hotfix SwiftSonic
immediately (e.g. a 0.4.1-style patch), do not bypass.

**Alarm signal**: if you are writing more than 10 lines of networking code in Cassette
that do not go through SwiftSonic, stop and discuss.

### B3 — v1 simplifications (documented)

Three deliberate simplifications for v1. Each is marked with
`// TODO(v1.x): <planned evolution>` in the code so they are easy to find later.

| Feature | v1 | v1.x |
|---|---|---|
| Audio cache during stream | Full background download alongside stream | `AVAssetResourceLoaderDelegate` chunk interception |
| Permanent downloads | Foreground `URLSession` (user keeps app open) | Background `URLSession` with resume after app kill |
| Server queue sync | Best-effort `savePlayQueue`/`getPlayQueue`, silently ignored on failure | Robust bidirectional sync with multi-device merge |

### Architecture invariants

1. Files under `Services/` never `import SwiftUI`, `UIKit`, or `AppKit`.
2. `PlayerService` is the **single source of truth** for playback state.
   No duplicated playback state in any view model.
3. `MediaResolver` is the **single entry point** for playable URLs.
   `PlayerService` always asks `MediaResolver` — never SwiftSonic directly.
4. All dependencies injected via `init`. No singletons except `AppContainer`.
5. `NowPlayingService` is active from v1 (lockscreen / Control Center / AirPods).

### Keychain policy

Credentials (passwords, `customHeaders`) are **never** in:
- `UserDefaults`
- Log statements (even at debug level)
- Error messages shown to users

Keychain only. `ServerCredentials` carries an `// IMPORTANT: Never persist outside of Keychain` comment to reinforce this.

### Commit style

Conventional commits: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`.
One atomic commit per subtask. Propose a plan and wait for validation before
implementing each numbered Étape.
