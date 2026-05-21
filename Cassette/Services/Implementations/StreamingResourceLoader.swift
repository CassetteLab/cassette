// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import AVFoundation
import UniformTypeIdentifiers
import OSLog

// MARK: - LoaderState (internal actor)

/// Actor that owns all mutable state for a single StreamingResourceLoader instance.
/// Kept separate so the NSObject AVFoundation delegate remains non-actor while still
/// satisfying Swift 6 strict concurrency with zero data races.
private actor LoaderState {

    // MARK: State

    var pendingRequests: [AVAssetResourceLoadingRequest] = []
    private(set) var contentLength: Int64?
    private(set) var contentMimeType: String?
    let chunkStore: ChunkStore

    /// Prevents onFullyCached from firing more than once (guarded against actor reentrancy).
    private var didFireFullyCached = false

    init(chunkStore: ChunkStore) {
        self.chunkStore = chunkStore
    }

    // MARK: Request management

    func addRequest(_ request: AVAssetResourceLoadingRequest) {
        guard !request.isCancelled else { return }
        pendingRequests.append(request)
    }

    func removeRequest(_ request: AVAssetResourceLoadingRequest) {
        pendingRequests.removeAll { $0 === request }
    }

    // MARK: Content info

    func setContentInfo(length: Int64, mimeType: String?) async {
        if contentLength == nil {
            contentLength = length
            await chunkStore.setTotalLength(length)
        }
        if contentMimeType == nil, let mimeType {
            contentMimeType = mimeType
        }
    }

    // MARK: Chunk storage

    func storeChunk(data: Data, at offset: Int64) async {
        await chunkStore.store(data: data, at: offset)
    }

    // MARK: Coverage queries

    func isCovered(range: Range<Int64>) async -> Bool {
        await chunkStore.data(for: range) != nil
    }

    func dataForRange(_ range: Range<Int64>) async -> Data? {
        await chunkStore.data(for: range)
    }

    /// Returns true exactly once if the stream is fully cached and the callback
    /// has not yet fired. Re-checks the flag after the actor suspension point
    /// so concurrent reentrant calls cannot both return true.
    func shouldFireFullyCachedCallback() async -> Bool {
        guard !didFireFullyCached else { return false }
        guard let total = contentLength, total > 0 else { return false }
        let covered = await chunkStore.isFully(covering: total)
        guard covered else { return false }
        // Re-check after suspension to guard against actor reentrancy.
        guard !didFireFullyCached else { return false }
        didFireFullyCached = true
        return true
    }

    func completeData() async -> Data? {
        guard let total = contentLength else { return nil }
        return await chunkStore.data(for: 0 ..< total)
    }

    // MARK: Fulfillment

    /// Attempts to satisfy all pending requests from current chunk store contents.
    /// Clears the request list before any suspension point (actor reentrancy safety):
    /// new requests added via addRequest() during awaits are preserved because they
    /// land in the already-cleared array and get prepended back at the end.
    /// Uses partial respond(with:) calls so AVFoundation receives data incrementally
    /// and does not time out while waiting for a large range to finish downloading.
    func fulfillPendingRequests() async {
        guard !pendingRequests.isEmpty else { return }

        let toProcess = pendingRequests
        pendingRequests = []

        var unfulfilled: [AVAssetResourceLoadingRequest] = []

        for request in toProcess {
            guard !request.isCancelled else { continue }

            if let info = request.contentInformationRequest, let length = contentLength {
                info.contentLength = length
                info.isByteRangeAccessSupported = true
                if let mimeType = contentMimeType {
                    info.contentType = UTType(mimeType: mimeType)?.identifier
                }
            }

            guard let dataRequest = request.dataRequest else {
                // Content-info-only request: finish once we have the length.
                if contentLength != nil {
                    request.finishLoading()
                } else {
                    unfulfilled.append(request)
                }
                continue
            }

            let startOffset = dataRequest.currentOffset
            let endOffset: Int64
            if dataRequest.requestsAllDataToEndOfResource {
                guard let total = contentLength else {
                    unfulfilled.append(request)
                    continue
                }
                endOffset = total
            } else {
                endOffset = dataRequest.requestedOffset + Int64(dataRequest.requestedLength)
            }

            guard startOffset < endOffset else {
                request.finishLoading()
                continue
            }

            // Deliver the largest contiguous block available from currentOffset.
            // respond(with:) advances dataRequest.currentOffset automatically.
            // Keep the request alive until all bytes up to endOffset are delivered.
            if let data = await chunkStore.largestContiguousData(from: startOffset, upTo: endOffset),
               !data.isEmpty {
                dataRequest.respond(with: data)
                let newOffset = startOffset + Int64(data.count)
                if newOffset >= endOffset {
                    request.finishLoading()
                    Logger.streaming.debug("[LOADER] Fulfilled \(endOffset - dataRequest.requestedOffset) bytes total, ending at \(endOffset)")
                } else {
                    unfulfilled.append(request)
                }
            } else {
                unfulfilled.append(request)
            }
        }

        // Prepend unfulfilled so any requests added during our awaits (now in
        // pendingRequests) come after the still-waiting originals.
        pendingRequests.insert(contentsOf: unfulfilled, at: 0)
    }
}

