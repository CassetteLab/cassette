# macOS Playback Issues — Branch Audit

Branch: `fix/macos-playback-issues` vs `main`

Commits audited:
- `0bc5f9b` refactor(nowplaying): use local HTTP for Discord RPC (replace distributed notifications)
- `4d3f1df` fix(nowplaying): post playback-stopped on pause
- `85c85b5` fix(lifecycle): post playback-stopped on app terminate
- `d888c4e` fix(nowplaying): re-post discord rpc on resume from pause

---

## 1. Changed files

The four commits touch exactly **two files**:

| File | Commits | Summary |
|---|---|---|
| `Cassette/Services/Implementations/NowPlayingService.swift` | `0bc5f9b`, `4d3f1df`, `d888c4e` | Replace distributed notifications with local HTTP POST to `localhost:47832`; add `playback-stopped` on pause; add re-post on resume from pause using `currentSong` state |
| `Cassette/App/CassetteApp.swift` | `85c85b5` | Add `await c.nowPlayingService.stop()` to the Cmd+Q terminate handler, after `playerService.stop()` and before `sema.signal()` |

No AudioStreaming code, no AudioPlayer configuration, no `#if os(macOS)` audio session code was changed.

---

## 2. AudioStreaming / player initialization

`AudioPlayer` is created **synchronously in `PlayerService.init()`** (`PlayerService.swift:116–130`), before any lifecycle event or notification is processed:

```swift
let player = AudioPlayer(configuration: playerConfig)
let delegate = AudioStreamingDelegate()
self.audioPlayer = player
delegate.service = self
player.delegate = delegate
```

Full boot sequence in `CassetteApp.swift:91–119`:

1. `AppContainer.init()` → `PlayerService.init()` → `AudioPlayer` allocated
2. `AppContainer.setup()` — async, network/keychain
3. `nowPlayingService.start()` — MPRemoteCommandCenter registered
4. `container = newContainer` — views render
5. `serverService.loadPersistedState()`
6. `playerService.restoreSession()` → `audioPlayer.play(url:headers:)` called for the first time

`NowPlayingService` has **zero influence** over when `AudioPlayer` starts. There is no ordering dependency between the two services at startup. The Discord RPC HTTP calls cannot reach `AudioPlayer` in any way.

---

## 3. Lifecycle changes — `playback-stopped` risks

### On pause (`4d3f1df`)

```
pause() → pushPositionSnapshot(rate: 0.0) → NowPlayingService.update(with: snapshot)
```

`snapshot.artworkURL == nil` and `snapshot.playbackRate == 0` → position-only update path. New code at `NowPlayingService.swift:184`:

```swift
if snapshot.playbackRate == 0 {
    postDiscordRPC(.stopped)
}
```

This fires a fire-and-forget HTTP POST. Nothing in this path touches AudioStreaming.

### On terminate (`85c85b5`)

```swift
// CassetteApp.swift:127–143
c.playerService.stopAudioEngineSync()   // synchronous, on calling thread
Task {
    await c.playerService.stop()
    await c.nowPlayingService.stop()    // NEW
    sema.signal()
}
sema.wait(timeout: .now() + 1.5)
```

`nowPlayingService.stop()` does:
1. `await MainActor.run { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; playbackState = .stopped }`
2. `postDiscordRPC(.stopped)` — launches a `URLSession.dataTask`, returns immediately

**Critical pre-existing issue**: `sema.wait()` blocks the main thread. On macOS, `MainActor == main thread`. Any `await MainActor.run { }` inside the Task (both in `playerService.stop()` and the new `nowPlayingService.stop()`) cannot be scheduled — the main thread is blocked. This was already true before `85c85b5`, which is why the 1.5-second timeout was introduced in an earlier commit (`fix(macos): add timeout to terminate semaphore to prevent Cmd+Q freeze`).

The new `nowPlayingService.stop()` does not worsen this — it just adds more work that also silently drops on timeout. In practice: the Discord RPC `.stopped` event on Cmd+Q is likely never delivered. This is cosmetic only.

### Can `playback-stopped` fire before player initialization?

No. `NowPlayingService` is only wired to `PlayerService` via `setNowPlayingService()` in `AppContainer.setup()`, and `nowPlayingService.start()` runs after that. The service cannot receive any `update(with:)` call until `restoreSession()` is called, which runs after `container = newContainer`. No premature stop event is possible on cold launch.

---

## 4. Local HTTP server for Discord RPC

The commit message says "local HTTP server" but this is a **pure HTTP client** — no port is bound, no socket is opened for listening. `postDiscordRPC` (`NowPlayingService.swift:303–324`):

