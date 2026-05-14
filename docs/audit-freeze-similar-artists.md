# Audit — freeze au tap similar artist

## Contexte

Quand l'user tap sur un similar artist dans `ArtistDetailView`, l'app freeze
indéfiniment (~2-3 min en debug Xcode, pas de watchdog kill, pas de crash).

---

## Section A — Timeouts URLSession

`similarArtists(mbid:)` dans `ListenBrainzClient.swift` utilise le transport injecté
(`any ListenBrainzTransport`) sans override de timeout sur le `URLRequest` :

```swift
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Accept")
// timeoutInterval non set → 60s default
```

Le transport en production (`CustomHeadersTransport`) enveloppe `URLSession.shared` :
- `timeoutIntervalForRequest` = 60s (temps avant premier octet)
- `timeoutIntervalForResource` = 604 800s (7 jours — défaut URLSession)

**Verdict A** : Les timeouts URLSession pour l'endpoint LB ne peuvent pas causer un
freeze > 60s seuls. La cause est ailleurs.

---

## Section B — LibraryService index lazy

Code de construction de l'index (`LibraryService.swift:230-243`) :

```swift
func findArtist(byName name: String) async -> ArtistID3? {
    if artistNameIndex == nil { await buildArtistNameIndex() }
    return artistNameIndex?[Self.normalizeArtistName(name)]
}

private func buildArtistNameIndex() async {
    guard let indices = try? await artists() else { return }  // réseau Subsonic
    let all = indices.flatMap { $0.artist }
    artistNameIndex = Dictionary(
        all.map { (Self.normalizeArtistName($0.name), $0) },
        uniquingKeysWith: { first, _ in first }
    )
}
```

