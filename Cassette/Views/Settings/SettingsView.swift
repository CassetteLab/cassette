// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import OSLog
import SwiftSonic

struct SettingsView: View {
    @Environment(\.appContainer) private var container
    @State private var downloadsVM: DownloadsViewModel?

    var body: some View {
        Group {
            if let downloadsVM {
                form(downloadsVM: downloadsVM)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .cassetteContentWidth()
        .navigationTitle("Settings")
        .task {
            guard let container else { return }
            if downloadsVM == nil {
                downloadsVM = DownloadsViewModel(
                    modelContainer: container.modelContainer,
                    downloadService: container.downloadService,
                    serverState: container.serverState
                )
            }
            await downloadsVM?.loadData()
        }
    }

    private func form(downloadsVM: DownloadsViewModel) -> some View {
        Form {
            DownloadsSectionView(vm: downloadsVM)
            CacheSectionView()
            serverSection()
            aboutSection()
            #if DEBUG
            debugSection()
            #endif
        }
        .formStyle(.grouped)
        .refreshable {
            await downloadsVM.loadData()
        }
    }

    // MARK: - Sections

    private func serverSection() -> some View {
        Section("Server") {
            if let server = container?.serverState.activeServer {
                LabeledContent {
                    Text(server.displayName)
                } label: {
                    Label {
                        Text("Connected to")
                    } icon: {
                        SettingsIcon(systemImage: "server.rack", color: Color.cassetteAccent)
                    }
                }
                LabeledContent {
                    Text(server.baseURL)
                } label: {
                    Label {
                        Text("Address")
                    } icon: {
                        SettingsIcon(systemImage: "link", color: .blue)
                    }
                }
                LabeledContent {
                    Text(server.username)
                } label: {
                    Label {
                        Text("Username")
                    } icon: {
                        SettingsIcon(systemImage: "person.fill", color: .purple)
                    }
                }
            } else {
                Text("No server configured.")
                    .foregroundStyle(.secondary)
            }
            // TODO(v1.x): multi-server management (add / remove / switch servers)
        }
    }

    #if DEBUG
    private func debugSection() -> some View {
        Section("Debug") {
            Button("Print Wrapped — This Month") {
                Task { await printWrapped(period: .currentMonth(), tag: "[WRAPPED-DEBUG-MONTH]") }
            }
            Button("Print Wrapped — Previous Month") {
                Task { await printWrapped(period: .previousMonth(), tag: "[WRAPPED-DEBUG-PREV]") }
            }
            Button("Print Wrapped — This Year") {
                Task { await printWrapped(period: .currentYear(), tag: "[WRAPPED-DEBUG-YEAR]") }
            }
            Button("Seed Previous Month — 10 events") {
                Task { await seedPreviousMonth() }
            }
            Button("Force Wrapped Monthly Update") {
                Task {
                    guard let container,
                          let sid = container.serverState.activeServer?.id.uuidString else {
                        Logger.wrapped.warning("[WRAPPED-DEBUG] No active server")
                        return
                    }
                    await container.wrappedPlaylistService.handleYearTransitionIfNeeded(
                        serverId: sid, calendar: .current)
                    let result = await container.wrappedPlaylistService.runMonthlyUpdateIfNeeded(
                        serverId: sid, calendar: .current)
                    Logger.wrapped.info("[WRAPPED-DEBUG] result=\(String(describing: result), privacy: .public)")
                }
            }
            Button("Dump Wrapped UserDefaults") {
                dumpWrappedUserDefaults()
            }
            Button("Reset Wrapped State (current server)", role: .destructive) {
                guard let container,
                      let sid = container.serverState.activeServer?.id.uuidString else {
                    Logger.wrapped.warning("[WRAPPED-RESET] No active server")
                    return
                }
                resetWrappedState(serverId: sid)
            }
        }
    }

    private func dumpWrappedUserDefaults() {
        let ud = UserDefaults.standard
        let prefix = "cassette.wrapped."
        let allKeys = ud.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }.sorted()
        if allKeys.isEmpty {
            Logger.wrapped.info("[WRAPPED-DUMP] No cassette.wrapped.* keys found in UserDefaults")
        } else {
            Logger.wrapped.info("[WRAPPED-DUMP] Found \(allKeys.count, privacy: .public) cassette.wrapped.* key(s):")
            for key in allKeys {
                let value = ud.object(forKey: key)
                Logger.wrapped.info("[WRAPPED-DUMP] \(key, privacy: .public) = \(String(describing: value), privacy: .public)")
            }
        }
    }

    private func resetWrappedState(serverId: String) {
        let ud = UserDefaults.standard
        let keysToRemove = ud.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("cassette.wrapped.") && $0.hasSuffix(".\(serverId)")
        }
        for key in keysToRemove {
            ud.removeObject(forKey: key)
        }
        Logger.wrapped.info("[WRAPPED-RESET] Cleared \(keysToRemove.count, privacy: .public) key(s) for serverId=\(serverId, privacy: .public)")
    }