- **Port**: `47832` (hardcoded)
- **Targets**: `http://localhost:47832/now-playing` and `http://localhost:47832/playback-stopped`
- **Mechanism**: `URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()` — fire-and-forget, response/error discarded
- **Timeout**: 2 seconds (`URLRequest.timeoutInterval`)
- **Isolation**: `nonisolated` — callable from any actor context

No Core Audio session is requested. No audio-related resource is touched. If nothing is listening on port 47832, the requests fail silently within the 2-second timeout. `URLSession.shared` tasks for failed connections are cheap and self-cleaning.

---

## 5. Merge conflict check

```
git log --merges: 349f6ac  Merge branch 'main' into fix/macos-playback-issues
```

Only one relevant merge. `git diff fix/macos-playback-issues...main` (symmetric difference) shows only the dominant color fix (`b58fdff`) as diverged. No conflicts are indicated. No file shows signs of a silent bad resolution.

---

## 6. macOS-specific code paths touched

All Discord RPC code is behind `#if os(macOS)` guards:

| Location | Guard | Content |
|---|---|---|
| `NowPlayingService.swift:110–112` | `#if os(macOS)` | `postDiscordRPC(.stopped)` in `stop()` |
| `NowPlayingService.swift:183–195` | `#if os(macOS)` | Pause-detection and resume re-post in position-only `update(with:)` path |
| `NowPlayingService.swift:219–227` | `#if os(macOS)` | New-track `postDiscordRPC(.nowPlaying(...))` |
| `NowPlayingService.swift:302–325` | `#if os(macOS)` | `postDiscordRPC(_:)` function definition |
| `NowPlayingService.swift:347–360` | `#if os(macOS)` | `DiscordRPCEvent` and `DiscordNowPlayingInfo` type definitions |
| `CassetteApp.swift:134` | Inside existing `#if os(macOS)` terminate block | `await c.nowPlayingService.stop()` |

iOS is not affected by any of these changes.

---

## Suspects ranked by likelihood of causing HALC / macOS audio issues

| Rank | Location | Issue | Likelihood |
|---|---|---|---|
| 1 | `CassetteApp.swift:127–143` (pre-existing, not introduced here) | `sema.wait()` blocks main thread while Task needs `MainActor` — terminate work never completes, audio engine teardown races with process exit | Pre-existing. Not regressed by these commits. |
| 2 | `CassetteApp.swift:134` (`85c85b5`) | `nowPlayingService.stop()` starts a URLSession dataTask with a 2-second timeout inside a 1.5-second semaphore window — Discord `.stopped` on Cmd+Q is silently dropped | Low — cosmetic only, no audio effect |
| 3 | `NowPlayingService.swift:184–185` (`4d3f1df`) | `postDiscordRPC(.stopped)` fires on every pause — rapid pause/resume cycles create fire-and-forget URLSession tasks on `URLSession.shared` | Negligible — tasks complete or time out cleanly |
| 4 | `NowPlayingService.swift:186–193` (`d888c4e`) | Resume re-post uses `currentSong` which is only set in the new-track path (`artworkURL != nil`). If session was restored via position-only path (`artworkURL == nil`), `currentSong` is nil and Discord stays cleared after resume | Low — Discord RPC only, no audio effect |

---

## Ordering / race condition risks at startup

None introduced by these commits. The boot sequence is unchanged. `NowPlayingService.start()` registers MPRemoteCommandCenter handlers and does nothing else — no HTTP requests, no resources acquired. `postDiscordRPC` is only callable once `update(with:)` or `stop()` is invoked, which requires playback to be active.

---

## Code that could prematurely trigger stop/teardown of the audio engine

None in these commits. The only call to `audioPlayer.stop()` or `audioPlayer.pause()` remains in `PlayerService` — `NowPlayingService` has no reference to `AudioPlayer` and cannot affect it.

The closest risk is the pre-existing terminate path: `stopAudioEngineSync()` runs synchronously, then `playerService.stop()` calls `audioPlayer.stop()` again (redundant but safe). The new `nowPlayingService.stop()` added after this is purely MPNowPlayingInfoCenter + one HTTP request — it does not touch the audio engine.

---

## Summary

None of the four branch commits introduce a new HALC risk or AudioStreaming regression. The local HTTP Discord RPC is a pure fire-and-forget client with no audio side-effects. The pre-existing deadlock risk in the terminate semaphore path is unchanged. The only practical consequence of these commits on macOS audio is zero.