// MARK: - StreamingResourceLoader

/// AVAssetResourceLoaderDelegate that intercepts cassette-stream:// URLs and
/// fulfills AVFoundation byte-range requests via HTTP range requests to the real server.
///
/// Must be a final NSObject subclass, NOT an actor: AVFoundation calls delegate
/// methods on its own internal queue, and actor isolation would cause a deadlock.
/// All mutable state is managed by the internal LoaderState actor.
final class StreamingResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {

    // MARK: Public

    nonisolated let songId: String

    /// Fires at most once when the complete audio data has been accumulated.
    /// Parameters: (audioData, mimeType). Caller should offload persistence to a Task.
    /// nonisolated(unsafe): set once before the loader is handed to AVFoundation, then only read.
    nonisolated(unsafe) var onFullyCached: ((Data, String) -> Void)?

    // MARK: Private

    private let realURL: URL
    private let headers: [String: String]
    private let loaderState: LoaderState
    private let urlSession: URLSession

    private let maxRetryAttempts = 3
    private let retryDelays: [Duration] = [
        .milliseconds(500),
        .seconds(1),
        .seconds(2)
    ]

    // MARK: Init

    nonisolated init(realURL: URL, headers: [String: String], songId: String) {
        self.realURL = realURL
        self.headers = headers
        self.songId = songId

        let store = ChunkStore()
        self.loaderState = LoaderState(chunkStore: store)

        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - AVAssetResourceLoaderDelegate

    nonisolated func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        Logger.streaming.debug("[LOADER] shouldWait songId=\(self.songId, privacy: .public)")
        Task {
            await loaderState.addRequest(loadingRequest)
            await fetchIfNeeded(for: loadingRequest)
        }
        return true
    }

