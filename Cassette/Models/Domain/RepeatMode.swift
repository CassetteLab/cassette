import Foundation

nonisolated enum RepeatMode: String, Sendable, Codable, CaseIterable {
    case off
    case one
    case all
}