| Point | Réponse |
|---|---|
| Construction | Lazy — premier appel à `findArtist(byName:)` |
| Source des données | `getArtists()` — 1 seul appel réseau Subsonic |
| Actor | `LibraryService` actor (les 18 appels d'enrichment sont séquentiels) |
| Ré-entrance | Non dangereuse ici : les appels de la boucle for-await sont séquentiels, seul le premier déclenche le build |
| SwiftData | Aucun — fetch Subsonic HTTP uniquement |

**Verdict B** : L'index est déjà construit **avant** que l'user puisse taper (les
similar artists sont affichés seulement après la fin du chargement). Pas la cause
du freeze.

---

## Section C — Logique de tap dans SimilarArtistCell

```swift
// ArtistDetailView.swift — SimilarArtistCell.body
if recommendation.inLibrary {
    NavigationLink(destination: {
        ArtistDetailView(artist: ArtistID3(id: recommendation.id, name: recommendation.name))
    }) {
        cellContent
    }
    .buttonStyle(.plain)
} else {
    Button(action: onOutOfLibraryTap) { cellContent }
    .buttonStyle(.plain)
}
```

| Point | Réponse |
|---|---|
| `recommendation.id` quand `inLibrary == true` via LBProvider | `libraryArtist.id` — vrai Subsonic ID ✓ |
| `recommendation.id` quand `inLibrary == true` via SubsonicProvider | `$0.id` de `getArtistInfo2.similarArtist` — Subsonic ID fourni par le serveur, **pas vérifié comme réellement dans la lib de l'user** ⚠️ |
| Fiabilité du flag `inLibrary` | Buggé côté SubsonicProvider (voir Section E) |

---

## Section D — ArtistDetailView init avec ArtistID3 minimal

`ArtistID3(id:name:)` — tous les autres paramètres ont des defaults dans SwiftSonic.
L'init est léger, pas de computation lourde.

Quand `.task` fire sur la vue pushée :

```
load()
  → libraryService.artist(id: artistB.id)     → getArtist Subsonic (~200ms) ✓
  → loadSimilarArtists()
      → recommendationService.similarArtists(to: artistB.id)
          → LBProvider.similarArtists(...)     → voir Section E ⚠️
          → SubsonicProvider.similarArtists(...) → voir Section E ⚠️
```

Si `artistId` est un vrai Subsonic ID (`inLibrary: true` via LBProvider), le
`getArtist(id:)` réussit normalement. Pas un freeze.

---

## Section E — Cause racine confirmée : double appel getArtistInfo2 séquentiel

### Flux complet lors du tap sur similar artist B

```
1. NavigationLink push → ArtistDetailView(B).task → viewModel.load()
2.   libraryService.artist(id: B.id)                          ~200ms  ✓
3.   loadSimilarArtists()
4.     recommendationService.similarArtists(to: B.id)
5.       LBProvider.similarArtists(toArtistID: B.id, limit: 20):
           libraryService.getArtistMBID(B.id)
             → client().getArtistInfo2(id: B.id, count: 0)    ← réseau Subsonic
               → Subsonic → Last.fm / MusicBrainz (lookup externe)
               → peut hanger jusqu'à 60s (timeout URLRequest)
             ← si timeout → catches error → return []
6.       LBProvider retourne [] → RecommendationService passe au suivant
7.       SubsonicProvider.similarArtists(toArtistID: B.id, limit: 20):
           client().getArtistInfo2(id: B.id, count: 20)       ← MÊME endpoint Subsonic
             → MÊME call Last.fm / MusicBrainz
             → peut hanger encore 60s
                                                     ─────────────────
                                             Total : jusqu'à 120s
```

### Code incriminé

**LBProvider** (`ListenBrainzRecommendationProvider.swift:88-93`) :
```swift
guard let resolved = try await libraryService.getArtistMBID(forArtistID: artistID) else {
    return []
}
```

**LibraryService** (`LibraryService.swift:225-228`) :
```swift
func getArtistMBID(forArtistID artistID: String) async throws -> String? {
    let info = try await client().getArtistInfo2(id: artistID, count: 0)
    return info.musicBrainzId
}
```

**SubsonicProvider** (`SubsonicRecommendationProvider.swift:31`) :
```swift
func similarArtists(toArtistID: String, limit: Int) async throws -> [SimilarArtistRecommendation] {
    let info = try await client().getArtistInfo2(id: toArtistID, count: limit)  // count: 20
    ...
}
```

**Ordre dans AppContainer** (`AppContainer.swift:120`) :
```swift
recommendationService = RecommendationService(providers: [lbProvider, subsonicProvider])
```

### Pourquoi le serveur est lent

`getArtistInfo2` déclenche un lookup externe côté Navidrome (Last.fm / MusicBrainz)
pour les artistes non encore enrichis. Ce lookup externe peut :
- prendre 30-120s si le service externe est lent
- ne pas avoir de timeout propre côté serveur

Le `timeoutIntervalForRequest` de 60s côté iOS finit par killer le premier appel.
Puis SubsonicProvider refait le même appel — autre 60s.

### Bug bonus : faux `inLibrary: true` dans SubsonicProvider

```swift
// SubsonicRecommendationProvider.swift:32-34
return (info.similarArtist ?? []).prefix(limit).map {
    SimilarArtistRecommendation(id: $0.id, name: $0.name, coverArt: $0.coverArt,
                                inLibrary: true,  // ← inconditionnellement true
                                mbid: $0.musicBrainzId)
}
```

Les similar artists de `getArtistInfo2` sont des artistes connus du serveur via
Last.fm/MB, pas nécessairement présents dans la lib de l'user. Résultat :
NavigationLink poussé pour des artistes qui afficheront "No Albums".

---

## Section F — Cause #1 et options de fix

### Cause identifiée

**Double appel séquentiel à `getArtistInfo2` sur le même artiste** — une fois par
LBProvider (`count: 0`) pour le MBID, une fois par SubsonicProvider (`count: 20`)
pour les similar artists. Chaque appel peut hanger 60s si le serveur fait un
lookup externe lent.

Le main thread n'est pas bloqué (pas de watchdog kill en debug). L'UI est réactive
mais `isLoadingSimilarArtists == true` pendant toute la durée → skeleton perpetuel
perçu comme freeze par l'user.

---

### Options de fix (à valider avant implémentation)

#### Option A — Un seul appel `getArtistInfo2`, résultat partagé *(recommandée)*

Faire un seul `getArtistInfo2(id:, count: limit)` dans `LibraryService` qui retourne
à la fois le MBID et la liste de similar artists Subsonic. Les deux providers
consomment ce résultat sans refaire de réseau.

Avantage : élimine le double appel à la racine. Un seul appel lent possible au lieu
de deux.

#### Option B — Cache MBID dans LibraryService

Ajouter un `[String: String?]` dans `LibraryService` pour cacher les résultats de
`getArtistMBID`. Évite le re-fetch sur les visites répétées du même artiste.

Limite : ne résout pas la première visite.

#### Option C — Timeout court sur MBID

Wrapper `getArtistMBID` dans une `Task` avec un timeout explicite (ex: 5s). Si pas
de MBID en 5s → LBProvider renvoie `[]` rapidement. SubsonicProvider prend le
relai. Réduit la fenêtre de freeze de 60+60s à 5+60s.

#### Option D — Supprimer SubsonicProvider des similar artists

`SubsonicRecommendationProvider.freshReleases` retourne déjà `[]`. On pourrait
faire pareil pour `similarArtists` et ne garder que LBProvider pour ce use-case.
Simplifie, élimine le second appel, mais perd le fallback Subsonic.

---

### Fichiers à modifier (selon option choisie)

| Fichier | Changement |
|---|---|
| `LibraryService.swift` | A : nouvelle méthode `getArtistInfo(forArtistID:count:)` avec cache ; B : cache MBID |
| `LibraryServiceProtocol.swift` | A/B : signature mise à jour |
| `ListenBrainzRecommendationProvider.swift` | A : utilise la nouvelle méthode partagée |
| `SubsonicRecommendationProvider.swift` | A : utilise le résultat partagé ; D : retourne `[]` |
| `AppContainer.swift` | Injection mise à jour si besoin |
