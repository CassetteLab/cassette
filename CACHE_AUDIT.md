# Cache v1.4 — SwiftSonic Stream API Audit (Phase 3 prep)

Audit statique. Aucune modification de code, aucun build.  
Date : 2026-05-01.  
SwiftSonic version : **0.6.1** (revision `bd5c7b52`, github.com/MathieuDubart/swiftsonic)  
Source : `DerivedData/.../SourcePackages/checkouts/swiftsonic/`

---

## 1. streamURL — signatures complètes

Fichier source : `Sources/swiftsonic/Endpoints/SwiftSonicClient+Media.swift`

### Overloads disponibles

Seul **un** overload existe pour `streamURL` :

```swift
nonisolated func streamURL(
    id: String,
    maxBitRate: Int? = nil,
    format: String? = nil,
    timeOffset: Int? = nil,
    size: String? = nil,
    estimateContentLength: Bool? = nil,
    converted: Bool? = nil
) -> URL?
```

Tous les paramètres sont optionnels sauf `id`. La méthode est `nonisolated`, compatible avec des appels depuis n'importe quel contexte d'isolation.

### Méthodes stream/download adjacentes

```swift
// Téléchargement direct (pas de transcoding)
nonisolated func downloadURL(id: String) -> URL?

// HLS — pas de format, bitrate via audioBitRate
nonisolated func hlsURL(
    id: String,
    audioBitRate: Int? = nil,
    audioTrack: String? = nil
) -> URL?

// Cover art
nonisolated func coverArtURL(id: String, size: Int? = nil) -> URL?

// Avatar utilisateur
nonisolated func avatarURL(username: String) -> URL?
```

---

## 2. Support format / bitrate

**Les deux paramètres sont présents et fonctionnels dans `streamURL`.**

| Paramètre Subsonic | Param SwiftSonic | Type | Présent |
|---|---|---|:---:|
| `format` | `format` | `String?` | ✓ |
| `maxBitRate` | `maxBitRate` | `Int?` (kbps) | ✓ |
| `timeOffset` | `timeOffset` | `Int?` (secondes) | ✓ |
| `estimateContentLength` | `estimateContentLength` | `Bool?` | ✓ |
| `converted` | `converted` | `Bool?` | ✓ |
| `size` | `size` | `String?` | ✓ |

### Implémentation interne

Les params sont convertis en `[String: String]` et passés à `requestBuilder.mediaURL(endpoint:params:)` :

```swift
var params: [String: String] = ["id": id]
if let v = maxBitRate            { params["maxBitRate"]            = String(v) }
if let v = format                { params["format"]                = v }
if let v = timeOffset            { params["timeOffset"]            = String(v) }
if let v = size                  { params["size"]                  = v }
if let v = estimateContentLength { params["estimateContentLength"] = v ? "true" : "false" }
if let v = converted             { params["converted"]             = v ? "true" : "false" }
return requestBuilder.mediaURL(endpoint: "stream", params: params)
```

Aucune validation côté SwiftSonic — les valeurs sont transmises telles quelles au serveur. La spec Subsonic délègue la validation des codecs à l'implémentation serveur (Navidrome, Subsonic, etc.).

---

## 3. Types enum pour les formats

**Absent.** Il n'existe pas de `StreamFormat`, `AudioFormat` ou équivalent dans SwiftSonic.

- Le format est passé comme `String?` brut.
- Valeurs valides selon la spec Subsonic : `"mp3"`, `"flac"`, `"ogg"`, `"opus"`, `"aac"`, `"raw"` (bypass transcoding).
- Le modèle `Song` contient `transcodedContentType: String?` et `transcodedSuffix: String?` (métadonnées du format transcodé tel que servi, pas d'enum non plus).

**Conséquence pour phase 3** : si on veut une API fortement typée côté Cassette, il faudra définir l'enum dans Cassette (pas dans SwiftSonic). SwiftSonic restera avec le `String?`.

---

## 4. Verdict

| Question | Réponse |
|---|---|
| Patch SwiftSonic requis ? | **Non** |
| `format` exposé ? | Oui — `String?` |
| `maxBitRate` exposé ? | Oui — `Int?` kbps |
| Enum format exposé ? | Non — à créer dans Cassette si besoin |
| Utilisable tel quel pour phase 3 ? | **Oui** |

SwiftSonic 0.6.1 implémente l'intégralité des paramètres Subsonic standard pour l'endpoint `stream.view`. Aucune modification du package n'est requise.

---

## 5. Usage phase 3 — pattern à suivre

Dans `CacheService.store()` (phase 2) ou dans le futur call site phase 3, passer directement les params à `streamURL` :

```swift
// Exemples d'appels depuis MediaResolver ou PlayerService (phase 3)
let url = client.streamURL(id: songId)                          // stream format serveur
let url = client.streamURL(id: songId, format: "mp3", maxBitRate: 320)
let url = client.streamURL(id: songId, format: "opus", maxBitRate: 128)
let url = client.streamURL(id: songId, format: "raw")           // original sans transcoding
```

`downloadURL` est distinct et ne supporte pas le transcoding — il renvoie le fichier original tel quel. À ne pas confondre avec `streamURL(format: "raw")`.

---

## 6. Observations annexes

- **`downloadURL` sans transcoding** : si l'utilisateur choisit "format original" pour le cache, il y a deux options — `streamURL(id:, format: "raw")` (même pipeline que le stream, juste sans transcoding) ou `downloadURL(id:)` (téléchargement direct, pas de custom headers auth via le path — attention si Navidrome est derrière un reverse proxy qui vérifie les headers). Préférer `streamURL(format: "raw")` pour la cohérence des headers.

- **`hlsURL` non pertinent** pour le cache : HLS segmenté n'est pas trivial à reassembler en fichier unique. Cache phase 3 utilisera exclusivement `streamURL`.

- **`nonisolated`** sur toutes les URL builders : cohérent avec l'usage dans MediaResolver (actor) qui les appelle sans `await`. Compatible Swift 6.

- **Return type `URL?`** : peut retourner `nil` si les credentials sont invalides ou si l'URL ne peut pas être construite. Le call site doit gérer le `nil` (déjà fait dans MediaResolver via `guard let streamURL`).

- **Pas de validation bitrate** côté SwiftSonic : `maxBitRate: 0` signifie "pas de limite" selon la spec Subsonic. Si on passe `maxBitRate: 0`, le serveur ne tronscodera pas. Il vaut mieux passer `nil` pour "pas de préférence" — SwiftSonic omet le param si `nil`, ce qui est équivalent mais plus propre.
