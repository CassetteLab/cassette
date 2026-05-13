# Widget NowPlaying — Diagnostic Étape 0

## 1. `WidgetSyncService.onPlayStateChanged` ✅

Complet et correct. Construction DTO → encode JSON → write `SharedStorage.defaults[nowPlayingState]` → bridge cover → sync couleur dominante → `reloadTimelinesIfNeeded()` → log debug.

```swift
func onPlayStateChanged(isPlaying: Bool, currentSong: DisplayableSong?) async {
    let track: SharedTrackInfo? = currentSong.map { song in
        let coverArtId = song.coverArtId ?? song.id
        return SharedTrackInfo(id: song.id, title: song.title,
            artist: song.artist ?? "", albumID: song.albumId,
            coverArtFilename: "\(coverArtId).jpg")
    }
    let nowPlaying = SharedNowPlayingState(track: track, isPlaying: isPlaying, lastUpdated: Date())
    if let encoded = try? JSONEncoder().encode(nowPlaying) {
        SharedStorage.defaults.set(encoded, forKey: SharedStorageKey.nowPlayingState.rawValue)
    }
    if let song = currentSong {
        let coverArtId = song.coverArtId ?? song.id
        try? await bridgeCoverArt(coverArtId: coverArtId)
        await syncDominantColors(forCoverArtIds: [coverArtId])
    }
    reloadTimelinesIfNeeded()
    Logger.widget.debug("onPlayStateChanged: isPlaying=\(isPlaying)")
}
```

---

## 2. `NowPlayingProvider.makeEntry()` ✅

Lit `SharedStorageKey.nowPlayingState.rawValue`. Décode `SharedNowPlayingState`. Keys symétriques.

```swift
private func makeEntry() -> NowPlayingEntry {
    guard let data = SharedStorage.defaults.data(forKey: SharedStorageKey.nowPlayingState.rawValue),
          let state = try? JSONDecoder().decode(SharedNowPlayingState.self, from: data) else {
        return .empty
    }
    let coverArtId = state.track?.coverArtFilename?.replacingOccurrences(of: ".jpg", with: "")
    let dominantColor = SharedWidgetData.dominantColor(forCoverArtId: coverArtId)
    let coverImage = coverArtId.flatMap { SharedWidgetData.image(forCoverArtId: $0) }
    return NowPlayingEntry(date: Date(), track: state.track,
        isPlaying: state.isPlaying, coverImage: coverImage, dominantColor: dominantColor)
}
```

---

## 3. `SharedStorage.defaults` ✅

```swift
static var defaults: UserDefaults {
    UserDefaults(suiteName: "group.fr.mathieu-dubart.Cassette") ?? .standard
}
```

Utilise le suite App Group, pas `.standard`.

---

## 4. `PlayPauseIntent` ✅ (structurellement)

```swift
#if os(iOS)
import AppIntents

nonisolated struct PlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Lecture / Pause"

    func perform() async throws -> some IntentResult {
        await NowPlayingBridge.performTogglePlayPause?()
        return .result()
    }
}
#endif
```

Routing vers le main app process dépend du metadata AppIntents généré au build — à confirmer via logs device.

---

## 5. `NowPlayingBridge` — définition + assignation ✅

**Définition** (`Cassette/Shared/NowPlayingBridge.swift`) :
```swift
nonisolated enum NowPlayingBridge {
    nonisolated(unsafe) static var performTogglePlayPause: (@Sendable () async -> Void)?
}
```

**Assignation** dans `AppContainer.init`, ligne 108, **synchrone** :
```swift
NowPlayingBridge.performTogglePlayPause = { [weak player] in await player?.togglePlayPause() }
```

S'exécute à la création de `AppContainer()`, avant tout `Task {}`. Bridge set dès le cold start.

---

## 6. `reloadTimelinesIfNeeded()` ⚠️ Bug throttle

```swift
func reloadTimelinesIfNeeded() {
    let now = Date()
    if let last = lastReloadDate, now.timeIntervalSince(last) < 1.0 { return }
    lastReloadDate = now
    #if os(iOS)
    WidgetCenter.shared.reloadAllTimelines()
    #endif
    Logger.widget.debug("reloadAllTimelines triggered")
}
```

Throttle 1 seconde. Reload global (`reloadAllTimelines`, pas ciblé par kind).

---

## ⚠️ Bug confirmé statiquement — throttle race sur track change

Dans `PlayerService.startPlayback()` :

```swift
if let ws = widgetSyncService {
    Task { await ws.onTrackStarted(song) }           // Task A
}
if let ws = widgetSyncService {
    Task { [weak ws] in await ws?.onPlayStateChanged(isPlaying: true, currentSong: song) }  // Task B
}
```

`WidgetSyncService` est un `actor` → Tasks A et B sont **sérialisées**.

**Ordre d'exécution :**
1. Task A → `onTrackStarted` → écrit `recentlyPlayedItems` → `reloadTimelinesIfNeeded()` à t₀ (`lastReloadDate = t₀`) → **reload déclenché**
2. Task B → `onPlayStateChanged` → écrit `nowPlayingState` ✅ → `reloadTimelinesIfNeeded()` à t₀+δ → **THROTTLÉE** (δ < 1s)

**Résultat** : le widget se recharge une fois (via Task A) **avant** que `nowPlayingState` soit écrit. Task B écrit le bon état mais ne peut pas déclencher de rechargement.

Widget affiche état stale ou vide pour `nowPlayingState` à chaque changement de track.

**Fix proposé** : dans `onPlayStateChanged`, bypasser `reloadTimelinesIfNeeded()` et appeler `WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")` directement — ciblé, sans throttle.

---

## Tableau récap

| Zone | Status | Note |
|------|--------|------|
| `onPlayStateChanged` write | ✅ OK | Complet, key correcte |
| `makeEntry` read | ✅ OK | Key symétrique |
| `SharedStorage.defaults` | ✅ OK | App Group suite |
| `PlayPauseIntent` | ✅ OK (code) | Test device requis pour `[INTENT]` |
| `NowPlayingBridge` assignation | ✅ OK | Synchrone dans `AppContainer.init` |
| `reloadTimelinesIfNeeded` | ⚠️ Bug | Throttle bloque le reload après write `nowPlayingState` |

---

## Étapes suivantes

- **Fix immédiat (sans device)** : bypass throttle dans `onPlayStateChanged` → `reloadTimelines(ofKind: "NowPlayingWidget")`
- **Fix conditionnel (nécessite device)** : si `[INTENT]` absent → problème routing `AudioPlaybackIntent` → investiguer metadata AppIntents
