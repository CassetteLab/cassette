# Search → Artist → Album Layering Audit

---

## Part 1 — Initial rendering/layering audit

**Symptom (initial hypothesis):** Navigation pushes visually under instead of on
top. Suspected cause: zoom-transition source/destination asymmetry.

### 1. HistoryRecordingView

Located at `SearchView.swift:292–298`:

```swift
private struct HistoryRecordingView<Content: View>: View {
    let action: () async -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        content().task { await action() }
    }
}
```

Clean passthrough — no ZStack, no `.background`, no `.zIndex`, no custom
transition. Not involved in Artist→Album navigation anyway: it only wraps the
`ArtistID3` and `AlbumID3` direct destinations, not `HomeDestination`.

### 2. SearchView body structure

Root is `Group { … }` (not ZStack/VStack). All four `.navigationDestination`
modifiers are chained directly on that `Group` — not on a child, not on a
background. No `.zIndex` or `.overlay` on the search results. No `.background`
on the Group. Only `.listStyle(.plain)` on the inner `List`.

```
Group { if empty → EmptyStateView; else → List }
    .navigationDestination(for: ArtistID3.self)          // wraps in HistoryRecordingView
    .navigationDestination(for: AlbumID3.self)           // wraps in HistoryRecordingView
    .navigationDestination(for: HomeDestination.self)    // ← Artist→Album resolves here
    .navigationDestination(item: $navigatingToHistoryEntry)
    .cassetteContentWidth()                              // no-op on iOS
```

For `HomeDestination.album`, `AlbumDetailView` is instantiated as:

```swift
AlbumDetailView(
    album: album,
    coverArtId: album.coverArt,
    initialCoverImage: artworkImageCache.cachedImage(...)
    // ← no zoomSourceId, no zoomNamespace (before fix)
)
```

### 3. ArtistDetailView root structure

`Group { ScrollView { heroSection; LazyVGrid { NavigationLink → AlbumGridCell } } }`

No `.background`, no `.overlay`, no `.zIndex`. Clean.

**Critical detail:** every `AlbumGridCell` is always constructed with both zoom
parameters:

```swift
AlbumGridCell(
    album: album,
    zoomSourceId: album.id,           // non-nil
    zoomNamespace: albumZoomNamespace  // non-nil — ArtistDetailView's own @Namespace
)
```

Inside `AlbumGridCell.body`, the cover art always receives:

```swift
.cassetteMatchedTransitionSource(id: zoomSourceId, in: zoomNamespace)
// → .matchedTransitionSource(id: album.id, in: albumZoomNamespace)
```

`albumZoomNamespace` is owned by `ArtistDetailView`. It never leaves that view.

### 4. fullScreenCover / sheet / custom transition usage

`AlbumDetailView.swift:231–232`:

```swift
.navigationBarBackButtonHidden(true)
#if os(iOS)
.enableSwipeBack()
#endif
```

`SwipeBackEnabler` is a `UIViewControllerRepresentable` applied as
`.background(…)`. Its `updateUIViewController` runs:

```swift
DispatchQueue.main.async {
    navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    navigationController?.interactivePopGestureRecognizer?.delegate = nil
}
```

This fires on every SwiftUI update cycle — unusual but not a z-ordering modifier.

`AlbumDetailView.swift:287`:

```swift
.cassetteZoomTransition(sourceID: zoomSourceId, in: zoomNamespace)
```

When `zoomSourceId` and `zoomNamespace` are both `nil` (the case from
SearchView before the fix), the implementation returns `self` unchanged. **No
`.navigationTransition(…)` was applied at all.**

### 5. Comparison with HomeView → Artist → Album

`HomeView.swift:166–174`:

```swift
case .album(let album):
    AlbumDetailView(
        album: album,
        zoomSourceId: album.id,                    // non-nil
        zoomNamespace: recentlyAddedZoomNamespace,  // non-nil — HomeView's @Namespace
        coverArtId: album.coverArt,
        initialDominantColor: …,
        initialCoverImage: …
    )
```

This triggers `.navigationTransition(.zoom(…))` on the destination. The
namespace mismatches the source's `albumZoomNamespace`, so no actual zoom fires,
but both sides are zoom-transition-aware — iOS falls back to a clean standard
push.

**Side-by-side (before fix):**

| Path | Source cell | Destination |
|---|---|---|
| Home → Artist → Album | `.matchedTransitionSource(id, albumNS)` | `.navigationTransition(.zoom(id, recentlyAddedNS))` — mismatched NS → standard push |
| **Search → Artist → Album** | `.matchedTransitionSource(id, albumNS)` | **No `.navigationTransition(…)` at all** |