    nonisolated func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        Logger.streaming.debug("[LOADER] didCancel songId=\(self.songId, privacy: .public)")
        Task { await loaderState.removeRequest(loadingRequest) }
    }

    // MARK: - Fetch coordination

    private func fetchIfNeeded(for request: AVAssetResourceLoadingRequest) async {
        let knownLength = await loaderState.contentLength

        // If the request needs content info and we don't have it yet, get metadata first.
        if request.contentInformationRequest != nil, knownLength == nil {
            await fetchMetadata()
            return  // fulfillPendingRequests() is called inside fetchMetadata
        }

        guard let dataRequest = request.dataRequest else {
            await loaderState.fulfillPendingRequests()
            return
        }

        let startOffset = dataRequest.currentOffset
        let endOffset: Int64

        if dataRequest.requestsAllDataToEndOfResource {
            if let total = knownLength {
                endOffset = total
            } else {
                // Total length unknown — use open-ended range request to discover it.
                await fetchOpenEnded(from: startOffset, for: request)
                return
            }
        } else {
            endOffset = dataRequest.requestedOffset + Int64(dataRequest.requestedLength)
        }

        guard startOffset < endOffset else {
            await loaderState.fulfillPendingRequests()
            return
        }

        let range = startOffset ..< endOffset

        if await loaderState.isCovered(range: range) {
            await loaderState.fulfillPendingRequests()
            return
        }

        await fetchRange(range, for: request)
    }

    // MARK: - HTTP fetching

    private func fetchMetadata() async {
        var req = URLRequest(url: realURL)
        req.httpMethod = "HEAD"
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        if let (_, response) = try? await urlSession.data(for: req),
           let http = response as? HTTPURLResponse {
            if let lengthStr = http.value(forHTTPHeaderField: "Content-Length"),
               let length = Int64(lengthStr) {
                await loaderState.setContentInfo(length: length, mimeType: http.mimeType)
            }
            let knownLength = await loaderState.contentLength
            Logger.streaming.debug("[LOADER] HEAD length=\(knownLength ?? -1) songId=\(self.songId, privacy: .public)")
        } else {
            Logger.streaming.warning("[LOADER] HEAD failed songId=\(self.songId, privacy: .public)")
        }

        await loaderState.fulfillPendingRequests()
    }

    private func fetchOpenEnded(from offset: Int64, for request: AVAssetResourceLoadingRequest) async {
        var req = URLRequest(url: realURL)
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")

        Logger.streaming.debug("[LOADER] Open-ended fetch from \(offset) songId=\(self.songId, privacy: .public)")

        do {
            let (asyncBytes, response) = try await urlSession.bytes(for: req)
            guard let http = response as? HTTPURLResponse else {
                request.finishLoading(with: URLError(.badServerResponse))
                await loaderState.removeRequest(request)
                return
            }

            await extractContentInfo(from: http, requestedOffset: offset)

            guard (200 ..< 300).contains(http.statusCode) else {
                Logger.streaming.error("[LOADER] HTTP \(http.statusCode) open-ended songId=\(self.songId, privacy: .public)")
                request.finishLoading(with: URLError(.badServerResponse))
                await loaderState.removeRequest(request)
                return
            }

            let storeOffset: Int64 = http.statusCode == 200 ? 0 : offset
            var writeOffset = storeOffset
            var buffer = Data(capacity: 131_072)
            let flushThreshold = 131_072
            var streamedFully = true

            for try await byte in asyncBytes {
                guard !request.isCancelled, !Task.isCancelled else {
                    streamedFully = false
                    break
                }
                buffer.append(byte)
                if buffer.count >= flushThreshold {
                    let chunk = buffer
                    buffer = Data(capacity: flushThreshold)
                    await loaderState.storeChunk(data: chunk, at: writeOffset)
                    writeOffset += Int64(chunk.count)
                    await loaderState.fulfillPendingRequests()
                }
            }

            if !buffer.isEmpty {
                await loaderState.storeChunk(data: buffer, at: writeOffset)
                writeOffset += Int64(buffer.count)
            }

            // For chunked-encoding responses that omit Content-Length, set the total
            // now that we know all bytes have been received.
            if streamedFully, await loaderState.contentLength == nil {
                await loaderState.setContentInfo(length: writeOffset, mimeType: http.mimeType)
            }

            Logger.streaming.debug("[LOADER] Open-ended complete: \(writeOffset - storeOffset) bytes songId=\(self.songId, privacy: .public)")
            await loaderState.fulfillPendingRequests()
            await checkFullyCached()

        } catch {
            Logger.streaming.error("[LOADER] Open-ended error songId=\(self.songId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            request.finishLoading(with: error)
            await loaderState.removeRequest(request)
        }
    }

    private func fetchRange(
        _ range: Range<Int64>,
        for request: AVAssetResourceLoadingRequest,
        attempt: Int = 0
    ) async {
        var req = URLRequest(url: realURL)
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")

        Logger.streaming.debug("[LOADER] Fetch bytes \(range.lowerBound)-\(range.upperBound - 1) attempt=\(attempt + 1) songId=\(self.songId, privacy: .public)")

        do {
            let (asyncBytes, response) = try await urlSession.bytes(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            await extractContentInfo(from: http, requestedOffset: range.lowerBound)

            guard (200 ..< 300).contains(http.statusCode) else {
                Logger.streaming.error("[LOADER] HTTP \(http.statusCode) range request songId=\(self.songId, privacy: .public)")
                await retryOrFail(range: range, request: request, attempt: attempt, error: URLError(.badServerResponse))
                return
            }

            let storeOffset: Int64 = http.statusCode == 200 ? 0 : range.lowerBound
            var writeOffset = storeOffset
            var buffer = Data(capacity: 131_072)
            let flushThreshold = 131_072
            var streamedFully = true

            for try await byte in asyncBytes {
                guard !request.isCancelled, !Task.isCancelled else {
                    streamedFully = false
                    break
                }
                buffer.append(byte)
                if buffer.count >= flushThreshold {
                    let chunk = buffer
                    buffer = Data(capacity: flushThreshold)
                    await loaderState.storeChunk(data: chunk, at: writeOffset)
                    writeOffset += Int64(chunk.count)
                    await loaderState.fulfillPendingRequests()
                }
            }

            if !buffer.isEmpty {
                await loaderState.storeChunk(data: buffer, at: writeOffset)
                writeOffset += Int64(buffer.count)
            }

            // For full-file 200 responses without Content-Length, the total size
            // is known only after all bytes have been streamed from offset 0.
            if streamedFully, storeOffset == 0, await loaderState.contentLength == nil {
                await loaderState.setContentInfo(length: writeOffset, mimeType: http.mimeType)
            }

            Logger.streaming.debug("[LOADER] Range \(range.lowerBound)-\(range.upperBound - 1): \(writeOffset - storeOffset) bytes songId=\(self.songId, privacy: .public)")
            await loaderState.fulfillPendingRequests()
            await checkFullyCached()

        } catch {
            await retryOrFail(range: range, request: request, attempt: attempt, error: error)
        }
    }

    private func retryOrFail(
        range: Range<Int64>,
        request: AVAssetResourceLoadingRequest,
        attempt: Int,
        error: Error
    ) async {
        if attempt < maxRetryAttempts - 1 {
            let delay = retryDelays[min(attempt, retryDelays.count - 1)]
            Logger.streaming.warning(
                "[LOADER] Retry \(attempt + 1)/\(self.maxRetryAttempts) delay=\(delay) songId=\(self.songId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await fetchRange(range, for: request, attempt: attempt + 1)
        } else {
            Logger.streaming.error(
                "[LOADER] Failed after \(self.maxRetryAttempts) attempts songId=\(self.songId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            request.finishLoading(with: error)
            await loaderState.removeRequest(request)
        }
    }

    // MARK: - Helpers

    private func extractContentInfo(from http: HTTPURLResponse, requestedOffset: Int64) async {
        if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
           let parsed = parseContentRange(contentRange) {
            await loaderState.setContentInfo(length: parsed.total, mimeType: http.mimeType)
        } else if http.statusCode == 200 {
            if let str = http.value(forHTTPHeaderField: "Content-Length"), let length = Int64(str) {
                await loaderState.setContentInfo(length: length, mimeType: http.mimeType)
            }
            // No Content-Length on a 200: caller sets total length after all bytes are streamed.
        }
    }

    private func checkFullyCached() async {
        guard await loaderState.shouldFireFullyCachedCallback() else { return }
        guard let data = await loaderState.completeData() else { return }
        let mimeType = await loaderState.contentMimeType ?? "audio/mpeg"
        Logger.streaming.info(
            "[LOADER] '\(self.songId, privacy: .public)' fully cached — \(data.count) bytes, \(mimeType, privacy: .public)"
        )
        onFullyCached?(data, mimeType)
    }

    private func parseContentRange(_ header: String) -> (start: Int64, end: Int64, total: Int64)? {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("bytes ") else { return nil }
        let rest = String(trimmed.dropFirst(6))
        let slashParts = rest.components(separatedBy: "/")
        guard slashParts.count == 2,
              let total = Int64(slashParts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        let dashParts = slashParts[0].components(separatedBy: "-")
        guard dashParts.count == 2,
              let start = Int64(dashParts[0].trimmingCharacters(in: .whitespaces)),
              let end   = Int64(dashParts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return (start, end, total)
    }
}
