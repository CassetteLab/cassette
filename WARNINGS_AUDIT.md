# Cassette — Audit des warnings (2026-04-24)

## Résumé

| Catégorie | Nombre | Statut |
|---|---|---|
| Concurrence Swift 6 | 6 | À corriger |
| Deprecated APIs | 0 | — |
| Code mort / inutilisé | 0 | — |
| Divers | 0 | — |
| **Total** | **6** | |

Un seul warning AppIntents (`appintentsmetadataprocessor`) issu du build system
Xcode, non lié à notre code — ignoré.

---

## Catégorie 1 — Concurrence (6 warnings, priorité haute)

### Cause racine unique

Le build setting `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` rend toutes les
propriétés `static let` d'une extension implicitement `@MainActor`. Les nine
propriétés de `extension Logger` dans `Logger+Cassette.swift` sont donc
`@MainActor`-isolées. Quand elles sont lues depuis un acteur non-MainActor
(`KeychainService`, `MediaResolver`), Swift 6 produit un warning — qui sera une
**erreur** en mode strict.

### Détail

| Fichier | Ligne | Propriété accédée | Contexte d'accès |
|---|---|---|---|
| `Keychain/KeychainService.swift` | 25 | `Logger.keychain` | `actor KeychainService.store` |
| `Keychain/KeychainService.swift` | 44 | `Logger.keychain` | `actor KeychainService.retrieve` |
| `Keychain/KeychainService.swift` | 61 | `Logger.keychain` | `actor KeychainService.delete` |
| `Services/Implementations/MediaResolver.swift` | 26 | `Logger.resolver` | `actor MediaResolver.resolve` |
| `Services/Implementations/MediaResolver.swift` | 33 | `Logger.resolver` | `actor MediaResolver.resolve` |
| `Services/Implementations/MediaResolver.swift` | 45 | `Logger.resolver` | `actor MediaResolver.resolve` |

### Correction prévue

**Fichier unique à modifier : `Utilities/Logger+Cassette.swift`**

Ajouter `nonisolated` sur toutes les propriétés statiques. `Logger` est un
`struct` `Sendable` d'OSLog — partager son instance entre acteurs est sûr et
c'est l'usage prévu par Apple.

```swift
// Avant
static let keychain = Logger(subsystem: "app.cassette.keychain", category: "KeychainService")

// Après
nonisolated static let keychain = Logger(subsystem: "app.cassette.keychain", category: "KeychainService")
```

Même correction sur les 8 autres propriétés (`server`, `player`, `library`,
`cache`, `download`, `resolver`, `nowPlaying`, `ui`).

- **Complexité** : triviale (une ligne de diff, 9 propriétés)
- **Commit** : `refactor(concurrency): mark Logger extension properties nonisolated`

---

## Warnings volontairement ignorés

Aucun.

---

## Résidu AppIntents (non-bloquant)

```
warning: Metadata extraction skipped. No AppIntents.framework dependency found.
```

Produit par le processeur Xcode `appintentsmetadataprocessor` sur tout projet
sans AppIntents. Non lié à notre code, non supprimable sans ajouter AppIntents.
Acceptable dans l'état actuel de Cassette v1.
