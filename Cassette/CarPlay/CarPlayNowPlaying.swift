// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import CarPlay
import OSLog

/// The Now Playing screen's extra controls.
///
/// Artwork, title, scrubber and transport come from `NowPlayingService` through
/// MPNowPlayingInfoCenter, and the favourite button from the like command it already registers —
/// none of that is rebuilt here. This adds only what CarPlay cannot infer: shuffle, repeat, and
/// the queue behind Up Next.
@MainActor
final class CarPlayNowPlaying: NSObject, CPNowPlayingTemplateObserver {
    private weak var library: CarPlayLibrary?

    init(library: CarPlayLibrary) {
        self.library = library
        super.init()
    }

    func configure() {
        let template = CPNowPlayingTemplate.shared
        template.add(self)
        template.isUpNextButtonEnabled = true
        template.upNextTitle = "Queue"
        refreshButtons()
    }

    func refreshButtons() {
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([shuffleButton(), repeatButton()])
    }

    // MARK: - Buttons

    private func shuffleButton() -> CPNowPlayingShuffleButton {
        CPNowPlayingShuffleButton { [weak self] _ in
            Task { @MainActor in
                guard let library = self?.library else { return }
                await library.container.playerService.toggleShuffle()
                self?.refreshButtons()
            }
        }
    }

    private func repeatButton() -> CPNowPlayingRepeatButton {
        CPNowPlayingRepeatButton { [weak self] _ in
            Task { @MainActor in
                guard let library = self?.library else { return }
                // Same cycle as the phone's queue control, so the two surfaces never disagree
                // about what the next press does.
                let next: RepeatMode = switch library.container.playerState.repeatMode {
                case .off: .all
                case .all: .one
                case .one: .off
                }
                await library.container.playerService.setRepeatMode(next)
                self?.refreshButtons()
            }
        }
    }

    // MARK: - Up Next

    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        guard let library else { return }
        let state = library.container.playerState
        // What is left to play, not the whole queue: the driver asked what is coming, and the
        // tracks already behind them are noise on a car screen.
        let upcoming = Array(state.queue.dropFirst(state.currentIndex + 1).prefix(library.itemLimit))
        guard !upcoming.isEmpty else {
            Logger.carPlay.notice("Up Next tapped with nothing queued")
            return
        }
        let template = CPListTemplate(title: "Queue", sections: [
            CPListSection(items: library.songItems(upcoming)),
        ])
        library.interfaceController.pushTemplate(template, animated: true, completion: nil)
    }
}
#endif