    private func seedPreviousMonth() async {
        guard let container,
              let sid = container.serverState.activeServer?.id.uuidString else {
            Logger.stats.warning("[WRAPPED-SEED] No active server — aborting")
            return
        }

        let cal = Calendar.current
        let now = Date()
        let startOfCurrentMonth = cal.date(from: DateComponents(
            year: cal.component(.year, from: now),
            month: cal.component(.month, from: now),
            day: 1
        ))!
        let startOfPrevMonth = cal.date(byAdding: .month, value: -1, to: startOfCurrentMonth)!
        let prevYear = cal.component(.year, from: startOfPrevMonth)
        let prevMonth = cal.component(.month, from: startOfPrevMonth)

        func dayInPrevMonth(_ day: Int, hour: Int = 12) -> Date {
            cal.date(from: DateComponents(
                year: prevYear, month: prevMonth, day: day, hour: hour
            )) ?? startOfPrevMonth
        }

        // Try to fetch 5 real songs; fall back to synthetic stubs if unavailable
        var realSongs: [Song]? = nil
        do {
            let fetched = try await container.libraryService.randomSongs(size: 5)
            if !fetched.isEmpty { realSongs = fetched }
        } catch {
            Logger.stats.warning("[WRAPPED-SEED] Failed to fetch random songs: \(error, privacy: .public) — using synthetic stubs (Navidrome playlist will not reference real tracks)")
        }

        let events: [PlaybackEventDTO]
        if let songs = realSongs {
            func dto(_ s: Song, day: Int, hour: Int = 12, fraction: Double = 1.0, completed: Bool = true) -> PlaybackEventDTO {
                let dur = TimeInterval(s.duration ?? 240)
                return PlaybackEventDTO(
                    trackId: s.id,
                    trackTitle: s.title,
                    albumId: s.albumId,
                    albumTitle: s.album,
                    artistId: s.artistId,
                    artistName: s.artist ?? s.displayArtist ?? "Unknown",
                    genre: s.genres?.first?.name ?? s.genre,
                    timestamp: dayInPrevMonth(day, hour: hour),
                    durationListened: dur * fraction,
                    trackDuration: dur,
                    wasCompleted: completed,
                    serverId: sid
                )
            }
            let t0 = songs[0], t1 = songs[1], t2 = songs[2]
            let t3 = songs.count > 3 ? songs[3] : songs[0]
            let t4 = songs.count > 4 ? songs[4] : songs[1]
            events = [
                dto(t0, day: 3,  hour: 10),
                dto(t0, day: 5,  hour: 14),
                dto(t1, day: 5,  hour: 15),
                dto(t2, day: 8,  hour: 9),
                dto(t2, day: 9,  hour: 11),
                dto(t2, day: 10, hour: 8,  fraction: 0.92, completed: false),
                dto(t3, day: 12, hour: 20, fraction: 0.60, completed: false),
                dto(t4, day: 15, hour: 18, fraction: 0.50, completed: false),
                dto(t0, day: 18, hour: 21),
                dto(t1, day: 20, hour: 16),
            ]
            let ids = songs.prefix(5).map(\.id).joined(separator: ", ")
            Logger.stats.info("[WRAPPED-SEED] Seeded 10 events for \(prevYear, privacy: .public)-\(String(format: "%02d", prevMonth), privacy: .public) using REAL Navidrome tracks: \(ids, privacy: .public)")
        } else {
            events = [
                PlaybackEventDTO(trackId: "seed-t1", trackTitle: "Track [seed] Alpha",
                                 albumId: "seed-alb1", albumTitle: "Album [seed] Q1",
                                 artistId: "seed-art1", artistName: "Artist [seed] One",
                                 genre: "Indie [seed]",
                                 timestamp: dayInPrevMonth(3, hour: 10),
                                 durationListened: 210, trackDuration: 220,
                                 wasCompleted: true, serverId: sid),
                PlaybackEventDTO(trackId: "seed-t1", trackTitle: "Track [seed] Alpha",
                                 albumId: "seed-alb1", albumTitle: "Album [seed] Q1",
                                 artistId: "seed-art1", artistName: "Artist [seed] One",
                                 genre: "Indie [seed]",
                                 timestamp: dayInPrevMonth(5, hour: 14),
                                 durationListened: 215, trackDuration: 220,
                                 wasCompleted: true, serverId: sid),
                PlaybackEventDTO(trackId: "seed-t2", trackTitle: "Track [seed] Beta",
                                 albumId: "seed-alb1", albumTitle: "Album [seed] Q1",
                                 artistId: "seed-art1", artistName: "Artist [seed] One",
                                 genre: "Indie [seed]",
                                 timestamp: dayInPrevMonth(5, hour: 15),
                                 durationListened: 180, trackDuration: 195,
                                 wasCompleted: true, serverId: sid),
                PlaybackEventDTO(trackId: "seed-t3", trackTitle: "Track [seed] Gamma",
                                 albumId: "seed-alb2", albumTitle: "Album [seed] Q2",
                                 artistId: "seed-art2", artistName: "Artist [seed] Two",
                                 genre: "Jazz [seed]",
                                 timestamp: dayInPrevMonth(8, hour: 9),
                                 durationListened: 240, trackDuration: 250,
                                 wasCompleted: true, serverId: sid),
                PlaybackEventDTO(trackId: "seed-t3", trackTitle: "Track [seed] Gamma",
                                 albumId: "seed-alb2", albumTitle: "Album [seed] Q2",
                                 artistId: "seed-art2", artistName: "Artist [seed] Two",
                                 genre: "Jazz [seed]",
                                 timestamp: dayInPrevMonth(9, hour: 11),
                                 durationListened: 235, trackDuration: 250,
                                 wasCompleted: true, serverId: sid),
                PlaybackEventDTO(trackId: "seed-t3", trackTitle: "Track [seed] Gamma",
                                 albumId: "seed-alb2", albumTitle: "Album [seed] Q2",
                                 artistId: "seed-art2", artistName: "Artist [seed] Two",
                                 genre: "Jazz [seed]",
                                 timestamp: dayInPrevMonth(10, hour: 8),
                                 durationListened: 230, trackDuration: 250,
                                 wasCompleted: false, serverId: sid),
                PlaybackEventDTO(trackId: "seed-t4", trackTitle: "Track [seed] Delta",
                                 albumId: "seed-alb2", albumTitle: "Album [seed] Q2",
                                 artistId: "seed-art3", artistName: "Artist [seed] Three",
                                 genre: "Jazz [seed]",
                                 timestamp: dayInPrevMonth(12, hour: 20),
                                 durationListened: 120, trackDuration: 200,
                                 wasCompleted: false, serverId: sid),
                PlaybackEventDTO(trackId: "seed-t5", trackTitle: "Track [seed] Epsilon",
                                 albumId: "seed-alb1", albumTitle: "Album [seed] Q1",
                                 artistId: "seed-art3", artistName: "Artist [seed] Three",
                                 genre: "Indie [seed]",
                                 timestamp: dayInPrevMonth(15, hour: 18),
                                 durationListened: 90, trackDuration: 180,
                                 wasCompleted: false, serverId: sid),
                PlaybackEventDTO(trackId: "seed-t1", trackTitle: "Track [seed] Alpha",
                                 albumId: "seed-alb1", albumTitle: "Album [seed] Q1",
                                 artistId: "seed-art1", artistName: "Artist [seed] One",
                                 genre: "Indie [seed]",
                                 timestamp: dayInPrevMonth(18, hour: 21),
                                 durationListened: 218, trackDuration: 220,
                                 wasCompleted: true, serverId: sid),
                PlaybackEventDTO(trackId: "seed-t2", trackTitle: "Track [seed] Beta",
                                 albumId: "seed-alb1", albumTitle: "Album [seed] Q1",
                                 artistId: "seed-art1", artistName: "Artist [seed] One",
                                 genre: "Indie [seed]",
                                 timestamp: dayInPrevMonth(20, hour: 16),
                                 durationListened: 185, trackDuration: 195,
                                 wasCompleted: true, serverId: sid),
            ]
            Logger.stats.info("[WRAPPED-SEED] Seeded \(events.count, privacy: .public) synthetic events for \(prevYear, privacy: .public)-\(String(format: "%02d", prevMonth), privacy: .public) (serverId=\(sid, privacy: .public))")
        }

        for event in events {
            await container.statsService.recordPlayback(event)
        }
    }

