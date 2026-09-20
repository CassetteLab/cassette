// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

/// Both cover caches share one directory and are told apart only by the `@` in the filename.
/// Getting that split wrong in one direction leaves stale artwork; getting it wrong in the other
/// deletes the covers of offline downloads, which nothing re-creates short of downloading the
/// tracks again. These pin the classification both caches read.
///
/// Deliberately not exercised against the real directory: it lives under Documents, shared with
/// the app host — whose launch-time legacy sweep deletes bare `{id}` files from a detached task —
/// and with every other suite, so a filesystem test there races rather than measures.
@Suite("Cover cache — which files are clearable")
struct ClearStreamingCoversTests {

    @Test("tier files are streaming cache and may be cleared", arguments: [
        "abc123@thumb",
        "abc123@hero",
        "playlist-7@thumb",
        "id-with-dashes@hero",
    ])
    func tierFilesAreClearable(name: String) {
        #expect(DownloadService.isStreamingCoverFile(name))
    }

    @Test("bare ids belong to offline downloads and must survive", arguments: [
        "abc123",
        "playlist-7",
        "id-with-dashes",
        "al-60",
    ])
    func bareIdsAreProtected(name: String) {
        #expect(!DownloadService.isStreamingCoverFile(name))
    }

    @Test("an id containing @ is still classified by the suffix, not by luck")
    func idWithAtSign() {
        // A server is free to hand out a cover id containing '@'. Such an id's own file is
        // indistinguishable from a tier file, which is a known limit of the naming scheme —
        // this pins the current behaviour rather than pretending otherwise.
        #expect(DownloadService.isStreamingCoverFile("weird@id"))
    }
}
