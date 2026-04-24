import Foundation

protocol KeychainServiceProtocol: AnyObject, Sendable {
    func store<T: Codable & Sendable>(_ value: T, forKey key: String) async throws
    func retrieve<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T?
    func delete(forKey key: String) async throws
}
