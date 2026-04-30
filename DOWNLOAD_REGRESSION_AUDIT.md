# Download Regression Diagnostic — 2026-04-30

## 1. Historique git récent du download path

| Hash | Date | Message | Suspect |
|------|------|---------|---------|
| `03da0d6` | 2026-04-30 | fix(download): write track records to mainContext for live @Query reactivity | Moyen |
| `c121230` | 2026-04-30 | feat(download): live progress indicator for album and playlist download | **Haut** |
| `f01fecf` | 2026-04-30 | fix(playlist): disable content interactions during dismiss transition | Non suspect |
| `9087154` | 2026-04-30 | fix(album): disable content interactions during dismiss transition | Non suspect |
| `f154973` | 2026-04-30 | feat(playlist): add zoom support, skeleton state, and instant header rendering | Non suspect |
| `553e49d` | 2026-04-29 | refactor(album): polish loading state — skeleton cover, active Play button, instant title | Non suspect |
| `9ebe4bb` | 2026-04-25 | perf(service): download album and playlist tracks concurrently | **SUSPECT PRINCIPAL** |

### Analyse détaillée des commits suspects

#### `9ebe4bb` — SUSPECT PRINCIPAL

Avant ce commit, `download(album:)` était **séquentiel** :
```swift
for song in songs {
    try await download(song: song, serverId: serverId)  // une à la fois
}
```

Après : **N tasks sans aucune limite** via `withTaskGroup` :
```swift
await withTaskGroup(of: Bool.self) { group in
    for song in songs {
        group.addTask { try await self.download(song:) }  // 23 simultanées
    }
}
```

Ce commit a également ajouté `_downloadCoverArt(id:)` dans `_downloadSong` (après chaque audio download, par track), alors qu'avant il était seulement appelé une fois en post-group pour l'album entier. Ce double changement — concurrence illimitée + cover art per-track — est la source principale de la régression.

#### `c121230` — SUSPECT HAUT

Introduit deux nouveaux `@Query<DownloadedTrack>` actifs pendant un download :
- `AlbumDetailView.downloadedAlbumTracks` — filtré par `albumId`
- `PlaylistDetailView.allDownloadedTracks` — **aucun filtre**, observe TOUS les DownloadedTrack

Ces @Query déclenchent des re-renders SwiftUI à chaque `mainContext.save()`, contribuant à la saturation MainActor. N'est pas la cause du timeout réseau mais amplifie la lenteur perçue et la congestion MainActor.

#### `03da0d6` — SUSPECT MOYEN

Change le contexte de save de `ModelContext(modelContainer)` (éphémère, sibling) à `modelContainer.mainContext` (long-lived, observé par @Query). Chaque insert déclenche maintenant immédiatement les notifications @Query et re-renders. Amplifie l'effet de `c121230` mais ne crée pas le problème réseau.

---

## 2. Architecture actuelle de `download(album:)` + `_downloadSong`

### Séquence pour 1 track

```
download(album:) [DownloadService actor]
  └─ withTaskGroup : addTask pour chaque track
       └─ download(song:) [actor]
            ├─ await isDownloaded() → MainActor.run { ModelContext fetch }       [hop #1]
            ├─ inFlightTasks[key] = Task { _downloadSong(...) }
            └─ await task.value
                 └─ _downloadSong [actor]
                      ├─ serverService.activeCredentials()                        [réseau]
                      ├─ serverService.makeSwiftSonicClient()                     [réseau]
                      ├─ URLSession.shared.data(for: streamRequest)               [RÉSEAU AUDIO — tout en RAM]
                      ├─ FileManager.write(to:)                                   [I/O disque]
                      ├─ _downloadCoverArt(id:)  ← PER TRACK                     [RÉSEAU COVER ART]
                      │    ├─ fileExists check (idempotent)
                      │    └─ URLSession.shared.data(for: coverArtRequest)        [si fichier absent]
                      └─ await MainActor.run {                                    [hop #2 — bloquant]
                           mainContext.insert(record)
                           mainContext.save()    ← SYNCHRONE sur MainActor
                           → @Query notification → re-render vue entière
                         }
```

### Séquence pour N=23 tracks en parallèle

