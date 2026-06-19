// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

// MARK: - Player navigation helpers

func postNavigateToAlbum(track: DisplayableSong) {
    guard let albumId = track.albumId else { return }
    NotificationCenter.default.post(
        name: .cassetteNavigateToAlbum,
        object: nil,
        userInfo: [
            "albumId":   albumId,
            "albumName": track.albumName ?? "",
            "coverArtId": track.coverArtId as Any
        ]
    )
}

func postNavigateToArtist(track: DisplayableSong) {
    guard let artistId = track.artistId else { return }
    postNavigateToArtist(artistId: artistId, artistName: track.artist ?? "", coverArtId: track.coverArtId)
}

func postNavigateToArtist(artistId: String, artistName: String, coverArtId: String?) {
    NotificationCenter.default.post(
        name: .cassetteNavigateToArtist,
        object: nil,
        userInfo: [
            "artistId":   artistId,
            "artistName": artistName,
            "coverArtId": coverArtId as Any
        ]
    )
}

extension Notification.Name {
    static let cassetteTogglePlayPause = Notification.Name("cassette.togglePlayPause")
    static let cassetteSkipNext = Notification.Name("cassette.skipNext")
    static let cassetteSkipPrevious = Notification.Name("cassette.skipPrevious")
    static let cassetteFocusSearch = Notification.Name("cassette.focusSearch")
    static let cassetteToggleShuffle = Notification.Name("cassette.toggleShuffle")
    static let cassetteToggleRepeat = Notification.Name("cassette.toggleRepeat")
    static let cassetteToggleQueue = Notification.Name("cassette.toggleQueue")
    static let cassetteOpenFullPlayer = Notification.Name("cassette.openFullPlayer")
    static let cassetteOpenFullPlayerLyrics = Notification.Name("cassette.openFullPlayerLyrics")
    static let cassetteSelectAlbums = Notification.Name("cassette.selectAlbums")
    static let cassetteNavigateToAlbum  = Notification.Name("cassetteNavigateToAlbum")
    static let cassetteNavigateToArtist = Notification.Name("cassetteNavigateToArtist")
}
