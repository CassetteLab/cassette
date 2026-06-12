# CarPlay-readiness — known-issues audit (2026-06-12)

Phase 2 of "clean before CarPlay". Full inventory of known issues across code
markers (`TODO`, `KI-`, `deferred`…), local docs (APP_FEEDBACK.md), CONTRIBUTING,
and git history (the v1.0 `KI-1/2/3` definitions were recovered from
`Beta_FEEDBACK.md`, deleted in 08b3d69). Each issue is triaged for CarPlay, which
leans on queue navigation, MPRemoteCommandCenter, AVAudioSession routing, and
now-playing metadata.

Sweep notes: `FIXME`/`HACK`/`XXX`/`won't fix` markers — zero real hits. All
`deferred` hits are benign design comments, not issues. The
`INVESTIGATION_scrubber_drift.md` working doc was local-only (gitignored) and no
longer exists; the FLAC-drift assessment below is grounded in code only.

## Triage table

| ID | What it is | Location | Symptom / limitation | Verdict | Reason |
|----|-----------|----------|---------------------|---------|--------|
| CR-01 | MPRemote skip/previous after sleep | NowPlayingService.swift (active `[RCC]` debug-log instrumentation, 9 sites) | Lock-screen/remote next-previous commands unresponsive after device sleep | **BLOCKING** | Remote commands ARE the CarPlay control surface; already Phase 3 scope |
| CR-02 | AVAudioSession `setActive` Code=-50 | PlayerService.swift:1824 (retry once after 0.5 s) | Another app holds the session; activation fails, single blind retry | **INVESTIGATE** | CarPlay does constant session handoffs (nav prompts, Siri, calls); capture alongside CR-01 in the Phase 3 device session |
| CR-03 | KI-3 — lock-screen scrubber stuck at end on repeat-one restart (v1.0) | handleEndOfTrack `.one` branch; periodic `pushPosition` (NowPlayingService) likely self-corrects within a tick | Scrubber briefly stuck at end; controls briefly desynced | **INVESTIGATE** | Declared fixed in v1.0.1, path since rewritten on AudioStreaming; never re-verified on device. Cosmetic if present, but on CarPlay's primary screen — verify in the same Phase 3 session |
| CR-04 | `resume()` cold-start reuses stored `currentSource` | PlayerService.swift `resume()` (`audioPlayer.state == .ready` path; source captured by session restore / end-of-album rewind) | A resolution captured earlier (possibly a stream URL) is replayed without re-resolving; stale if connectivity changed since | **INVESTIGATE** | "Get in the car and press play on a restored session" is THE CarPlay entry path; a stale stream URL fails silently. Cheap fix candidate: re-resolve on cold-start resume |
| CR-05 | KI-1 — repeat-all doesn't auto-restart at end of queue (v1.0) | Fixed: `skipToNext()` repeat-`.all` wrap branch + `do/catch` in `handleEndOfTrack` (28f0b4b, then AudioStreaming rewrite) | — | **RESOLVED (stale)** | Wrap branch present and exercised at HEAD; do not carry |
| CR-06 | KI-2 — auto-next intermittent on poor network (v1.0) | Fixed: errors logged not swallowed (v1.0.1) + keychain AfterFirstUnlock for locked transitions (b31c6c3) | Residual: a mid-queue resolve failure on a dead network stops playback with a logged error (by design) | **RESOLVED (stale)** / residual DEFERRABLE | Root cause (`try?` swallow) gone; residual stop is honest behavior, not CarPlay-specific, and further mitigated by the cache-validity work |
| CR-07 | Scrubber / FLAC seek drift | Seek path guards: `audioPlayer.isSeekable` (PlayerService:1127, 1642); transcoded/VBR byte-offset seeking is approximate | Position can drift after seeking in FLAC/transcoded streams; playback itself unaffected | **DEFERRABLE** | Confirmed non-functional (accuracy only); already accepted; periodic `pushPosition` keeps lock screen in sync |
| CR-08 | savePlayQueue / getPlayQueue server sync are stubs | LibraryService.swift:122,126; LibraryServiceProtocol:74; QueueSnapshot.swift TODO | No cross-device queue sync; local QueueSnapshot restore works | DEFERRABLE | CarPlay uses the local in-app queue; server sync is a cross-device nicety |
| CR-09 | Downloads die if app is killed (foreground URLSession) | DownloadService.swift:11 TODO(v1.x) | No resume-after-kill for downloads | DEFERRABLE | Not in the playback path; CarPlay doesn't download |
| CR-10 | cacheSession 30 s resource timeout caps large-file caching on slow links | PlayerService.swift:301 TODO(crossfade-followup) | Post-start cache writes of big files abort on slow links (prefetchSession at 300 s is unaffected) | DEFERRABLE | Cache miss falls back to stream; no functional break |
| CR-11 | No background cache write alongside live stream | MediaResolver.swift:54 TODO(v1.x) | First listen of a track always streams fully | DEFERRABLE | Optimization, not a defect |
| CR-12 | Close-delimited truncated transcode can be cached as complete | Documented in AudioResponseValidator (accepted limitation of the cache-validity fix) | Rare partial-but-audible cached audio on connection drop without Content-Length | DEFERRABLE | Audible degradation, not silence; bounded by validator (non-audio/empty rejected) |
| CR-13 | Rapid-fire request spots (favorite toggle per tap, `syncFromServer` per connectivity flip, scrobble per skip) | FavoritesService call sites; MainTabView `.task(id: isOnline)`; startPlayback | Server chatter bursts on rapid input | DEFERRABLE | Server load only; surfaced during the search-debounce recon, unchanged |
| CR-14 | SwiftSonic friction backlog (error taxonomy LNP/DNS indistinguishable, `.cannotFindHost` marked transient → 3 useless retries, star/unstar API shape, no starred dates) | APP_FEEDBACK.md friction log | Coarser error UX; ~3 s of pointless retries on deterministic DNS failures | DEFERRABLE | Library-side backlog; marginal error-surfacing delay, no functional break |
| CR-15 | "Étape 8" UI leftovers (FullPlayer slider overflow, macOS gray header background, default dismiss chevron) | APP_FEEDBACK.md § Known UI issues | Visual polish items from v1.0 | DEFERRABLE (likely stale) | Pure UI, no CarPlay surface; list predates several UI reworks — re-verify visually whenever convenient |
| CR-16 | `playNext()` residual `try?` swallow (APP_FEEDBACK 2026-04-27) | Fixed at HEAD: `do/catch` + `Logger.player.error` | — | **RESOLVED (stale)** | Do not carry |
| CR-17 | DownloadedTrack has no local play-date | offlineSmartShuffle comment (roadmap) | Offline shuffle can't filter by recency | DEFERRABLE | Cosmetic selection quality, offline-only |
| CR-18 | Roadmap TODOs (multi-server mgmt, PHPicker migration, lyrics TTL, alphabet headers macOS, mini-bar download, Glass composition rdar) | various (16 TODO sites) | Feature roadmap, not defects | DEFERRABLE | No CarPlay interaction |
| CR-19 | Known acceptable warning: `appintentsmetadataprocessor` (macOS builds) | CONTRIBUTING § Known acceptable warnings | Toolchain notice | DEFERRABLE (documented) | Not an issue; listed for completeness |

