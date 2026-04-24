# 🎵 Cassette

**A native iOS and macOS client for Subsonic and OpenSubsonic servers. Stream your self-hosted music library.**

<!-- TODO(v1.0): replace placeholder with real banner image at assets/banner.png
![Cassette banner](assets/banner.png)
-->

[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0--or--later-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B%20%7C%20macOS%2014%2B-blue.svg)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange.svg)](https://swift.org)
<!-- TODO(v1.0): uncomment once available on the App Store
[![App Store](https://img.shields.io/badge/App%20Store-available-blue?logo=apple)](https://apps.apple.com/...)
-->
<!-- TODO(v1.0): uncomment once CI is configured
[![CI](https://github.com/MathieuDubart/Cassette/actions/workflows/ci.yml/badge.svg)](https://github.com/MathieuDubart/Cassette/actions)
-->

---

## Screenshots

<!-- TODO(v1.0): replace with real screenshots
| Browse | Player | Downloads |
|--------|--------|-----------|
| ![Browse](docs/screenshots/browse.png) | ![Player](docs/screenshots/player.png) | ![Downloads](docs/screenshots/downloads.png) |
-->

---

## Features

- Native iOS and macOS app built entirely with SwiftUI
- Streams from any Subsonic or OpenSubsonic compatible server (Navidrome, Gonic, Ampache, and others)
- Browse your library by artists, albums, and playlists
- Full-text search across your entire collection
- Background playback with lock screen controls and AirPlay support
- Offline playback — download albums and playlists for listening without a connection
- Ephemeral cache to reduce repeated network requests for recently played tracks
- Custom HTTP headers support for servers behind reverse proxies such as Cloudflare Access
- Credentials stored in the system Keychain — no plaintext passwords written to disk

---

## Requirements

- iOS 17 or later
- macOS 14 or later
- A running Subsonic or OpenSubsonic compatible server ([Navidrome](https://www.navidrome.org) is recommended)

---

## Installation

<!-- TODO(v1.0): uncomment once available on the App Store
### App Store

Download Cassette from the App Store: [link]
-->

### Build from source

1. Clone the repository:
   ```
   git clone https://github.com/MathieuDubart/Cassette.git
   ```
2. Open `Cassette.xcodeproj` in Xcode 16 or later.
3. Select the **Cassette** target and your desired destination (iPhone, iPad, or Mac).
4. Press **Run** (⌘R).

No additional package manager setup is required — dependencies are resolved automatically via Swift Package Manager.

---

## Usage

1. Open Cassette on your device.
2. Enter your Subsonic server URL, username, and password.
3. If your server sits behind a reverse proxy that requires custom request headers (Cloudflare Access, for example), expand **Advanced** and add the required headers.
4. Tap **Connect** — Cassette verifies the connection and stores your credentials securely.
5. Start browsing your library.

> **Compatibility note:** Cassette works with any server implementing the Subsonic API v1.16.1 or the OpenSubsonic extension. It has been tested primarily against [Navidrome](https://www.navidrome.org).

---

## Architecture

Cassette is built with SwiftUI and Swift Concurrency throughout. All network and I/O work runs inside Swift actors, keeping the UI layer free of concurrency concerns. Subsonic API interactions are handled by [SwiftSonic](https://github.com/MathieuDubart/swiftsonic), a separate Swift package developed alongside this project. Local persistence uses SwiftData for cached tracks, downloaded content, and server configuration; credentials are stored exclusively in the system Keychain. Playback is backed by AVFoundation, with MPNowPlayingInfoCenter and MPRemoteCommandCenter wired for lock screen, Control Center, and external accessory integration. The service layer is structured as protocol-bound actors to keep the path clear for a future CarPlay extension.

---

## Roadmap

**Coming next**
- macOS refinements (v1.1)
- CarPlay support (v1.2)
- Widgets and Live Activities
- Synchronized lyrics (OpenSubsonic extension)
- Last.fm scrobbling

**Under consideration**
- Multi-server switching in Settings
- Smart playlists generated locally
- iPad-optimized layout

---

## Dependencies

| Package | License | Purpose |
|---------|---------|---------|
| [SwiftSonic](https://github.com/MathieuDubart/swiftsonic) | MIT | Swift client library for the Subsonic and OpenSubsonic APIs |

SwiftSonic is developed by the same author and evolves in step with Cassette. The MIT license is compatible with GPL-3.0-or-later.

---

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. All contributions are licensed under GPL-3.0-or-later.

---

## License

Cassette is free software, licensed under the **GNU General Public License v3.0 or later**.

- You are free to use, study, modify, and distribute this software.
- Any modified version you distribute must also be released under the GPL-3.0-or-later.
- The source code must remain available to anyone who receives the software.
- There is no warranty, to the extent permitted by applicable law.

See the [LICENSE](LICENSE) file for the full text.

The [SwiftSonic](https://github.com/MathieuDubart/swiftsonic) dependency is MIT-licensed and GPL-compatible.

---

## Acknowledgements

- The [Navidrome](https://www.navidrome.org) team for their excellent self-hosted music server.
- The [OpenSubsonic](https://opensubsonic.netlify.app) community for modernizing the Subsonic API specification.
- Apple for the SwiftUI, AVFoundation, and SwiftData frameworks.

---

## Author

**Mathieu Dubart** — [github.com/MathieuDubart](https://github.com/MathieuDubart)
