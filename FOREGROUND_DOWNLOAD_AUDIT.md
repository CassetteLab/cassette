# Foreground Download Continuation — Architecture Audit

**Date:** 2026-05-01  
**Scope:** Read-only inventory of DownloadService, ToastService, ViewModels, AppContainer.  
**Goal:** Identify what exists and what gaps must be bridged to enable (1) foreground continuation, (2) UI sync on return, (3) toast on completion.

---

## 1. DownloadService API

**Type:** `actor DownloadService` — custom actor isolation, not `@MainActor`, not `@Observable`, not `ObservableObject`.

**Public protocol surface (DownloadServiceProtocol):**

```swift
var progressStream: AsyncStream<[DownloadProgress]> { get }           // nonisolated

func downloadedURL(forSongId: String, serverId: UUID) async -> URL?
func isDownloaded(songId: String, serverId: UUID) async -> Bool
func downloadedSongIds(serverId: UUID) async -> Set<String>
func localCoverArtURL(forId: String) async -> URL?
func localAlbumData(albumId: String, serverId: UUID) async -> LocalAlbumData?
func localPlaylistData(playlistId: String, serverId: UUID) async -> LocalPlaylistData?

func download(song: Song, serverId: UUID) async throws
func download(album: AlbumID3, serverId: UUID) async throws
func download(playlist: PlaylistWithSongs, serverId: UUID) async throws

func isDownloading(songId: String, serverId: UUID) async -> Bool
func cancelDownload(songId: String, serverId: UUID) async
func remove(songId: String, serverId: UUID) async throws
func remove(albumId: String, serverId: UUID) async throws
func remove(playlistId: String, serverId: UUID) async throws
```

**"Currently downloading" state — where it lives:**  
Nowhere public at album/playlist granularity. The only actor-level tracking is `private var inFlightTasks: [String: Task<Void, Error>]`, keyed by `"songId::serverId"` — purely per-song, private. There is no `isDownloadingAlbum(albumId:) async -> Bool` method in the protocol or implementation.

Album/playlist-level state (`isDownloadingAlbum`, `isDownloadingPlaylist`) exists exclusively in the ViewModels. The service itself is stateless with respect to album-level downloads.

**Cross-view observation mechanism:**  
`progressStream: AsyncStream<[DownloadProgress]>` is declared in the protocol and fully implemented — `DownloadProgress` events (per-song, progress 0→1.0) are emitted from `_downloadSong`. **However, `progressStream` is never consumed anywhere in the codebase.** It is implemented infrastructure that has never been wired to a subscriber. Zero call sites outside of the service itself.

---

## 2. ToastService API

**Type:** `@MainActor @Observable final class ToastService`.

**Public API:**

```swift
private(set) var current: Toast?   // observed by ToastOverlay via @Environment

func show(_ message: String, style: Style = .info, duration: TimeInterval = 3.0)
func showError(_ message: String)    // show(..., style: .error, duration: 4.0)
func showSuccess(_ message: String)  // show(..., style: .success, duration: 2.5)
func dismiss()
```

**How views access it:**  
`ToastOverlay` (a ViewModifier) reads it via `@Environment(ToastService.self) private var toastService`. The modifier is applied at a high level in the navigation hierarchy so all screens can show toasts.

**How ViewModels access it:**  
Via init injection — a `let toastService: ToastService` stored property. Examples:
- `PlaylistDetailViewModel.swift:29` — `private let toastService: ToastService`
- `EditPlaylistViewModel` and `AddToPlaylistViewModel` and `CreatePlaylistViewModel` — same pattern

**Is it accessible from DownloadService today?**  
No. `DownloadService.init(serverService:modelContainer:)` does not receive a `ToastService`. The service has no reference to it.

**Calling from DownloadService (actor isolation concern):**  
`ToastService` is `@MainActor`. `DownloadService` is a custom actor. Cross-actor calls require `await`. From inside a DownloadService actor method: `await toastService.showSuccess("…")` is valid Swift — the runtime hops to MainActor automatically. A `let toastService: ToastService` stored property on the actor is legal.

**Notable asymmetry:**  
`PlaylistDetailViewModel` already has `toastService` injected and uses it for `removeTrack` and `moveTracks` error toasts. `AlbumDetailViewModel` does NOT have `toastService` — it silently swallows errors with `try?`. This is a pre-existing inconsistency.

---

## 3. State "in-progress" — Where It Lives and How It's Observed