    private func printWrapped(period: WrappedPeriod, tag: String) async {
        guard let container,
              let sid = container.serverState.activeServer?.id.uuidString else {
            Logger.stats.warning("\(tag, privacy: .public) No active server — aborting")
            return
        }
        let data = await container.statsService.wrappedData(for: period, serverId: sid, calendar: .current)
        Logger.stats.info("\(tag, privacy: .public) period=\(data.period.displayName, privacy: .public)")
        Logger.stats.info("\(tag, privacy: .public) totalSeconds=\(data.totalSecondsListened, privacy: .public)")
        Logger.stats.info("\(tag, privacy: .public) totalTracksPlayed=\(data.totalTracksPlayed, privacy: .public)")
        Logger.stats.info("\(tag, privacy: .public) totalUniqueTracks=\(data.totalUniqueTracks, privacy: .public)")
        Logger.stats.info("\(tag, privacy: .public) totalUniqueArtists=\(data.totalUniqueArtists, privacy: .public)")
        Logger.stats.info("\(tag, privacy: .public) totalUniqueAlbums=\(data.totalUniqueAlbums, privacy: .public)")
        Logger.stats.info("\(tag, privacy: .public) streakDays=\(data.streakDays, privacy: .public)")
        Logger.stats.info("\(tag, privacy: .public) dominantGenre=\(data.dominantGenre ?? "nil", privacy: .public)")
        for track in data.topTracks {
            Logger.stats.info("\(tag, privacy: .public) track #\(track.rank, privacy: .public): \(track.title, privacy: .public) — \(track.artistName, privacy: .public) — \(Int(track.totalSecondsListened), privacy: .public)s × \(track.playCount, privacy: .public)")
        }
        for album in data.topAlbums {
            Logger.stats.info("\(tag, privacy: .public) album #\(album.rank, privacy: .public): \(album.title, privacy: .public) — \(album.artistName, privacy: .public) — \(Int(album.totalSecondsListened), privacy: .public)s × \(album.playCount, privacy: .public)")
        }
        for artist in data.topArtists {
            Logger.stats.info("\(tag, privacy: .public) artist #\(artist.rank, privacy: .public): \(artist.name, privacy: .public) — \(Int(artist.totalSecondsListened), privacy: .public)s × \(artist.playCount, privacy: .public)")
        }
        Logger.stats.info("\(tag, privacy: .public) firstTrack=\(data.firstTrackOfPeriod?.title ?? "nil", privacy: .public)")
        Logger.stats.info("\(tag, privacy: .public) lastTrack=\(data.lastTrackOfPeriod?.title ?? "nil", privacy: .public)")
    }
    #endif

