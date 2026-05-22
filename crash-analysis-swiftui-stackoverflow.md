# Crash Analysis — SwiftUI Stack Overflow (macOS 26.5, v1.7 build 15)

**Date :** 2026-05-22  
**Version :** 1.7 (15) — TestFlight  
**OS :** macOS 26.5 (25F71) — Mac Catalyst  
**Exception :** `EXC_BAD_ACCESS (SIGSEGV)` — `KERN_PROTECTION_FAILURE` (Stack Guard page)

---

## Signature du crash

```
Thread 0 — ~54 000 frames récursifs
Pattern : StyleableView._makeViewList ↔ StyleModifier._makeViewList (cycle A→B→A→B…)
Trigger : _UINavigationParallaxTransition (swipe-back ou push de navigation)
Root cause frame : swift_conformsToProtocol2 → StyleableView._makeViewList
```

Ce n'est **pas** un `ViewModifier` qui s'appelle directement lui-même. C'est le **système d'héritage de styles SwiftUI** qui boucle infiniment lors de la résolution de conformances de types (`swift_conformsToProtocol2` au frame 5).

---

## Suspect #1 — `Glass.regular.interactive()` dans `cassetteGlassButton` (PRINCIPAL)

**Fichier :** `DesignSystem/Components/GlassButtonModifier.swift:15,30`

```swift
let glass: Glass = tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive()
```

`.interactive()` n'est pas anodin : il enveloppe la vue en interne avec un `StyleModifier` propre au système Liquid Glass pour les animations de pression. Ce `StyleModifier` s'injecte dans l'environnement de style SwiftUI. Si la vue parente est elle-même un `StyleableView` qui propage un style concurrent (ex : l'environnement du `NavigationStack` en cours de transition), SwiftUI essaie de les composer — et le cycle `StyleableView._makeViewList → StyleModifier._makeViewList → StyleableView…` boucle indéfiniment.

### Tous les call sites en navigation

| Fichier | Lignes |
|---|---|
| `Views/Platform/macOS/AlbumDetailMacOS.swift` | 133, 149, 160 |
| `Views/Platform/macOS/ArtistDetailMacOS.swift` | 167 |
| `Views/Platform/macOS/PlaylistDetailMacOS.swift` | 177, 192, 208, 219, 235 |
| `Views/Browse/AlbumDetailView.swift` | 399, 426, 435, 444, 452, 462, 471 |
| `Views/Browse/PlaylistDetailView.swift` | 573, 593, 602, 610, 620, 629 |
| `Views/Main/FullPlayerView.swift` | 307, 348 |

Toutes ces pages sont des **destinations de navigation**. Le crash se produit précisément pendant `_UINavigationParallaxTransition`, c'est-à-dire au moment où SwiftUI compose simultanément la vue source et la vue destination.

---

## Suspect #2 — `BottomPlayerBar` avec `glassEffect` en overlay permanent sur le `NavigationStack`

**Fichiers :** `Views/Platform/macOS/BottomPlayerBar.swift:59–67` / `Views/Platform/macOS/RootViewMacOS.swift:45–50`

```swift
// RootViewMacOS.swift — le BottomPlayerBar est toujours présent pendant les transitions
.overlay(alignment: .bottom) {
    BottomPlayerBar(...)
}

// BottomPlayerBar.swift — glassEffect non-interactif
Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
```

Le `BottomPlayerBar` est un **overlay permanent** sur le `NavigationStack`. Il contient un `.glassEffect` non-interactif, mais sa présence constante dans la hiérarchie de style pendant toutes les transitions de navigation en fait un facteur aggravant : c'est la couche Glass "ambiante" dans laquelle les children de navigation sont évalués.

---

## Suspect #3 — Double `glassEffect` dans `FullPlayerExpandedView` (mineur)

**Fichier :** `Views/Platform/macOS/FullPlayerExpandedView.swift:82,101`

```swift
Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
```

Deux instances dans la même vue. Non-interactif, mais le pattern `shape → fill → glassEffect` crée une pile `StyleableView → StyleModifier → StyleModifier` qui contribue à la profondeur de résolution de styles.

---

## Mécanisme hypothétique

SwiftUI 6 / macOS 26 implémente Liquid Glass via le système `StyleModifier`/`StyleableView` (le même pipeline que `buttonStyle`, `listStyle`, etc.).

Quand `.interactive()` est actif, la `Glass` installe un `StyleModifier` qui doit être "résolu" par rapport au contexte parent. Si ce parent est lui-même en cours d'évaluation (cas d'une transition de navigation qui compose simultanément deux hiérarchies de vues), le moteur de style entre dans un cycle de résolution A→B→A→B.

**Trigger exact :** swipe-back (ou push) vers une page contenant plusieurs `cassetteGlassButton(.interactive())`, pendant que `BottomPlayerBar` (Glass dans l'overlay) est dans le même pass de layout.

---

## Ce qui N'est PAS la cause

- Aucun `ViewModifier` custom dans le codebase ne s'appelle lui-même directement.
- `ShimmerModifier`, `ToastOverlay`, `SongContextMenuModifier`, `ContentWidthModifier`, `CassetteCoverModifier` sont tous linéaires et ne touchent pas au système de style.
- Les commits récents (5 derniers) ne modifient pas les vues incriminées.
- `GlassButtonModifier.swift` lui-même n'est pas récursif — c'est l'effet runtime de `.interactive()` qui est problématique.

---

## Fix proposé

Retirer `.interactive()` de `cassetteGlassButton` et `cassetteGlassCapsule` :

```swift
// Avant
let glass: Glass = tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive()

// Après
let glass: Glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
```

**Validation :** reproduire le crash sur macOS 26.5 (swipe-back depuis un album ou une playlist), puis confirmer sa disparition après le fix. Si `.interactive()` est fonctionnellement nécessaire pour l'animation de pression, l'alternative est d'appliquer le style uniquement hors d'un contexte de navigation (ex : `PrimitiveButtonStyle` custom qui délègue à Glass sans passer par le système de style SwiftUI).
