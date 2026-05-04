# Beta Known Issues — v1.0 → v1.0.1 patch

Fichier gitignored. Ne pas committer.

---

## Known Issues v1.0 (non-bloquants, fixés en v1.0.1)

### KI-1 — Repeat all ne re-démarre pas automatiquement en fin de queue

**Symptôme** : avec repeat all actif, à la fin de la dernière track,
la queue ne redémarre pas automatiquement depuis la track 0.
L'utilisateur doit tapper "next" manuellement.

**Fréquence** : 100% reproductible.

**Impact** : faible — cas d'usage minoritaire (90%+ des usages ignorent
repeat all queue end). Feature présente dans le tap-next, absente en auto.

**Cause racine** : `handleEndOfTrack()` appelle `try? await skipToNext()`
pour les modes `.all` et `.off`. La logique de `skipToNext()` est correcte
(elle check `repeatMode == .all` et appelle `play(tracks:startIndex:0)`).
Mais `try?` swallowe silencieusement toute erreur de résolution media
(`mediaResolver.resolve()`). Si le serveur est lent ou renvoie une erreur
sur la track 0, le restart échoue sans feedback.

**Diagnostic complet** :
- `skipToNext()` ligne 178-191 : logique repeat-all correcte ✓
- `try?` ligne 429 : swallowe l'erreur ← cause
- Hypothèses HA1, HA2 réfutées (la logique est correcte)

**Fix v1.0.1** :
```swift
// handleEndOfTrack() — else path uniquement
// Remplacer try? par do/catch + log SANS appel à pause()
do {
    try await skipToNext()
} catch {
    Logger.player.error("[PLAYBACK] skipToNext() failed: \(error, privacy: .public)")
    // NE PAS appeler pause() ici — risque de régression artwork/scrubbing
    // via actor-to-actor await sérialisant les Tasks user concurrentes
}
```

**Tests requis avant commit v1.0.1** :
1. Repeat all + queue end → track 0 démarre automatiquement
2. Artwork lock screen reste à jour au changement de track
3. Scrubbing in-app + lock screen + Control Center fonctionnels
4. Couper Wi-Fi pendant transition → log d'erreur visible, pas de crash

---

### KI-2 — Auto-next intermittent (track suivante ne démarre pas parfois)

**Symptôme** : en lecture normale sans repeat, à la fin d'une track,
parfois la track suivante ne démarre pas. AVPlayer reste en pause.

**Fréquence** : intermittent — dépend des conditions réseau.

**Impact** : moyen — visible sur réseau instable ou serveur lent.

**Cause racine** : même que KI-1. `try? await skipToNext()` swallowe
les erreurs de résolution media de la track suivante. En conditions
réseau normales, `resolve()` réussit et la transition se passe bien.
En conditions dégradées, l'erreur est swallowée et l'audio s'arrête.

**Hypothèses réfutées** :
- HB1 (observer non enregistré au cold start) : RÉFUTÉ — observer
  enregistré dans `startPlayback()` ET dans `prepareCurrentTrackForRestoration()`
- HB3 (AudioSession non réactivée) : RÉFUTÉ — `configureAudioSessionIfNeeded()`
  appelé dans `startPlayback()` via `play()`

**Fix v1.0.1** : identique à KI-1 (même `try?` → `do/catch + log`).

---

### KI-3 — Lock screen scrubber reste à la fin en repeat one

**Symptôme** : avec repeat one actif, au restart de la track, le
scrubber du lock screen reste coincé à la fin au lieu de revenir à 0:00.
Les contrôles play/pause peuvent être désynchronisés brièvement.

**Fréquence** : 100% reproductible sur lock screen.

**Impact** : faible — cosmétique, la lecture redémarre correctement
en arrière-plan. Le scrubber se resynchronise après ~0.5s via le
periodic time observer.

**Cause racine** :
- Problème A : aucun snapshot nowPlayingInfo envoyé au MOMENT où la
  track se termine naturellement (avant le seek). iOS voit rate=1.0
  avec `lastElapsedTime` proche de la durée → le scrubber continue
  d'extrapoler au-delà de la durée.
- Problème B (principal) : iOS envoie automatiquement un update
  `MPNowPlayingInfoCenter` quand `AVPlayerItemDidPlayToEndTime` fire
  (`rate=0, position=duration`). Notre update via `pushPositionSnapshot()`
  (appelé dans `seek()`) arrive avant `player.play()`. L'iOS auto-update
  peut arriver APRÈS notre update et l'écraser.

