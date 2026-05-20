# DIAG — AirPlay queue stop after each song

**Date** : 2026-05-20  
**Versions** : Cassette v1.7, iOS (bug non reproduit macOS/CarPlay)  
**Setup** : NAD C700 V2 (AirPlay 2), même config que NaviBeat (qui ne bug pas)  
**Périmètre** : audit statique uniquement — aucune modification de code

---

## 1. Observers `AVAudioSession`

Tous les observers sont déclarés et gérés dans `PlayerService` (`actor PlayerService`).  
Fichier : `Cassette/Services/Implementations/PlayerService.swift`

### 1.1 `AVAudioSession.interruptionNotification`

| Champ | Valeur |
|-------|--------|
| **Propriété de stockage** | `private var interruptionObserver: NSObjectProtocol?` (ligne 38) |
| **Queue d'observation** | `.main` |
| **Lieu d'inscription** | `configureAudioSessionIfNeeded()`, ligne 1252–1261 |
| **Guard anti-doublon** | `if interruptionObserver == nil` |
| **Lieu de désinscription** | `teardownPlayer()`, lignes 1213–1216 |
| **Guard iOS** | `#if os(iOS)` (absent sur macOS) |

**Handler** — `handleAudioSessionInterruption(_:)`, lignes 1282–1313 :

```
.began
  → guard isPlaying (state.playbackState == .playing) sinon return
  → state.playbackState = .paused
  → stopPositionSaveTimer()
  → saveSession()
  → widgetSync.onPlayStateChanged(isPlaying: false)
  ⚠️ player?.pause() NOT called — iOS a déjà suspendu l'audio engine

.ended
  → lit AVAudioSessionInterruptionOptionKey → shouldResume
  → si shouldResume == true  → resume()
  → si shouldResume == false → reste paused, aucun log
```