**ViewModels:**
- `AlbumDetailViewModel.isDownloadingAlbum: Bool` — set `true` at the top of `downloadAlbum()`, `false` at the bottom. Same for `downloadMissingTracks()`.
- `PlaylistDetailViewModel.isDownloadingPlaylist: Bool` — same pattern in `downloadPlaylist()` / `downloadMissingTracks()`.
- Both are `@Observable @MainActor` classes — SwiftUI views observe them via `let vm` binding.

**View ↔ download Task binding:**  
In `AlbumDetailView`:
```swift
@State private var viewModel: AlbumDetailViewModel?
// ...
Button { Task { await vm.downloadAlbum() } } label: { ... }
```
This is an **unstructured `Task`** (`Task { ... }`, not a `.task` modifier). It is NOT tied to the view's lifecycle. The Task captures `vm` (a class reference). When the view is popped, `@State private var viewModel` is released from SwiftUI's perspective, but the Task still holds a strong reference to the VM object — the download continues running in the background until completion. The VM's `isDownloadingAlbum` is set to `false` on a VM that no one is watching.

**When the user returns to the same album detail:**  
A new `viewModel` is initialized (`AlbumDetailViewModel?` starts as `nil`, a new instance is created on appear). That new instance has `isDownloadingAlbum = false`. There is no mechanism to detect that a download is already in progress for that albumId — the VM queries SwiftData after the fact but doesn't inspect `inFlightTasks` in the service. The UI will show the download button as if nothing is happening.

**`progressStream` — consumed?**  
No. Declared in the protocol, implemented in the service, never subscribed to by any view or ViewModel.

---

## 4. Multi-Download Support

Multi-album or album+playlist simultaneous downloads are **architecturally possible** today. There is no mutex or serialization guard at the album or playlist level in `DownloadService`. Two concurrent calls to `download(album:serverId:)` would spawn two independent `withTaskGroup` blocks. With the new 3-slot concurrency limit, each group has 3 slots = 6 potential concurrent URLSession tasks across two albums. `URLSession.shared` default `httpMaximumConnectionsPerHost = 6`, so this is at the ceiling.