### 6. Toolbar / navigation bar styling

**SearchView:** no toolbar modifiers.

**ArtistDetailView:** `.navigationTitle(artist.name)` +
`.navigationBarTitleDisplayModeLarge()` + standard `.toolbar`. No
`.toolbarBackground`, no `.toolbarColorScheme`, no `.navigationTransition`.

**AlbumDetailView:**
- `.navigationTitle("")` (empty string)
- `.navigationBarTitleDisplayModeInline()`
- `.navigationBarBackButtonHidden(true)` — custom chevron added via
  `.toolbar { ToolbarItem(.navigation) }`
- No `.toolbarBackground` or `.toolbarColorScheme`

### Fix applied (Part 1)

Added `@Namespace private var albumZoomNamespace` to `SearchView` and passed
`zoomSourceId`/`zoomNamespace` in both `HomeDestination.album` and
`HomeDestination.albumById` cases. Mirrors the HomeView pattern. Namespaces
won't match (different view instances), so iOS falls back to a standard push —
but both sides are now zoom-transition-aware, resolving the asymmetry.

---

## Part 2 — Root cause: HistoryRecordingView / @Query re-render loop

**Revised hypothesis:** The actual bug is that ArtistDetailView's `.task` fires
again when AlbumDetailView is pushed, causing a new ArtistDetailView instance
to be rendered on top of AlbumDetailView.

### 1. ArtistDetailView's task trigger

`ArtistDetailView.swift:110–122`:

```swift
.task {
    guard let c = container else { return }
    if viewModel == nil {
        viewModel = ArtistDetailViewModel(...)
    }
    await viewModel?.load()
    await viewModel?.loadSimilarArtists()
}
```

`.task` with **no `id:` parameter**. Fires on view appearance. The
`if viewModel == nil` guard only wraps viewModel *creation* — `load()` and
`loadSimilarArtists()` are called unconditionally every time the task fires. If
the view is recreated, both are called again from a fresh `viewModel == nil`
state.

### 2. ArtistDetailView's stable identity in NavigationStack

The pushed value is `ArtistID3`. From SwiftSonic:

```swift
public static func == (lhs: ArtistID3, rhs: ArtistID3) -> Bool { lhs.id == rhs.id }
public func hash(into hasher: inout Hasher) { hasher.combine(id) }
```

Identity is `id: String` only. `starred: Date?` and `album: [AlbumID3]?` are
excluded. Stable for navigation purposes.

Within the view hierarchy, `ArtistDetailView` uses structural identity (type +
position). `init` sets `_artistFavoriteMatches = Query(...)`, which is
re-executed when the struct is reconstructed — but `@Query` wraps the predicate
stably based on `artist.id`.

### 3. What causes SearchView body to re-evaluate during navigation

**Primary trigger — fires on every artist navigation, always:**

`HistoryRecordingView`'s `.task` fires immediately when ArtistDetailView
appears. It calls:

```swift
await container?.searchHistoryService.record(...)
```

`SearchHistoryService.record` (`SearchHistoryService.swift:16–42`) **always
writes to the model container** — either `ctx.insert(...)` for a new entry, or
`existing.visitedAt = Date()` for a revisit. Both paths call `ctx.save()`.
There is no "skip if already up-to-date" path.

SearchView owns:

```swift
@Query private var historyEntries: [SearchHistoryEntry]
```

The query has no server-side filter on the descriptor (filtering is done in the
`serverHistory` computed property). Any write to `SearchHistoryEntry` in the
container notifies this `@Query`, which forces SearchView's body to re-evaluate.
This happens within milliseconds of ArtistDetailView appearing, on every single
navigation.

**Secondary trigger — fires when artwork loads:**

```swift
@Environment(ArtworkImageCache.self) private var artworkImageCache
```

`artworkImageCache` is referenced in the `HomeDestination` destination closures.
If `ArtworkImageCache` is `@Observable` and its cache mutates during navigation
(cover art finishes loading in ArtistDetailView), that mutation also re-evaluates
SearchView's body.

### 4. ArtistID3 — value type, Equatable correctness

Struct, passed by value. Explicitly implements `==` and `hash(into:)` using
only `id: String`. The `starred: Date?` field is correctly excluded from both.
Stable.

### 5. Comparison: HomeView → Artist → Album

HomeView's `HomeDestination.artist` case (`HomeView.swift:175`):