    private func aboutSection() -> some View {
        Section("About") {
            LabeledContent {
                Text("Cassette")
            } label: {
                Label {
                    Text("App")
                } icon: {
                    SettingsIcon(systemImage: "info.circle.fill", color: .blue)
                }
            }
            Link(destination: URL(string: "https://github.com/MathieuDubart/cassette")!) {
                Label {
                    Text("GitHub Repository")
                } icon: {
                    SettingsIcon(systemImage: "chevron.left.forwardslash.chevron.right", color: .gray)
                }
            }
            // TODO(v1.0): display Bundle version, add GPL license note, SwiftSonic MIT attribution
        }
    }
}

// MARK: - Shared icon component

struct SettingsIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Cache section

struct CacheSectionView: View {
    @Environment(\.appContainer) private var container
    @State private var usedBytes: Int64 = 0
    @State private var trackCount: Int = 0
    @State private var isClearing: Bool = false

    private var cacheSettings: CacheSettings? { container?.cacheSettings }

    var body: some View {
        let maxTracks = cacheSettings?.maxTracks ?? 10

        return Section {
            LabeledContent {
                Text(usageDescription(maxTracks: maxTracks))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } label: {
                Label {
                    Text("Used")
                } icon: {
                    SettingsIcon(systemImage: "externaldrive.fill", color: .green)
                }
            }

            if let cacheSettings {
                Stepper(
                    value: Binding(
                        get: { cacheSettings.maxTracks },
                        set: { cacheSettings.maxTracks = max(1, min(10, $0)) }
                    ),
                    in: 1...10
                ) {
                    HStack {
                        Label {
                            Text("Max tracks")
                        } icon: {
                            SettingsIcon(systemImage: "tray.full.fill", color: Color.cassetteAccent)
                        }
                        Spacer()
                        Text("\(maxTracks)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .font(.body.weight(.medium))
                    }
                }
            }

            if let cacheSettings {
                Picker(selection: Binding<CacheFormat>(
                    get: { cacheSettings.cacheFormat },
                    set: { newValue in cacheSettings.cacheFormat = newValue }
                )) {
                    ForEach(CacheFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                } label: {
                    Label {
                        Text("Format")
                    } icon: {
                        SettingsIcon(systemImage: "waveform", color: .purple)
                    }
                }
                .pickerStyle(.menu)
            }

            if let cacheSettings {
                Toggle(isOn: Binding(
                    get: { cacheSettings.cacheOverCellular },
                    set: { cacheSettings.cacheOverCellular = $0 }
                )) {
                    Label {
                        Text("Use cellular data")
                    } icon: {
                        SettingsIcon(systemImage: "antenna.radiowaves.left.and.right", color: .blue)
                    }
                }
            }

            Button(role: .destructive) {
                Task { await clearCache() }
            } label: {
                if isClearing {
                    HStack(spacing: CassetteSpacing.s) {
                        ProgressView().scaleEffect(0.8)
                        Text("Clearing…")
                    }
                } else {
                    Label("Clear cache", systemImage: "trash.fill")
                }
            }
            .disabled(isClearing || (usedBytes == 0 && trackCount == 0))

        } header: {
            Text("Cache")
        } footer: {
            Text("Cached tracks let recently-played music load instantly without re-fetching from the server. Cache is automatic, sliding window — the oldest track is replaced when the limit is reached.")
        }
        .task {
            await refreshUsage()
        }
        .onChange(of: cacheSettings?.maxTracks) { _, newValue in
            guard let newValue else { return }
            Task {
                await container?.cacheService.setMaxTracks(newValue)
                await refreshUsage()
            }
        }
    }

    // MARK: - Helpers

    private func usageDescription(maxTracks: Int) -> String {
        let bytesString = ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file)
        return "\(bytesString) · \(trackCount)/\(maxTracks) tracks"
    }

    private func refreshUsage() async {
        guard let container else { return }
        let bytes = await container.cacheService.usedBytes
        let count = await container.cacheService.trackCount
        usedBytes = bytes
        trackCount = count
    }

    private func clearCache() async {
        guard let container else { return }
        isClearing = true
        defer { isClearing = false }
        await container.cacheService.clearAll()
        container.dominantColorExtractor.clearCache()
        await refreshUsage()
    }
}

// MARK: - Downloads section

struct DownloadsSectionView: View {
    let vm: DownloadsViewModel