**Comportement par défaut** : si `shouldResume` est absent ou false (cas courant pour certains types d'interruption), la session reste muette sans log explicite.

---

### 1.2 `AVAudioSession.routeChangeNotification`

| Champ | Valeur |
|-------|--------|
| **Propriété de stockage** | `private var routeChangeObserver: NSObjectProtocol?` (ligne 39) |
| **Queue d'observation** | `.main` |
| **Lieu d'inscription** | `configureAudioSessionIfNeeded()`, lignes 1262–1279 |
| **Guard anti-doublon** | `if routeChangeObserver == nil` |
| **Lieu de désinscription** | `teardownPlayer()`, lignes 1217–1220 |
| **Guard iOS** | `#if os(iOS)` |

**Handler** — inline, lignes 1270–1277 :

```swift
switch changeReason {
case .oldDeviceUnavailable:
    Task { [weak self] in await self?.pause() }      // ← full pause, async

case .newDeviceAvailable, .routeConfigurationChange:
    try? AVAudioSession.sharedInstance().setActive(true)  // ← session only, NO play()

default:
    break
}
```

**Effet sur `PlayerState`** :
- `.oldDeviceUnavailable` → `pause()` → `player?.pause()` + `state.playbackState = .paused`
- `.newDeviceAvailable` / `.routeConfigurationChange` → aucun effet sur le player ni sur le state

**Raisons non gérées explicitement** (tombent dans `default: break`) : `.wakeFromSleep`, `.noSuitableRouteForCategory`, `.categoryChange`, `.override`, `.unknown`, `.routeConfigurationChange` n'est pas dans `default` mais vu ci-dessus.

---

### 1.3 Notifications NON observées

Les notifications suivantes ne sont enregistrées **nulle part** dans le projet :

| Notification | Présente ? |
|---|---|
| `AVAudioSession.mediaServicesWereLostNotification` | ✗ |
| `AVAudioSession.mediaServicesWereResetNotification` | ✗ |
| `AVAudioSession.silenceSecondaryAudioHintNotification` | ✗ |

---

## 2. Configuration `AVAudioSession`

Fichier : `PlayerService.swift`, fonction `configureAudioSessionIfNeeded()`, lignes 1227–1280

### 2.1 Catégorie, options, mode

```swift
// ligne 1233
try session.setCategory(.playback, options: [.allowAirPlay, .allowBluetoothHFP])
```

- **Catégorie** : `.playback` — correct pour musique, permet background audio
- **Options** : `.allowAirPlay` + `.allowBluetoothHFP` — HFP est la profile voix Bluetooth, pas A2DP. Pour AirPlay seul c'est neutre, mais l'absence de `.allowBluetooth` (A2DP) signifie que les écouteurs BT audio-seulement ne sont pas supportés
- **Mode** : non défini → `.default` implicite — correct pour musique
- `setCategory` est appelé **une seule fois** par cycle de vie app (guard `audioSessionConfigured`, ligne 1230)

### 2.2 `setActive(true/false)` — quand et où

| Appel | Ligne | Condition |
|-------|-------|-----------|
| `session.setActive(true)` | 1239 | Toujours, dans `configureAudioSessionIfNeeded()` |
| `session.setActive(true)` retry | 1246 | Si erreur code=-50, après 0.5 s de délai |
| `session.setActive(true)` | 1274 | Dans le handler routeChange, pour `.newDeviceAvailable`/`.routeConfigurationChange` |

`setActive(false)` : **absent de tout le projet** — la session n'est jamais explicitement désactivée.

### 2.3 Relation `setActive` / `AVPlayer.play()`

Dans `startPlayback()` (le chemin principal de transition de track), la séquence est :

```
ligne 216 : teardownPlayer()            ← sync, old player destroyed
ligne 219 : configureAudioSessionIfNeeded()  ← sync, setActive(true)
ligne 223 : AVPlayer(playerItem: item)  ← sync, new player created
ligne 231 : newPlayer.play()            ← sync, play signaled
ligne 234 : await MainActor.run { ... } ← PREMIER await après play()
```

`setActive(true)` précède `play()` d'exactement 12 lignes synchrones — séquence correcte selon la documentation Apple.

---

## 3. Transition track-to-track

### 3.1 Détection de fin de track

**Mécanisme unique** : `AVPlayerItemDidPlayToEndTime` notification, fichier `PlayerService.swift` lignes 1183–1194.

```swift
endOfTrackObserver = NotificationCenter.default.addObserver(
    forName: .AVPlayerItemDidPlayToEndTime,
    object: item,          // ← bound to specific AVPlayerItem
    queue: .main
) { [weak self] _ in
    Task { await self?.handleEndOfTrack() }
}
```

- Aucun `boundaryTimeObserver` ni `addPeriodicTimeObserver` utilisé pour la détection de fin
- Aucune observation de `timeControlStatus` (KVO, Combine, AsyncStream) — nulle part dans le projet
- L'observer est lié à un `AVPlayerItem` spécifique, correctement invalidé et ré-attaché à chaque transition

### 3.2 Chaîne d'appel sur advance automatique

```
AVPlayerItemDidPlayToEndTime
  → handleEndOfTrack()                          lignes 967–993
      → if repeatMode == .one : seek(0) + play()   lignes 969–983  [STOP ICI]
      → else : skipToNext()                         ligne 988

skipToNext()                                       lignes 602–623
  → if nextIndex < queue.count :
        play(tracks: queue, startIndex: nextIndex)  ligne 616
  → elif repeatMode == .all :
        play(tracks: queue, startIndex: 0)          ligne 619
  → else :
        rewindToFirstTrackPaused()                  ligne 621

play(tracks:startIndex:)                           lignes 102–148
  → mediaResolver.resolve(songId:)  [await — résolution réseau]
  → startPlayback(song:source:serverId:)            ligne 147

startPlayback()                                    lignes 150–275
  → recordCurrentTrackPlayback()    [await]
  → MainActor.run { cacheSettings } [await]
  → teardownPlayer()                [SYNC — ligne 216]
  → configureAudioSessionIfNeeded() [SYNC — ligne 219]
  → AVPlayer(playerItem:)           [SYNC — ligne 223]
  → newPlayer.play()                [SYNC — ligne 231]
  → await MainActor.run { state.playbackState = .playing }  [ligne 234–240]
  → await resolveArtworkURL()
  → await serverService.activeCredentials()
  → await nowPlayingService.update(with:)
  → await saveSession()
  → await evaluateAutoExtend()
```

### 3.3 Architecture AVPlayer — pas d'AVQueuePlayer

**Cassette utilise un `AVPlayer` unique, recréé intégralement à chaque transition.**

- Aucun `AVQueuePlayer` dans le projet
- Aucun `advanceToNextItem()`, aucun `insert(_:after:)`
- La seule réutilisation partielle est dans `rewindToFirstTrackPaused()` (fin de queue) : `player?.replaceCurrentItem(with:)` ligne 1035 — le player est conservé, seul l'item est swappé
- `teardownPlayer()` appelle `player?.pause()` puis `player = nil` — destroy complet

### 3.4 Thread / actor de l'advance

L'ensemble de la chaîne s'exécute sur l'executor du `PlayerService` actor. Le handler `AVPlayerItemDidPlayToEndTime` est reçu sur `.main` (queue du NotificationCenter), puis crée un `Task { await self?.handleEndOfTrack() }` qui bascule sur l'actor.

### 3.5 Timing exact du `play()` vs state update

`newPlayer.play()` est appelé à la ligne 231, avant les updates de `state` (ligne 234+). Il n'y a aucun `await` entre la création du nouveau player et son `play()`. Le premier `await` post-`play()` est `await MainActor.run { state.currentTrack = ... }` à la ligne 234 — c'est à ce moment que l'actor se libère et peut traiter d'autres tâches en attente.

---

## 4. `MPNowPlayingInfoCenter` et `MPRemoteCommandCenter`

Fichier : `Cassette/Services/Implementations/NowPlayingService.swift`

### 4.1 Mise à jour de `nowPlayingInfo` lors d'un advance

La mise à jour NowPlaying est appelée à la ligne 264 de `startPlayback()` :
```swift
await nowPlayingService?.update(with: snapshot)
```

Cet appel intervient **après** `newPlayer.play()` (ligne 231) et **après** `state.playbackState = .playing` (ligne 238). Il est donc postérieur au démarrage effectif du player.

Le snapshot contient `playbackRate: 1.0` et `ElapsedPlaybackTime: 0` — correctement initialisé pour une nouvelle track.

### 4.2 Commandes `MPRemoteCommandCenter` câblées

| Commande | Action | Lignes |
|---|---|---|
| `playCommand` | `resume()` | 29–33 |
| `pauseCommand` | `pause()` | 36–40 |
| `togglePlayPauseCommand` | `togglePlayPause()` | 43–48 |
| `nextTrackCommand` | `skipToNext()` | 50–58 |
| `previousTrackCommand` | `skipToPrevious()` | 61–70 |
| `changePlaybackPositionCommand` | `seek(to:)` | 72–81 |

Toutes les closures utilisent `Task.detached(priority: .userInitiated)` pour éviter de bloquer le thread de commande.

### 4.3 `nextTrackCommand` vs auto-advance

Le `nextTrackCommand` câble `skipToNext()` — exactement la même fonction appelée par `handleEndOfTrack()`. Les deux chemins (commande externe Control Center/Remote + auto-advance interne) passent par le même code. **Pas de divergence de comportement entre les deux.**

### 4.4 Availability des commandes

```swift
center.nextTrackCommand.isEnabled = !isLiveStream
center.previousTrackCommand.isEnabled = !isLiveStream
center.changePlaybackPositionCommand.isEnabled = !isLiveStream
```

Mis à jour à chaque `update(with:)` — correct pour les tracks normales.

---

## 5. Patterns suspects

### 5.1 `pause()` inconditionnel sur `.oldDeviceUnavailable` — ⚠️ SUSPECT PRINCIPAL

**`PlayerService.swift`, ligne 1271–1272** :
```swift
case .oldDeviceUnavailable:
    Task { [weak self] in await self?.pause() }
```

Ce `pause()` est **inconditionnel** : il ne vérifie pas si le player est en train de jouer, si la route a réellement changé de façon permanente, ni si le changement est transitoire (reconnexion pendant une transition de track). Il s'exécute sur l'actor via un `Task` non-structuré, ce qui signifie qu'il peut s'intercaler entre deux `await` de `startPlayback()`, en particulier les nombreux awaits qui suivent `newPlayer.play()` (lignes 234–268).

**Scénario de race** [à confirmer via instrumentation] :
1. `teardownPlayer()` → old AVPlayer détruit → iOS détecte fin de stream AirPlay → notification `.oldDeviceUnavailable` postée sur `.main`
2. `newPlayer.play()` appelé (ligne 231)
3. `startPlayback()` suspend à `await MainActor.run { }` (ligne 234)
4. Main queue traite la notification → handler crée `Task { await self?.pause() }` sur l'actor
5. Actor, libéré à l'étape 3, exécute `pause()` :
   - `player?.pause()` → pause le **nouveau** player
   - `state.playbackState = .paused`
6. `startPlayback()` reprend → `state.playbackState = .playing` (ligne 238) — mais le player est désormais paused
7. Ou si `pause()` arrive après la ligne 238, l'état final est `.paused` avec un player paused — exactement le comportement rapporté

### 5.2 Pas de `player?.play()` après `.newDeviceAvailable` / `.routeConfigurationChange` — ⚠️ SUSPECT

**`PlayerService.swift`, lignes 1273–1274** :
```swift
case .newDeviceAvailable, .routeConfigurationChange:
    try? AVAudioSession.sharedInstance().setActive(true)
```

La documentation Apple recommande explicitement d'appeler `play()` après une notification de route change indiquant qu'un device devient disponible, pour garantir la reprise si le player s'est mis en pause. Ce call manque.

Lorsque le nouveau `AVPlayer` connecte son stream AirPlay au NAD C700 V2, iOS peut émettre `.routeConfigurationChange` ou `.newDeviceAvailable` pendant la négociation. Si l'`AVPlayer` passe en `.waitingToPlayAtSpecifiedRate` (stall réseau pendant l'établissement du stream), aucun code ne le détecte ni ne rappelle `play()`.