```
t=0  : 23 tasks démarrent simultanément.
       URLSession.shared : httpMaximumConnectionsPerHost = 6 (default iOS, non modifiable).
       Tasks 1-6  : connexion HTTP établie, download audio démarre.
       Tasks 7-23 : QUEUED dans URLSession, aucune connexion disponible, aucune donnée reçue.

t=0..? : 6 fichiers FLAC téléchargent, bande passante divisée entre les 6 connexions.
          Chaque connexion audio est bloquée pendant X secondes (selon taille FLAC).
          Les cover arts viennent du même host → compétition sur les mêmes 6 connexions.

t=60s : timeoutIntervalForRequest (60s, default URLRequest) fire pour les 17 tasks en queue.
         Aucune donnée reçue en 60 secondes → URLError.timedOut (ou similaire).
         Capturé dans do-catch du group.addTask → return false (SILENCIEUX, pas de log visible).

t=60+X: Les 6 connexions actives continuent. Sur les 6 initialement connectées :
         - 2 fichiers complètent → mainContext.save() × 2 → re-renders × 2
         - 4 restants sont potentiellement toujours en progress ou échouent (mémoire)

fin   : withTaskGroup drain → succeeded = 2, failed = 21
         isDownloadingAlbum = false → UI affiche partiallyDownloaded(2, 23)
```

### Config URLSession

`URLSession.shared` — configuration par défaut iOS, non modifiable :
- `httpMaximumConnectionsPerHost` : **6**
- `timeoutIntervalForRequest` : **60 secondes** (délai sans données incrémentielles → timeout)
- `timeoutIntervalForResource` : **7 jours** (non pertinent)
- Méthode : **`URLSession.data(for:)`** — charge le fichier ENTIER en RAM avant écriture disque

Pour un album de 23 FLAC haute résolution (50-200MB each) : peak RAM = 23 × 50-200MB = **1.1GB – 4.6GB** si toutes les tasks sont connectées simultanément. Avec les 6 connexions actives : 300MB–1.2GB.

### `_downloadCoverArt` per-track — race condition non synchronisée

Avec 23 tasks concurrentes, plusieurs terminent leur download audio dans une fenêtre rapprochée. Toutes appellent `_downloadCoverArt`. Le check `!FileManager.default.fileExists(atPath:)` n'est pas synchronisé entre les actor tasks. Plusieurs tasks peuvent voir `fileExists = false` simultanément et lancer N downloads de la même cover art. N downloads du même fichier sur le même host → N connexions supplémentaires en compétition.

---

## 3. @Query\<DownloadedTrack\> actifs dans le repo

| Fichier / struct | Prédicat | Re-fetches pour 23 inserts | Actif pendant album download ? |
|-----------------|----------|---------------------------|-------------------------------|
| `AlbumDetailView.downloadedAlbumTracks` | `$0.albumId == aid` | **23** | OUI (vue courante) |
| `AlbumSongRows.downloadedTracks` | `albumId == aid && serverId == sid` | **23** | OUI (sous-vue de AlbumDetailView) |
| `PlaylistDetailView.allDownloadedTracks` | **AUCUN** | **23** | Si PlaylistDetailView est en navigation stack |
| `PlaylistSongRows.downloadedTracks` | `serverId == sid` | **23** | Si PlaylistDetailView est en navigation stack |
| `ArtistListView.tracks` | `serverId == sid` | **23** | Si ArtistListView est en navigation stack |

**Minimum garanti pendant un download d'album depuis AlbumDetailView : 46 re-fetches.**

Chaque re-fetch `AlbumDetailView` déclenche un re-render incluant :
- LinearGradient background full-screen
- Header (cover art, metadata, progress indicator)
- 23 song rows (via AlbumSongRows)

Chaque re-fetch `AlbumSongRows` rebuild `downloadedSongIds` (Set construction sur tous les tracks) puis re-render 23 rows.

`downloadedPlaylistTracksCount(in:)` dans `PlaylistDetailView` : `Set(allDownloadedTracks.map(\.songId))` O(M) + filtre O(N×M) sur TOUS les DownloadedTrack à chaque insert — potentiellement coûteux si beaucoup de tracks téléchargés au total.

---

## 4. Hypothèses par symptôme

### Symptôme 1 : "1 minute avant premier track visible"

**[HAUTE] Hypothèse A — Bande passante divisée entre 23 downloads concurrents**

Preuve : `withTaskGroup` sans limite de concurrence (`9ebe4bb`). Avant (séquentiel) : le premier track complétait en T secondes. Après (concurrent) : la bande passante est divisée entre N connexions actives, chaque fichier prend N× plus longtemps. Si T_sequentiel = 5-10s, T_concurrent_premier = 30-70s. L'user ne voit aucune progression visible jusqu'à la première complétion (~60s).

**[HAUTE] Hypothèse B — 17 tasks en queue : aucune progression pendant 60s**

Preuve : 23 - 6 = 17 tasks n'ont jamais de connexion. La jauge de progression reste à "Starting download…" (downloaded = 0) jusqu'à la première complétion d'une des 6 connexions actives, qui peut prendre 60s si les fichiers sont grands.

**[MOYENNE] Hypothèse C — Cover art downloads saturent les connexions**

