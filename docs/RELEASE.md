# Releasing Cassette

Cassette ships through two independent channels, both triggered by pushing a
`v*` git tag (e.g. `v1.9.0`).

| Channel | Target | Driver | Artifact |
| --- | --- | --- | --- |
| iOS | TestFlight → App Store | **Xcode Cloud** (configured in App Store Connect) | `.ipa` uploaded to TestFlight |
| macOS | Direct download / Homebrew | **GitHub Actions** (`.github/workflows/release.yml`) | notarized `.dmg` on the GitHub Release, cask bumped in the tap |

The two channels do not depend on each other; a tag push fans out to both.

## Release flow

1. Bump the version locally if you want a specific marketing version, or let the
   pipelines derive it from the tag (both read `v<version>`).
2. Tag and push:
   ```sh
   git tag v1.9.0
   git push origin v1.9.0
   ```
3. **macOS (GitHub Actions):** archives the `Cassette` scheme for macOS with
   manual Developer ID signing, exports via `ExportOptions-DeveloperID.plist`,
   notarizes + staples the `.app` and `.dmg`, publishes a GitHub Release with the
   `.dmg`, then bumps `Casks/cassette.rb` in the tap repo.
4. **iOS (Xcode Cloud):** runs `ci_scripts/ci_pre_xcodebuild.sh` (syncs the
   marketing version from `$CI_TAG` via `agvtool`), builds, and uploads to
   TestFlight.

The version is derived from the tag name with the leading `v` stripped. On a
manual `workflow_dispatch` run (no tag), the macOS job builds `0.0.0-dev` and
**does not** publish a Release or bump the cask — both steps are guarded by
`if: github.ref_type == 'tag'`.

## Required GitHub secrets

Set these in the repo settings (Settings → Secrets and variables → Actions):

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERT_P12_BASE64` | Base64 of the Developer ID Application cert exported as `.p12` (with private key) |
| `DEVELOPER_ID_CERT_PASSWORD` | Password protecting that `.p12` |
| `KEYCHAIN_PASSWORD` | Arbitrary password for the temporary CI keychain |
| `AC_API_KEY_P8_BASE64` | Base64 of the App Store Connect API key (`.p8`), used for notarization |
| `AC_API_KEY_ID` | App Store Connect API key ID |
| `AC_API_ISSUER_ID` | App Store Connect API issuer ID |
| `HOMEBREW_TAP_TOKEN` | PAT with write access to `CassetteLab/homebrew-cassette` (resource owner must be the org, not a personal account) |

`ExportOptions-DeveloperID.plist` is committed (Team ID is not a secret). No
certificate, key, or password is stored in this repo.

## One-time human setup

1. **Developer ID cert:** create a *Developer ID Application* certificate on the
   developer portal, then export it **with its private key** as `.p12` from
   Keychain Access. Base64-encode it (`base64 -i cert.p12 | pbcopy`) into
   `DEVELOPER_ID_CERT_P12_BASE64`.
2. **App Store Connect API key:** create an API key, download the `.p8`, and
   base64-encode it into `AC_API_KEY_P8_BASE64`; record its key ID and issuer ID.
3. **Add the GitHub secrets** listed above.
4. **Homebrew tap:** add `Casks/cassette.rb` to `CassetteLab/homebrew-cassette`
   (separate repo). The workflow rewrites its `version` and `sha256` on each tag.
   `HOMEBREW_TAP_TOKEN` must be scoped to the **organisation** that owns the tap:
   a fine-grained PAT created with a personal resource owner authenticates as the
   user and is refused with a 403, which is how the v1.9.0 cask bump failed.
5. **Xcode Cloud:** create a tag-triggered (`v*`) iOS → TestFlight workflow in
   App Store Connect. It picks up `ci_scripts/ci_pre_xcodebuild.sh` automatically.
6. **Validate end-to-end** with a throwaway tag (e.g. `v0.0.1-rc1`), then delete
   it (`git push --delete origin v0.0.1-rc1`).

## Release history

Only user-visible changes. The full commit list is on each GitHub Release.

### 1.9.0

**Mood playlists.** Five server-side playlists — Night, Energetic, Workout,
Chill, Focus — rebuilt weekly from Wednesday onwards. Tracks come from
AudioMuse-AI's sonic analysis when an instance is configured, and from the
library's own genre, BPM and MOOD tags when it is not, so the feature works on
any Subsonic server with nothing to install. A mood that cannot be refreshed
keeps last week's playlist instead of emptying it, and each one gets a generated
cover uploaded to the server.

**Offline.** Artists, search and the artist screen now render from downloaded
music instead of showing nothing when the server is unreachable.

**Downloads.** Fixed tracks that could not be played at all after downloading.
Navidrome can declare a file as `m4a` while sending FLAC bytes, and the file
extension is what picks the playback engine's parser; downloads are now named
after the bytes they actually contain rather than the server's claim.

**Instant Mix.** The seed track starts immediately and the mix is grafted behind
it, so the ~30s of similarity queries happen over music rather than silence.
Available from a song, album, artist or the current track. On a server with no
similarity data it falls through to endless play instead of going quiet.

**Library.** An "All Songs" view with sorting. Grid/list toggles on the albums
list and on an artist's discography. Artist biographies from the server. A
virtual "best of" playlist per artist, built from the songs you liked.

**Player.** Endless play now clears loop and shuffle when enabled, and removes
the tracks it added when disabled.

**Favourites.** One star symbol everywhere, replacing the heart/star mix. The
playing track can be favourited from CarPlay and the Apple Watch remote — iOS's
own Lock Screen and Control Center have no slot for it and will not show one.

**Localisation.** The app is translated into eight languages.

### 1.8.4

Test-stub conformance fixes; no user-visible change.

## Project facts the pipeline relies on

- **Bundle ID:** `fr.mathieu-dubart.Cassette` · **Team ID:** `LK2358MPL8`
- **macOS minimum:** 15.0 (Sequoia) — the cask should declare
  `depends_on macos: ">= :sequoia"`.
- **Toolchain:** the workflow runs on `macos-26` and selects the newest stable
  Xcode via `maxim-lobanov/setup-xcode@v1` (`latest-stable`). The project is
  authored with Xcode 27, a 2026 beta not yet on hosted runners. If it fails to
  compile on the runner's GA Xcode because of a beta-only API, move to a
  self-hosted runner with Xcode 27 — App Store submission requires a GA Xcode
  anyway, so a beta-only dependency is a launch blocker to resolve regardless.
- **Versioning:** the `Cassette` target uses `apple-generic` versioning, which
  `agvtool` (the Xcode Cloud script) requires. The macOS job sets the version via
  `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` build-setting overrides, which
  flow into the generated `Info.plist`.

## Known things to check on the first run

- The Widgets extension is **iOS-only** (`SUPPORTED_PLATFORMS` excludes macOS).
  The macOS archive should skip it; if the macOS app is configured to embed it,
  the archive step will fail and the embed must be made platform-conditional.
- `create-dmg` cosmetics (icon coordinates, window size) assume a standard
  drag-to-Applications layout; adjust in `release.yml` if the volume looks off.