[à confirmer via instrumentation]

### 5.3 Aucune observation de `timeControlStatus` — ⚠️ SUSPECT

**Absent de tout le projet** : pas de KVO, Combine, ni `AsyncStream` sur `AVPlayer.timeControlStatus`.

En playback AirPlay, l'`AVPlayer` peut passer à `.waitingToPlayAtSpecifiedRate` (stall) sans jamais revenir à `.playing` si la connection AirPlay est perturbée. Sans observation de ce status, le player reste silencieusement bloqué. La seule observation active est le periodic time observer à 0.5 s (ligne 1088) qui met à jour `state.position` — mais aucun code ne réagit au fait que la position n'avance plus.

[à confirmer via instrumentation]

### 5.4 Ré-inscription des observers à chaque transition — observation

`teardownPlayer()` retire `routeChangeObserver` et `interruptionObserver` (lignes 1217–1220, 1213–1216). `configureAudioSessionIfNeeded()` les ré-inscrit immédiatement après (guards `nil` aux lignes 1252, 1262). La séquence est synchrone (aucun `await` entre les deux fonctions dans `startPlayback()`), donc la fenêtre sans observer est théoriquement nulle du point de vue de l'actor. Ce n'est pas suspect en soi, mais crée une complexité inutile. **Pas retenu comme suspect principal.**

