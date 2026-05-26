# Dominant Color Audit — macOS Full Player

## Symptom

When two consecutive tracks have different covers, the dominant color reflects the *previous* track's cover instead of the current one.

---

## 1. Where `dominantColor` is declared and stored

There are **two separate code paths** — one for iOS, one for macOS.

**iOS (`FullPlayerView.swift:12`)** — stored mutable state on an `@Observable` view-model:

```swift
// FullPlayerViewModel.swift:12
var dominantColor: Color = .black
```

Held as `@State private var vm = FullPlayerViewModel()` in `FullPlayerView`.

**macOS (`FullPlayerExpandedView.swift:45–47`)** — a pure **computed property** with no intermediate storage:

```swift
private var dominantColor: Color {
    colorExtractor.dominantColor(for: currentTrack?.coverArtId, image: artworkImage)
}
```

It reads two live values every time the view body re-evaluates: `currentTrack?.coverArtId` (from `PlayerState`) and `artworkImage` (`@State private var artworkImage: PlatformImage? = nil`, line 23).

---

## 2. What triggers recomputation

**iOS**: an explicit `.task(id: coverArtId)` at `FullPlayerView.swift:27–28` fires `vm.updateColors(...)`, which performs the full download → extract → assign cycle. `dominantColor` is only updated after the new image is in hand.

**macOS**: the computed property re-evaluates on every body pass. It therefore re-evaluates the moment *either* `currentTrack` or `artworkImage` causes a body invalidation — whichever comes first. There is no gate holding the read until the new image is ready.

---

## 3. The async gap — root cause

The macOS artwork load is triggered at `FullPlayerExpandedView.swift:68–71`:

```swift
.task(id: currentTrack?.id) {
    artworkImage = await artworkCache.load(coverArtId: currentTrack?.coverArtId)
    await refreshFavorite()
}
```

When the track changes:

| Moment | `currentTrack?.coverArtId` | `artworkImage` |
|---|---|---|
| Track flip (instant) | **new track's ID** | **old track's image** (not cleared) |
| After `await artworkCache.load(...)` completes | new track's ID | new track's image |

Between those two moments, the computed `dominantColor` evaluates as:

```swift
colorExtractor.dominantColor(for: newTrackId, image: oldImage)
```

`artworkImage` is never reset to `nil` before the `await`, so the stale image sits there for the entire duration of the load.

---

## 4. Exact call sites where the color is set/updated

**macOS computed property** (`FullPlayerExpandedView.swift:45–47`):

```swift
private var dominantColor: Color {
    colorExtractor.dominantColor(for: currentTrack?.coverArtId, image: artworkImage)
}
```

**`DominantColorExtractor.dominantColor(for:image:)` (`DominantColorExtractor.swift:48–56`)** — extraction and caching logic:

```swift
func dominantColor(for coverArtId: String?, image: PlatformImage?) -> Color {
    guard let coverArtId else { return .clear }
    if let cached = cache[coverArtId] { return cached }   // cache hit: safe
    guard let image else { return .clear }                // if artworkImage is nil: returns .clear
    guard let result = extract(from: image) else { return .clear }
    cache[coverArtId] = result.color                     // WRITES extracted color under this coverArtId
    persistColor(result.packed, forKey: coverArtId)
    return result.color
}
```

**The compounding problem**: because `artworkImage` still holds the old image at the moment of the first evaluation with the new `coverArtId`, the call `dominantColor(for: newId, image: oldImage)` reaches the extraction path, runs `CIAreaAverage` on the old artwork, and **permanently writes that wrong color into the cache under the new track's ID**. All subsequent evaluations — even after the correct image loads — return the cached-but-wrong color immediately via the `if let cached` early-return, so the damage is persistent until the cache is cleared.

**iOS call site** (`FullPlayerViewModel.swift:44, 47`) — not affected because the image is downloaded first:

```swift
let color = colorExtractor.dominantColor(for: coverArtId, image: image)
withAnimation(.easeInOut(duration: 0.4)) {
    coverImage = image
    dominantColor = color   // only set after image is in hand
    ...
}
```

---

## 5. Cover loading logic

**macOS** uses `ArtworkImageCache.load(coverArtId:)` — a single `async` method, no completion callback, no intermediate "loading" state. The result lands in one statement:

```swift
artworkImage = await artworkCache.load(coverArtId: currentTrack?.coverArtId)
```

There is no hook between "task started" and "image assigned" that could nil out `artworkImage` first.

**iOS** uses a separate `URLSession` download inside `FullPlayerViewModel.updateColors(...)` — the dominant color is only computed *after* the data task finishes, so it never sees a stale image. This is why the iOS path does not exhibit the bug.

---

## Fix direction

Reset `artworkImage = nil` at the very start of the `.task(id: currentTrack?.id)` body, **before** the `await`. That makes `artworkImage` nil during the transition, which causes `dominantColor` to return `.clear` instead of running `CIAreaAverage` on the previous track's image and poisoning the cache entry for the new track's ID.

```swift
.task(id: currentTrack?.id) {
    artworkImage = nil   // ← clear stale image before async load
    artworkImage = await artworkCache.load(coverArtId: currentTrack?.coverArtId)
    await refreshFavorite()
}
```