**Hypothèses** :
- HC1 PARTIELLEMENT CONFIRMÉ (fenêtre race condition iOS auto-update)
- HC2 RÉFUTÉ (merge path préserve l'artwork)

**Fix v1.0.1 envisagé** :
```swift
// repeat one — après player.play(), forcer update nowPlayingInfo
// La version sans delay doit être testée en priorité.
// Si elle ne suffit pas, ajouter 100ms pour laisser l'iOS auto-update
// se terminer avant notre override.
await pushPositionSnapshot(rate: 1.0)
// ou si nécessaire :
// try? await Task.sleep(for: .milliseconds(100))
// await pushPositionSnapshot(rate: 1.0)
```

**⚠️ RISQUE IDENTIFIÉ** : lors du test v1.0, cette approche a causé
deux régressions :
1. Artwork non mis à jour au changement de track
2. Scrubbing cassé (in-app + lock screen + Control Center)

**Cause probable des régressions** :
- `await pushPositionSnapshot()` dans l'actor `PlayerService` suspend
  l'actor via un appel actor-to-actor vers `NowPlayingService`. Pendant
  cette suspension, les Tasks de scrubbing (seek) sont sérialisées
  derrière `handleEndOfTrack()` et s'exécutent avec un état potentiellement
  incohérent.
- Cet await supplémentaire dans le path repeat one augmente la fenêtre
  de vulnérabilité aux race conditions.

**Approche alternative à investiguer en v1.0.1** :
- Utiliser `MPRemoteCommandCenter` ou un mécanisme `@MainActor` direct
  pour l'update lock screen, bypasser le passage actor-to-actor
- Ou : ne pas ajouter de snapshot dans `handleEndOfTrack()` mais
  s'assurer que le periodic time observer force un update après le seek

**Tests requis avant commit v1.0.1** :
1. Repeat one + lock screen → scrubber à 0:00 après restart
2. Artwork préservé sur lock screen pendant repeat one
3. Scrubbing in-app + lock screen fonctionnel pendant repeat one
4. Repeat one + pause/play depuis lock screen → artwork stable

---

## Résumé des risques identifiés pour v1.0.1

| Modification | Risque identifié | Mitigation |
|---|---|---|
| `try?` → `do/catch + log` (sans `pause()`) | Minimal | Ne pas ajouter `pause()` dans le catch |
| `pushPositionSnapshot()` dans repeat one | Élevé (régressions artwork + scrub observées) | Investiguer mécanisme alternatif |
| Tout changement dans `seek()` ou `pushPositionSnapshot()` | Élevé | Ne pas toucher en v1.0.1 sans test device complet |

---

*Créé le 2026-04-27 — Diagnostic post-revert v1.0 candidate*

---

## Wrapped — Limitations connues (Phase 4b)

### WR-1 — mostPlayedDay absent des Highlights

**Symptôme** : la highlight card "Most Played Day" n'est pas implémentée en Phase 4b.

**Cause** : `WrappedData` expose uniquement des données agrégées. `PlaybackEvent` stocke un timestamp par écoute mais `StatsService.wrappedData()` ne retourne pas de répartition par jour.

**Fix v1.6.x** :
- Ajouter `mostPlayedDay: Date?` et `dailyDistribution: [Date: Int]` à `WrappedData`
- Implémenter dans `StatsService` via `GROUP BY` sur la date tronquée au jour
- Ajouter la card dans `WrappedRewardsSection`

---

## Won't fix v1 — investigated

### Tap-through during zoom dismiss (AlbumDetailView, PlaylistDetailView)

**Symptôme** : pendant la zoom-out animation (~300ms), taps sur song rows /
boutons header (Play, Shuffle, Download) / cover art déclenchent leur action
alors que la vue est en train de dismiss.

**Fréquence** : reproductible uniquement en tapant intentionnellement pendant
l'animation. Aucun feedback TestFlight à date.

**Impact** : faible — fenêtre de vulnérabilité ~300ms, geste involontaire
peu probable en usage normal.

**Diag (2026-05-03)** :
- `@Environment(\.isPresented)` flip à `false` APRÈS la fin de l'animation
  (équivalent `onDisappear`), pas au début — confirmé via logs `[DISMISS-DIAG]`
  dans `Logger.player`. Flag `isDismissing` ne peut donc pas être armé avant
  les premiers frames de l'animation.
- Patterns testés et abandonnés :
  * Overlay absorber `Color.clear.contentShape().ignoresSafeArea()` au root
    → régressait le scroll de la vue parente (overlay débordait hors des bounds
    visuels animés de la detail view)
  * `.disabled(isDismissing)` au root → flag flip trop tard (après animation),
    taps acceptés pendant toute la durée de la transition
  * `.allowsHitTesting(!isDismissing)` sur ScrollView/List → même cause racine
  * Guards in closures : même cause racine (flag pas armé à temps)
  * `isDismissing = true` sur bouton back uniquement : couvre back button tap
    mais pas swipe-back natif iOS

**Conclusion** : aucune option non-bancale identifiée dans le modèle
SwiftUI / iOS 26. Le hook SwiftUI d'entrée de dismiss (avant animation)
n'est pas exposé publiquement pour `.navigationTransition(.zoom)`.

**Revisit en v1.x si** :
- Users remontent le bug en TestFlight (zéro feedback à date)
- Nouveau hook SwiftUI disponible dans une future version iOS
- Changement de système de transition (abandonner zoom pour slide/push)