## Blocking list (Phase 3/4 scope)

1. **CR-01 — MPRemote skip/previous after sleep** (BLOCKING, already Phase 3).
   Active `[RCC]` debug instrumentation is in place in NowPlayingService.
2. **CR-02 — AVAudioSession Code=-50** (INVESTIGATE, same Phase 3 device
   session — session-activation territory CarPlay stresses hardest).
3. **CR-03 — KI-3 repeat-one lock-screen scrubber** (INVESTIGATE, fold into the
   same device session; 5-minute verification, likely self-resolved).
4. **CR-04 — stale `currentSource` on cold-start resume** (INVESTIGATE; the
   CarPlay entry path; candidate one-line fix: re-resolve through MediaResolver
   on the cold-start branch of `resume()`).

Everything else is deferrable or stale. KI-1/KI-2 (queue transitions) resolved —
queue navigation is NOT a CarPlay blocker at HEAD.

## Deferrable backlog

CR-06 (residual), CR-07 through CR-15, CR-17, CR-18 — ordered roughly by
user-visible impact: CR-07 (FLAC seek accuracy), CR-12 (truncated transcode),
CR-13 (request bursts), CR-10/CR-11 (cache coverage), CR-08/CR-09 (queue sync /
background downloads), CR-14 (SwiftSonic ergonomics), CR-15/CR-17/CR-18 (polish
and roadmap).