Preuve : `_downloadCoverArt` est appelé dans `_downloadSong` après chaque audio download. Pour les 6 premières connexions actives, après complétion audio, chacune tente un cover art download sur le même host. Avec un album (1 cover art), les 6 premières cover art requests ont 1 vrai hit + 5 qui voient `fileExists = true`. Overhead limité mais non nul, sur les mêmes 6 connexions.

**[BASSE] Hypothèse D — MainActor congestion**

Les saves et re-renders se produisent après le download réseau. Ne peuvent pas causer de délai avant le premier download visible.

---

### Symptôme 2 : "1 min 34 total pour 23 tracks"

**[HAUTE] Hypothèse A — Concurrent = même temps total que séquentiel en bandwidth-constrained**

Pour un débit total C MB/s et N fichiers de taille T :
- Séquentiel : durée_totale = N × T/C, premier_track = T/C
- Concurrent (6 connexions) : durée_totale ≈ N × T/C (identique), premier_track = N/6 × T/C (6× dégradé)

1min34 pour 23 tracks ≈ 4.1s/track en séquentiel. Cohérent avec des FLAC de taille modérée sur une connexion standard. La "régression" n'est pas une régression de débit total mais de **temps au premier résultat visible**.

---

### Symptôme 3 : "S'arrête à 2 tracks sur 23"

**[HAUTE] Hypothèse A — URLSession timeoutIntervalForRequest (60s) pour les 17 tasks en queue**

Preuve directe dans le code :

1. `URLSession.shared.data(for: request)` — `request` est un `URLRequest()` sans timeout personnalisé → `timeoutIntervalForRequest` = **60s** (default).
2. `httpMaximumConnectionsPerHost` = 6 → 17 tasks restent en queue URLSession, aucune donnée reçue.
3. À t=60s, les 17 tasks en queue reçoivent une erreur (timeout ou `URLError(.timedOut)`).
4. Dans `_downloadSong` : l'erreur propage jusqu'à `download(song:)` qui throw. Dans `withTaskGroup` :
   ```swift
   group.addTask {
       do {
           try await self.download(song: song, serverId: serverId)
           return true
       } catch {
           Logger.download.error(...)  // logué, mais silencieux pour l'UI
           return false               // ← résultat silencieusement "failed"
       }
   }
   ```
5. 17 false → isDownloadingAlbum = false → partiallyDownloaded(2, 23).

Note : les 6 connexions actives continuent après t=60s. Sur les 6, 2 complètent (petits fichiers ou connexions plus rapides), 4 échouent probablement pour mémoire ou timeout de la connexion active.

**[HAUTE] Hypothèse B — Memory pressure, iOS annule des URLSession tasks**