### 5.5 Absence de `setActive(false)` — observation neutre

La session n'est jamais désactivée. C'est un choix défensif documenté (commentaire ligne 1236) et cohérent avec un player de musique continu. Pas suspect.

---

## 6. Hypothèses priorisées

### H1 — ★★★ PROBABILITÉ HAUTE : route change `.oldDeviceUnavailable` pauses le nouveau player

**Mécanisme** : À chaque fin de track, `teardownPlayer()` détruit l'`AVPlayer` (ligne 1223 : `player = nil`). La destruction du player arrête le stream AirPlay vers le NAD C700 V2. iOS interprète cela comme l'indisponibilité de la route précédente et émet `.oldDeviceUnavailable`. Le handler appelle `pause()` via un `Task` non-structuré. En raison du scheduling de l'actor Swift, ce `pause()` s'intercale dans les awaits de `startPlayback()` **après** `newPlayer.play()` (ligne 231). Résultat : le nouveau player est démarré puis immédiatement mis en pause, avec `state.playbackState = .paused`.

**Pourquoi CarPlay est immunisé** : le routing CarPlay opère au niveau HAL/OS, indépendamment du cycle de vie des instances `AVPlayer`. Détruire un `AVPlayer` ne modifie pas la route CarPlay et ne déclenche pas `.oldDeviceUnavailable`.

