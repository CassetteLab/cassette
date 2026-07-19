---
type: "query"
date: "2026-07-18T22:17:01.299429+00:00"
question: "comment est géré le cache dans l'entierté de l'app et le offline ? Normalement il y a un système de cache qui gère toutes les métadonnées et les infos relatives aux albums, playlists, searches.... et il y a aussi un système de remux pour le m4a faststart qui est implémenté. Or rien de tout ce qui est prévu/implémenté pour le offline ne fonctionne actuellement."
contributor: "graphify"
outcome: "useful"
source_nodes: ["CacheService", "CacheServiceProtocol", "MediaResolver", "LibraryService", "AudioFaststartRemuxer", "DownloadService", "PlayerService", "CachedTrack", "DownloadedTrack", "FavoriteRecord"]
---

# Q: comment est géré le cache dans l'entierté de l'app et le offline ? Normalement il y a un système de cache qui gère toutes les métadonnées et les infos relatives aux albums, playlists, searches.... et il y a aussi un système de remux pour le m4a faststart qui est implémenté. Or rien de tout ce qui est prévu/implémenté pour le offline ne fonctionne actuellement.

## Answer

Expanded from original query via vocab: [cache, cached, offline, remux, remuxer, faststart, moov, metadata, expiry, stale, invalidate, prefetch]. Then traversed BFS (cache/offline) + DFS (remux) and verified in source. FINDING 1: there is NO metadata cache in the app and there never was. None of the 13 @Model types persists AlbumID3, SearchResult3 or PlaylistWithSongs. CacheService (despite its name) is a FIFO window of 10 recently-streamed AUDIO FILES in Caches/, not metadata (CacheService.swift:19-27). LibraryService is a pure pass-through to SwiftSonicClient; its only SwiftData access is offlineSmartShuffle reading DownloadedTrack (LibraryService.swift:497). Three cache layers exist — audio (CacheService), artwork (ArtworkImageCache), lyrics (CachedLyrics) — and zero for library metadata. FINDING 2: the m4a faststart remux DOES work and is wired at two sites — DownloadService.swift:319 (after each song download, before the fileSize read) and AppContainer.migrateM4AFaststartIfNeeded called from CassetteApp.swift:110 (one-shot migration). Covered by 11 tests in AudioFaststartRemuxerTests. GAP: files cached from stream never get remuxed — PlayerService.swift:1829 stores raw bytes via cacheService.store() with no classify step, so a mdat-first m4a played from cache keeps its seek problem while the same track downloaded gets fixed. FINDING 3: offline playback is sound (MediaResolver.swift:31-61 resolves download then cache then offline-guard then stream) but offline NAVIGATION is not, because every list screen calls LibraryService which hits the network. Offline only downloads-derived content can render. Conclusion: offline is not broken, it is absent — the metadata persistence layer was never built.

## Outcome

- Signal: useful

## Source Nodes

- CacheService
- CacheServiceProtocol
- MediaResolver
- LibraryService
- AudioFaststartRemuxer
- DownloadService
- PlayerService
- CachedTrack
- DownloadedTrack
- FavoriteRecord