The per-song `inFlightTasks` guard (`guard inFlightTasks[key] == nil`) prevents double-downloading the same song if it appears in two simultaneous downloads (e.g., a song that's in both an album and a playlist). The second caller silently returns.

**Conclusion:** Parallel multi-album/multi-playlist download is supported by the service. The ViewModels are per-view so they each track their own `isDownloading*` independently.

---

## 5. Persistence — In-Memory Only

`inFlightTasks` is actor-local in-memory state. It does not survive a process kill.

On cold start after a kill mid-download: SwiftData holds `DownloadedTrack` records for tracks that were fully saved before the kill (the `mainContext.save()` after each track completed). The `DownloadedAlbum`/`DownloadedPlaylist` record is written only after the entire task group completes — so if killed mid-download, the record won't exist yet, and the view will show `partiallyDownloaded(X, N)` based on how many `DownloadedTrack` rows exist for that `albumId`.

The source file documents this explicitly:
```swift
// TODO(v1.x): switch to background URLSession with resume-after-kill support.
// v1 uses foreground URLSession — the user must keep the app open during download.
```

No resume capability exists. No partial download state is persisted to allow restart.

---

## 6. AppContainer Wiring

Services stored in AppContainer and their init order (in `init()` body):

```
modelContainer           — SwiftData container
sessionService           — PlaybackSessionService(modelContainer:)
keychainService          — KeychainService()
serverService            — ServerService(state:keychain:modelContainer:)
libraryService           — LibraryService(serverService:)
cacheService             — CacheService(modelContainer:)
downloadService          — DownloadService(serverService:modelContainer:)   ← no toastService
artworkImageCache        — ArtworkImageCache(downloadService:libraryService:)
mediaResolver            — MediaResolver(downloadService:cacheService:serverService:serverState:)
playerService            — PlayerService(...)
nowPlayingService        — NowPlayingService(playerService:artworkImageCache:)
favoritesService         — FavoritesService(...)
pinService               — PinService(modelContainer:)
playlistService          — PlaylistService(serverService:)

// Inline-initialized stored properties (initialized before init() body):
toastService             = ToastService()
networkMonitor           = NetworkMonitor()
dominantColorExtractor   = DominantColorExtractor()
```

`toastService` is initialized as an inline stored property — it's available as `self.toastService` before the first line of `init()` body executes. Passing it to `DownloadService.init()` is straightforward and requires no reordering.

**What would need to change to inject toastService into DownloadService:**
1. `DownloadService.init(serverService:modelContainer:toastService:)` — add parameter
2. `DownloadServiceProtocol` — no change needed (init is not part of the protocol)
3. `AppContainer.init()` line 55: `DownloadService(serverService: server, modelContainer: modelContainer, toastService: toastService)`

---

## 7. Design Options for the Refactor

### Option A — Expose album/playlist download state in the service + inject ToastService

Add to `DownloadService` actor:
- `private var activeAlbumDownloads: Set<String>` — populated at start/end of `download(album:)`
- `private var activePlaylistDownloads: Set<String>` — same for playlist
- New protocol method: `func isDownloadingAlbum(_ albumId: String) async -> Bool`
- `let toastService: ToastService` — injected at init, called via `await` at end of download

ViewModels call `await downloadService.isDownloadingAlbum(albumId)` in their `load()` to restore state when the user navigates back.

**Tradeoffs:**
- PRO: minimal surface change to existing files. No new classes. Toast fires from the service itself (single place). UI sync on return works via one `await` call in `load()`.
- CON: `isDownloadingAlbum` is still two-step (VM holds its own `isDownloadingAlbum` + service has its own set) — two sources of truth that must be kept in sync. If `load()` is not called on return (e.g. view stays in hierarchy), the VM flag won't update.
- **Scope:** 3 files touched (DownloadService, AppContainer, both ViewModels).

### Option B — Foreground continuation via long-lived Task in AppContainer + progressStream

Keep ViewModels as they are. Move the `download(album:)` call up to AppContainer (or a new `DownloadCoordinator` held by AppContainer) instead of from the ViewModel. The coordinator holds `toastService` and calls it on completion. The coordinator exposes a `@MainActor @Observable` state object that ViewModels read from — so any view that navigates back re-reads current state without re-launching a download.

Views subscribe to the coordinator's state instead of (or in addition to) the VM.

**Tradeoffs:**
- PRO: cleanest separation of concerns. Download lifecycle is fully detached from view hierarchy. `progressStream` finally gets a subscriber. Single source of truth for "is downloading".
- CON: larger scope — new coordinator class, view bindings change, AppContainer gains one more service, both ViewModels need to be refactored to read from coordinator. Non-trivial.
- **Scope:** 4-6 files, new file.

### Option C — NotificationCenter bridge (lightest touch, most fragile)

Post a `Notification` from DownloadService at end of `download(album:)`/`download(playlist:)`. Any live view subscribes via `.onReceive` or a `.task` listening to notification stream and calls `toastService.showSuccess(...)` directly.

**Tradeoffs:**
- PRO: zero changes to service init, zero changes to AppContainer, zero changes to ViewModels.
- CON: NotificationCenter is stringly-typed, breaks the actor-isolation discipline of the rest of the codebase. Hard to test. Doesn't solve the "UI sync on return" problem (the notification fires once and is gone). Double source of truth for `isDownloading`.
- **Not recommended** given the existing architecture.

### Recommendation

**Option A** is the right first step — it has the smallest scope, follows the existing injection pattern already established by `PlaylistDetailViewModel`, and closes all three gaps:

1. **Foreground continuation** — already works today (Task survives pop). No change needed here.
2. **UI sync on return** — VM calls `await downloadService.isDownloadingAlbum(albumId)` in `load()`. One line per VM.
3. **Toast on completion** — `await toastService.showSuccess("…")` at end of `download(album:)` and `download(playlist:)`. Two lines in the service.

Option B is worth doing eventually (especially to activate `progressStream`) but is a larger investment. Do Option A now, Option B when foreground download becomes a user-visible feature worth the full architectural treatment.

---

## Observations Annexes

- **`progressStream` is dead infrastructure.** It emits `DownloadProgress` events per-song but has zero subscribers. Either wire it (Option B) or remove it to avoid confusion. Leaving it "implemented but unused" is a maintenance liability.

- **`AlbumDetailViewModel` has no `toastService`** while `PlaylistDetailViewModel` does. This asymmetry means album download errors are silently swallowed (`try?`) while playlist-related errors (reorder, remove track) show toasts. Worth fixing at the same time as Option A.

- **`downloadMissingTracks()` in both VMs does NOT use the TaskGroup / sliding-window** — it downloads sequentially with a `for` loop: `for song in missing { try? await downloadService.download(song:serverId:) }`. This means missing-track downloads for large partially-downloaded albums are still sequential. Lower priority since it only affects partial re-downloads, but worth noting.

- **`isDownloading(songId:serverId:) async -> Bool`** is on the protocol but is only reliable for individual song downloads initiated via `download(song:)`. Songs downloaded as part of an album go through `inFlightTasks` too, so the method works — but nothing currently calls it in the UI layer.