Preuve : `URLSession.data(for:)` charge le fichier entier en RAM. 6 FLAC concurrents à 50-200MB = 300MB–1.2GB en RAM pour le download seul (sans compter le reste de l'app). iOS envoie des memory warnings → annulation de URLSession tasks background → `URLError(.cancelled)` avalé par `do-catch`.

**[BASSE] Hypothèse C — Cancellation implicite via view lifecycle**

La task créée par `Button { Task { await vm.downloadAlbum() } }` est une **unstructured task** non liée au cycle de vie de la vue. Elle ne se cancel pas si la vue disparaît. Le `cancelAlbumDownload()` n'est appelé qu'explicitement par l'user via le bouton cancel. Peu probable sauf tap accidentel.

**[BASSE] Hypothèse D — mainContext.save() bloque le MainActor, delay dans les tasks**

Les saves se passent après le download réseau (URLSession). La congestion MainActor ne retarde pas l'acquisition des connexions URLSession ni les timeouts. Les tasks en queue URLSession ne sont pas affectées par la saturation MainActor.

---

## 5. Recommandations de fix (en mots, pas en code)

### Fix prioritaire 1 : limiter la concurrence dans `withTaskGroup`

**Cible** : `DownloadService.download(album:)` et `download(playlist:)`.

Réduire la concurrence à **3 downloads simultanés maximum**. Avec 3 connexions actives :
- Toutes les tasks obtiennent une connexion rapidement (pas de timeout de 60s par starvation)
- RAM peak = 3 × taille_FLAC au lieu de 23 (résout hypothèse B symptôme 3)
- Le premier track complète en T_séquentiel × 3/bande_passante au lieu de × 23 (résout symptôme 1)
- Le total time reste comparable au concurrent illimité mais avec coverage de 100% des tracks

Implémentation possible : `withTaskGroup` avec un `actor` limiter (slot counter), ou batching des songs en groupes de 3 avec loop séquentielle entre groupes. Alternative plus simple : remplacer `withTaskGroup` par une boucle séquentielle async pour revenir au comportement pre-`9ebe4bb` mais avec un `async let` batch de 3.

### Fix prioritaire 2 : remplacer `URLSession.data(for:)` par `URLSession.download(for:)`

**Cible** : `DownloadService._downloadSong`.

`URLSession.download(for:)` streame le fichier sur disque (temp file) sans jamais charger le contenu en RAM. Élimination du spike mémoire quelle que soit la concurrence. La complétion retourne une `URL` de fichier temporaire → `FileManager.moveItem(at:to:)`. Change le pattern de `data.write(to:)` à `FileManager.moveItem`.

Résout hypothèse B (memory pressure) et améliore la performance globale pour les grands fichiers.

### Fix complémentaire : filtrer `allDownloadedTracks` dans PlaylistDetailView

**Cible** : `PlaylistDetailView.@Query private var allDownloadedTracks`.

Workaround actuel : filtre impossible à l'init car `serverId` n'est pas statique. Solution : extraire la logique de comptage dans un sous-composant (analogue à `AlbumSongRows`) qui reçoit `serverId` en paramètre et initialise son `@Query` filtré dans son propre init. Évite les 23 re-fetches globaux de tous les DownloadedTrack.

### Fix cosmétique : déduplication cover art dans `_downloadSong`

**Cible** : appel `_downloadCoverArt` dans `_downloadSong`.

Pour les downloads d'album, la cover art devrait être téléchargée une seule fois en post-group (déjà fait dans `download(album:)`) et l'appel per-track retiré. Pour les downloads de track individuel (depuis `downloadSong`), garder le call per-track. Évite la race condition sur le `fileExists` check et réduit les requêtes réseau redondantes.

---

## 6. Questions ouvertes

1. **Taille exacte des FLAC** : Les hypothèses de timeout (60s queue) et mémoire dépendent de la taille des fichiers. Un `os_log(data.count)` dans `_downloadSong` (non intrusif) confirmerait l'ordre de grandeur. Si chaque FLAC fait < 20MB, le timeout n'est pas la cause principale.

2. **Comportement exact de `timeoutIntervalForRequest` pour une URLSession request en queue** : Apple ne documente pas clairement si le timer de 60s commence dès que la `URLRequest` est soumise ou dès l'établissement de la connexion. Si le timer commence seulement après connexion, les 17 tasks en queue ne timeouteraient pas à 60s — le problème serait alors purement memory pressure. Runtime test nécessaire.

3. **Memory footprint réel** : Instruments → Memory template sur device pendant un album download confirmerait ou infirmerait le memory pressure (hypothèse B). Chercher un spike à ~1GB+ et des memory warnings.

4. **Comportement Cloudflare / serveur custom** : Les `customHeaders` passés dans `URLRequest` pourraient interagir avec les politiques de connection Cloudflare (rate limiting, connection limits par IP). Un serveur Cloudflare proxied peut limiter à moins de 6 connexions simultanées vers l'origin. Non vérifiable statiquement.

5. **Régression exacte avant/après `9ebe4bb`** : Tester en checkoutant `9ebe4bb~1` (commit parent, download séquentiel) avec le même album confirmerait si le concurrent download est la source unique de la régression. Si le séquentiel est "grave rapide" et le concurrent échoue à 2/23, la cause est confirmée à 100%.

6. **iOS URLSession et `httpMaximumConnectionsPerHost` sur HTTP/2** : Sur HTTP/2 (qui multiplex plusieurs streams sur une seule connexion TCP), la limite de 6 connections s'applique différemment. Si le serveur supporte HTTP/2, URLSession peut envoyer plusieurs requests via multiplexing sur moins de connexions TCP. L'effet du `httpMaximumConnectionsPerHost` est alors différent. Non vérifiable sans connaissance du serveur cible.

---

## Résumé exécutif

| Symptôme | Cause principale | Commit source | Confiance |
|----------|-----------------|---------------|-----------|
| ~60s avant premier track visible | Bande passante divisée × 23, aucune progression tant que 0 track complete | `9ebe4bb` | Haute |
| 1min34 total | Même débit total que séquentiel, mais perçu différemment (tous en même temps vs progressif) | `9ebe4bb` | Haute |
| S'arrête à 2/23 | URLSession request timeout (60s sans connexion pour 17 tasks en queue) + possiblement memory pressure | `9ebe4bb` | Haute |
| Saturation MainActor | @Query sans filtre + mainContext.save par-track → re-renders coûteux × 23 | `c121230` + `03da0d6` | Haute (effet réel, secondaire vs réseau) |

**Fix prioritaire : limiter `withTaskGroup` à 3 downloads concurrents. Fix complémentaire : `URLSession.download(for:)` pour éliminer le RAM spike.**

Le commit `9ebe4bb` a introduit une concurrence illimitée qui interagit mal avec les limites de `URLSession.shared` (6 connexions/host, 60s timeout sans données) pour les fichiers de grande taille (FLAC). La régression n'est pas dans `DownloadService.swift` proprement dit mais dans la stratégie de concurrence choisie.