```swift
case .artist(let artist):
    ArtistDetailView(artist: artist)
```

**No `HistoryRecordingView`.** No `.task` that writes to SwiftData. HomeView's
`historyEntries` / `@Query` is not involved. When `ArtistDetailView` is pushed
from HomeView, no SwiftData write occurs → HomeView's `@Query` observations do
not fire → HomeView body does not re-evaluate → no destination re-registration
→ no risk of recreation.

The `HistoryRecordingView` mechanism is exclusive to SearchView's `ArtistID3`
and `AlbumID3` destinations.

### 6. Can the destination closure be evaluated more than once?

The closure:

```swift
.navigationDestination(for: ArtistID3.self) { artist in
    HistoryRecordingView {
        await container?.searchHistoryService.record(...)
    } content: {
        ArtistDetailView(artist: artist)
    }
}
```

When SearchView's body re-evaluates (triggered by the `historyEntries` @Query
change), SwiftUI re-processes this `.navigationDestination` modifier. In theory,
the NavigationStack caches pushed destinations and should not re-invoke the
closure for an already-active value.

**However:** `HistoryRecordingView`'s body is `content().task { await action() }`.
`action` and `content` are stored closures. When SwiftUI reconciles an updated
`HistoryRecordingView` struct (new closure references captured from the
re-render), if it treats the closure change as a structural change or a task `id`
change, it would discard the old instance, fire `onDisappear`/task-cancellation
on the old, and fire `onAppear`/new-task on the replacement — causing a fresh
`ArtistDetailView` to be instantiated, `viewModel` to be nil, and `.task` to
fire again with `load()` being called.

### 7. HomeDestination Hashable/Equatable correctness

`HomeDestination: Hashable` is synthesized.

- `case album(AlbumID3)` and `case artist(ArtistID3)`: both use only `id: String`
  for hash/equality → stable, no false-negatives. Not the source of the bug.
- `case offlineArtist(OfflineArtistSummary)`: synthesized Hashable includes the
  `albums: [OfflineAlbumSummary]` array. Two `OfflineArtistSummary` values with
  the same `name` but different album arrays will have different hashes —
  violates the `Identifiable` contract where `id = name`. Not relevant to
  Search→Artist→Album but a latent bug for offline navigation.

---

## Causal chain (Part 2)

```
1. Push ArtistDetailView from SearchView
2. HistoryRecordingView's .task fires immediately
3. SearchHistoryService.record() → ctx.save() (always, even for revisits)
4. SearchView's @Query historyEntries notified → body re-evaluates
5. .navigationDestination(for: ArtistID3.self) modifier is re-processed
6. SwiftUI sees updated HistoryRecordingView struct with new closure captures
7. IF SwiftUI treats this as a view identity change:
   → old HistoryRecordingView discarded, new one inserted
   → new .task fires → new ArtistDetailView instantiated (viewModel = nil)
   → ArtistDetailView's .task fires → load() + loadSimilarArtists() called
8. New ArtistDetailView renders on top of the push-in-progress AlbumDetailView
```

HomeView is immune because it never uses `HistoryRecordingView` — no SwiftData
write on navigation, no `@Query` notification, no body re-evaluation loop.

---

## Proposed fix (Part 2)

The root cause is that `SearchHistoryService.record` always writes to SwiftData,
and `SearchView` re-renders on every write via `@Query historyEntries`.

**Option A — Decouple history write from the navigation destination (preferred):**

Remove `HistoryRecordingView` entirely. Record history from the `NavigationLink`
action instead, using a `Button`-like wrapper or by recording in the
`.onAppear` of a lighter side-effect view that does NOT own the
`@Query`-triggering write at the same time as destination rendering.

Alternatively, use a non-@Query notification channel (e.g., observe a
`@Bindable` on a service, not a SwiftData `@Query`) so history writes don't
trigger SearchView re-renders.

**Option B — Debounce / deduplicate the SwiftData write:**

In `SearchHistoryService.record`, skip `ctx.save()` when `visitedAt` was
updated less than N seconds ago (e.g., 30s). This prevents the write — and
therefore the `@Query` notification — for rapid revisits, breaking the
re-render loop without architecture changes.

**Option C — Isolate history recording from SearchView's @Query:**

Move `historyEntries: @Query` to a child view that is not an ancestor of the
`.navigationDestination` modifier. SwiftUI only re-evaluates destination
closures when the view that *owns* the `.navigationDestination` modifier
re-renders. If the `@Query` lives below the modifier attachment point, the
modifier is insulated from the write.