**Pourquoi NaviBeat est immunisé** : NaviBeat utilise très probablement `AVQueuePlayer` qui enchaîne les items sans jamais détruire le player — la route AirPlay reste établie en continu, aucun `.oldDeviceUnavailable` n'est émis.

**Ce que l'instrumentation doit confirmer** : timestamp et raison exacte du route change par rapport au `play()` du nouveau player.

---

### H2 — ★★ PROBABILITÉ MOYENNE-HAUTE : `timeControlStatus` stall non détecté

**Mécanisme** : Lorsque le nouveau `AVPlayer` appelle `play()` alors qu'AirPlay négocie une nouvelle connexion avec le NAD C700 V2 (l'ancien stream venait d'être coupé), l'`AVPlayer` peut entrer dans `.waitingToPlayAtSpecifiedRate`. Aucun code n'observe ce status dans Cassette. Si la connexion AirPlay ne s'établit pas dans le délai interne d'`AVPlayer` (e.g., timeout de buffer), le player abandonne silencieusement. La position reste à 0, aucun son ne sort, mais `state.playbackState` est `.playing` (le state est mis à jour sans vérifier `timeControlStatus`).

**Ce que l'instrumentation doit confirmer** : observer `timeControlStatus` et logger ses transitions pendant la window de transition de track.

---

### H3 — ★ PROBABILITÉ MOYENNE : `routeConfigurationChange` sans `player?.play()` ne récupère pas un stall

**Mécanisme** : Lors de l'établissement du nouveau stream AirPlay (reconfiguration de route), iOS émet `.routeConfigurationChange`. Le handler appelle `setActive(true)` mais omet `player?.play()`. Si l'`AVPlayer` s'est mis en pause interne pendant la reconfiguration (comportement documenté par Apple pour certains receivers AirPlay), il reste paused faute d'un appel explicite à `play()`. Ce scenario est conditionnel à ce que le player se mette effectivement en pause lors de la reconfiguration — comportement non garanti.

**Ce que l'instrumentation doit confirmer** : logger si `.routeConfigurationChange` est émis pendant la transition, et si le player était réellement playing ou waiting à ce moment.

---

## Synthèse

Le bug s'explique le plus probablement par une **interaction destructive entre le pattern teardown-rebuild de `AVPlayer` et le handler `.oldDeviceUnavailable`**. Cassette recrée un `AVPlayer` complet à chaque transition de track — une architecture qui fonctionne en local et sur CarPlay mais qui est incompatible avec AirPlay : chaque destruction du player coupe le stream réseau vers le receiver, ce qui peut déclencher une notification de route change que le handler transforme en `pause()` sur le nouveau player.

**Ce que l'instrumentation (Phase A.2) doit capturer** :
1. Raisons exactes de route change (`oldDeviceUnavailable` / `newDeviceAvailable` / `routeConfigurationChange` / autre), avec timestamp en millisecondes relatif au `play()` du nouveau player
2. État de `timeControlStatus` du nouveau player à T+0.5 s, T+2 s, T+5 s après `play()`
3. Séquence `play()` → route change → pause() sur la timeline de l'actor, pour déterminer si le `pause()` arrive avant ou après `state.playbackState = .playing`
4. Confirmation que la notification `.oldDeviceUnavailable` est bien émise à chaque transition de track (et non sporadiquement)