    var body: some View {
        Section {
            LabeledContent {
                Text(vm.usedBytesFormatted)
                    .foregroundStyle(.secondary)
            } label: {
                Label {
                    Text("Used")
                } icon: {
                    SettingsIcon(systemImage: "arrow.down.circle.fill", color: .green)
                }
            }

            if !vm.displayAlbums.isEmpty {
                DisclosureGroup {
                    ForEach(vm.displayAlbums) { album in
                        HStack(spacing: CassetteSpacing.m) {
                            CoverArtCard(id: album.coverArtId ?? album.albumId, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                if let total = album.totalTracksCount {
                                    Text("\(album.downloadedTracksCount)/\(total) tracks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(album.downloadedTracksCount) track\(album.downloadedTracksCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await vm.removeAlbum(album) }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } label: {
                    Label {
                        Text("Albums (\(vm.displayAlbums.count))")
                    } icon: {
                        SettingsIcon(systemImage: "music.note.list", color: Color.cassetteAccent)
                    }
                }
            }

            if !vm.downloadedPlaylists.isEmpty {
                DisclosureGroup {
                    ForEach(vm.downloadedPlaylists) { playlist in
                        HStack(spacing: CassetteSpacing.m) {
                            CoverArtCard(id: playlist.playlistId, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text("\(playlist.tracksCount)/\(playlist.totalTracksCount) tracks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await vm.removePlaylist(playlist) }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } label: {
                    Label {
                        Text("Playlists (\(vm.downloadedPlaylists.count))")
                    } icon: {
                        SettingsIcon(systemImage: "list.bullet", color: .indigo)
                    }
                }
            }

            if vm.displayAlbums.isEmpty && vm.downloadedPlaylists.isEmpty {
                Text("No downloaded content.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            Button(role: .destructive) {
                Task { await vm.clearAll() }
            } label: {
                if vm.isClearingAll {
                    HStack(spacing: CassetteSpacing.s) {
                        ProgressView().scaleEffect(0.8)
                        Text("Clearing…")
                    }
                } else {
                    Label("Clear all downloads", systemImage: "trash.fill")
                }
            }
            .disabled(vm.isClearingAll || (vm.displayAlbums.isEmpty && vm.downloadedPlaylists.isEmpty))

        } header: {
            Text("Downloads")
        } footer: {
            Text("Downloaded tracks are stored permanently and available offline.")
        }
    }
}
