import Foundation

nonisolated enum PlaybackState: Sendable {
    case idle
    case loading
    case playing
    case paused
    case error(CassetteError)
}
