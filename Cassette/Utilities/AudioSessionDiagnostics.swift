// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog
import os
#if os(iOS)
import AVFAudio
import UIKit
#endif

/// Who asked the player to pause or resume. Carried as a task-local so the tag reaches PlayerService without
/// touching PlayerServiceProtocol. Diagnostic only: AudioSessionLog prints it, nothing branches on it.
nonisolated enum PlaybackCommandOrigin: String, Sendable {
    case ui
    case remotePlay = "remote-play"
    case remotePause = "remote-pause"
    case remoteToggle = "remote-toggle"
    case intent
    case interruption
    case route
    case other

    @TaskLocal static var current: PlaybackCommandOrigin = .other
}

/// Opt-in, persistent diagnostic channel for the audio-session investigation: issue #49 (no resume after Siri
/// in CarPlay) and playback that keeps going when a Bluetooth or CarPlay route disconnects.
///
/// OFF by default. `log` then returns after one UserDefaults read: the message autoclosure is never evaluated,
/// no string is built, nothing touches the disk. It is switched on at runtime, so it works in a TestFlight
/// build, through `cassette://diagnostics/audio-session/enable` (or the `debug.audioSessionLog` default).
/// When ON, every line goes to:
/// - os_log at `.notice`, which the system persists: it survives into a sysdiagnose and shows in Console;
/// - a size-capped file in Application Support, handed to the share sheet by
///   `cassette://diagnostics/audio-session/export`, so a tester needs no Xcode.
///
/// Observation only. Nothing in the player reads this channel to decide anything, so a build with the channel
/// ON behaves exactly like one with it OFF. Lines carry states, reasons and port types, never track titles,
/// server addresses or device names.
nonisolated enum AudioSessionLog {
    static let enabledKey = "debug.audioSessionLog"

    static var isEnabled: Bool {
        #if os(iOS)
        UserDefaults.standard.bool(forKey: enabledKey)
        #else
        false
        #endif
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        Logger.audioSession.notice("\(text, privacy: .public)")
        #if os(iOS)
        let now = Date()
        queue.async { append("\(now.formatted(timestampStyle)) \(text)\n") }
        #endif
    }

    /// Number stamped on a session notification when the main queue receives it, and repeated when the actor
    /// handles it: a handling order that differs from the receiving order shows up directly in the log.
    static func nextSequence() -> Int {
        guard isEnabled else { return 0 }
        return sequence.withLock { value in
            value += 1
            return value
        }
    }

    private static let sequence = OSAllocatedUnfairLock(initialState: 0)

    // MARK: - Pure descriptions (raw values, so they need no AVFAudio type and stay testable)

    static func describe(interruptionReason raw: UInt?) -> String {
        guard let raw else { return "absent" }
        let name = switch raw {
        case 0: "default"
        case 1: "appWasSuspended"
        case 2: "builtInMicMuted"
        case 3: "sceneWasBackgrounded"
        case 4: "routeDisconnected"
        case 5: "deviceUnauthenticated"
        default: "unknown"
        }
        return "\(name)(\(raw))"
    }

    static func describe(interruptionOptions raw: UInt?) -> String {
        guard let raw else { return "absent" }
        return raw & 1 == 1 ? "shouldResume(\(raw))" : "none(\(raw))"
    }

    static func describe(routeChangeReason raw: UInt) -> String {
        let name = switch raw {
        case 0: "unknown"
        case 1: "newDeviceAvailable"
        case 2: "oldDeviceUnavailable"
        case 3: "categoryChange"
        case 4: "override"
        case 6: "wakeFromSleep"
        case 7: "noSuitableRouteForCategory"
        case 8: "routeConfigurationChange"
        default: "unknown"
        }
        return "\(name)(\(raw))"
    }

    static func describe(categoryOptions raw: UInt) -> String {
        let names: [(UInt, String)] = [
            (0x1, "mixWithOthers"), (0x2, "duckOthers"), (0x4, "allowBluetoothHFP"), (0x8, "defaultToSpeaker"),
            (0x10, "interruptSpokenAudio"), (0x20, "allowBluetoothA2DP"), (0x40, "allowAirPlay"),
            (0x80, "overrideMutedMicrophoneInterruption"), (0x80000, "bluetoothHighQualityRecording")
        ]
        let set = names.filter { raw & $0.0 != 0 }.map(\.1)
        let known = names.reduce(UInt(0)) { $0 | $1.0 }
        let unknown = raw & ~known
        var parts = set
        if unknown != 0 { parts.append("0x\(String(unknown, radix: 16))") }
        return "\(parts.isEmpty ? "none" : parts.joined(separator: "|"))(0x\(String(raw, radix: 16)))"
    }

    static func describe(routeSharingPolicy raw: UInt) -> String {
        let name = switch raw {
        case 0: "default"
        case 1: "longFormAudio"
        case 2: "independent"
        case 3: "longFormVideo"
        default: "unknown"
        }
        return "\(name)(\(raw))"
    }

    static func describe(deactivationSource raw: Int?) -> String {
        guard let raw else { return "absent" }
        let name = switch raw {
        case 1: "app"
        case 2: "system"
        default: "unknown"
        }
        return "\(name)(\(raw))"
    }

    static func describe(resumptionRecommendation raw: Int?) -> String {
        guard let raw else { return "absent" }
        let name = switch raw {
        case 0: "shouldNotResume"
        case 1: "shouldResume"
        default: "unknown"
        }
        return "\(name)(\(raw))"
    }

    static func describe(ports: [String]) -> String {
        "[\(ports.joined(separator: ","))]"
    }

    /// `domain=… code=… '!int'`. The four-character form is what Core Audio documents its session errors by.
    static func describe(error: any Error) -> String {
        let nsError = error as NSError
        let tag = fourCC(nsError.code).map { " '\($0)'" } ?? ""
        return "domain=\(nsError.domain) code=\(nsError.code)\(tag)"
    }

    /// Decodes an OSStatus into its four-character code when all four bytes are printable (560557684 → "!int").
    /// Plain numeric statuses such as -50 have no such form and return nil.
    static func fourCC(_ code: Int) -> String? {
        guard code > 0, code <= Int(UInt32.max) else { return nil }
        let value = UInt32(code)
        let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    #if os(iOS)
    // MARK: - Session snapshots

    /// Category, options, policy and route as the system reports them right now: the effective configuration,
    /// not the one we asked for.
    static func sessionSummary(_ session: AVAudioSession = .sharedInstance()) -> String {
        "category=\(session.category.rawValue)"
            + " options=\(describe(categoryOptions: session.categoryOptions.rawValue))"
            + " mode=\(session.mode.rawValue)"
            + " policy=\(describe(routeSharingPolicy: session.routeSharingPolicy.rawValue))"
            + " prefersInterruptionOnRouteDisconnect=\(session.prefersInterruptionOnRouteDisconnect)"
            + " \(activitySummary(session))"
    }

    /// The part of the session state that moves during an interruption: route and other audio.
    static func activitySummary(_ session: AVAudioSession = .sharedInstance()) -> String {
        "route=\(describe(ports: session.currentRoute.outputs.map(\.portType.rawValue)))"
            + " otherAudioPlaying=\(session.isOtherAudioPlaying)"
            + " secondaryAudioHint=\(session.secondaryAudioShouldBeSilencedHint)"
    }

    static func environmentSummary() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "[ENV] app=\(version)(\(build)) os=\(ProcessInfo.processInfo.operatingSystemVersionString)"
            + " model=\(modelIdentifier()) logging=\(isEnabled ? "on" : "off") \(sessionSummary())"
    }

    private static func modelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    // MARK: - Notification payloads

    static func describeInterruption(_ userInfo: [AnyHashable: Any]?) -> String {
        let type = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        let typeName = switch type {
        case 1?: "began"
        case 0?: "ended"
        default: "unknown"
        }
        return "type=\(typeName)"
            + " reason=\(describe(interruptionReason: userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt))"
            + " options=\(describe(interruptionOptions: userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt))"
    }

    /// Reason and PREVIOUS route: `.oldDeviceUnavailable` can only be judged against what was just lost.
    static func describeRouteChange(_ userInfo: [AnyHashable: Any]?) -> String {
        let reason = (userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).map { describe(routeChangeReason: $0) }
        let previous = (userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)?
            .outputs.map(\.portType.rawValue)
        return "reason=\(reason ?? "absent") previous=\(previous.map { describe(ports: $0) } ?? "absent")"
    }

    /// Notifications logged only for the investigation; nothing observes them to react. A media-services reset
    /// would leave the engine dead, which is one way playback can stay paused for good.
    static let observedOnlyNotificationNames: [Notification.Name] = [
        AVAudioSession.mediaServicesWereLostNotification,
        AVAudioSession.mediaServicesWereResetNotification
    ]

    /// iOS 27 replacements for the interruption notification, also logged only. Raw strings, verified on the iOS 27
    /// simulator, because the typed constants don't exist in the iOS 26 SDK that stable Xcode builds with.
    static let iOS27SessionNotificationNames: [Notification.Name] = [
        Notification.Name("AVAudioSessionDidBecomeActiveNotification"),
        Notification.Name("AVAudioSessionDidBecomeInactiveNotification"),
        Notification.Name("AVAudioSessionResumptionRecommendationNotification")
    ]

    static func describeObservedOnly(_ notification: Notification) -> String {
        switch notification.name.rawValue {
        case "AVAudioSessionDidBecomeInactiveNotification":
            let context = notification.userInfo?["AVAudioSessionDeactivationContextKey"] as? NSObject
            let source = context.flatMap { integer($0, "source") }
            let reason = context
                .flatMap { object($0, "interruptionContext") }
                .flatMap { integer($0, "reason") }
                .flatMap { UInt(exactly: $0) }
            return "didBecomeInactive source=\(describe(deactivationSource: source))"
                + " interruptionReason=\(reason.map { describe(interruptionReason: $0) } ?? "none")"
        case "AVAudioSessionResumptionRecommendationNotification":
            let context = notification.userInfo?["AVAudioSessionResumptionContextKey"] as? NSObject
            let recommendation = context.flatMap { integer($0, "recommendation") }
            return "resumptionRecommendation recommendation=\(describe(resumptionRecommendation: recommendation))"
        case "AVAudioSessionDidBecomeActiveNotification":
            return "didBecomeActive"
        default:
            return notification.name.rawValue
        }
    }

    // The iOS 27 context objects are read through KVC, guarded by responds(to:) so a renamed property logs
    // "absent" instead of raising. Compiling their typed API would break the iOS 26 SDK build.
    private static func integer(_ object: NSObject, _ key: String) -> Int? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return (object.value(forKey: key) as? NSNumber)?.intValue
    }

    private static func object(_ object: NSObject, _ key: String) -> NSObject? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key) as? NSObject
    }

    // MARK: - File channel

    /// Rotate at this size; on disk the channel is bounded to about twice it (.log + .log.1).
    private static let maxBytes = 1024 * 1024
    private static let queue = DispatchQueue(label: "app.cassette.audio-session-log", qos: .utility)
    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private static func append(_ line: String) {
        let fm = FileManager.default
        guard let directory, let data = line.data(using: .utf8) else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("audio-session.log")
        if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size >= maxBytes {
            let rotated = directory.appendingPathComponent("audio-session.log.1")
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: file, to: rotated)
        }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }

    /// One self-contained report (environment header, then both generations oldest first) in a temporary file
    /// for the share sheet. Built on the log queue, so it cannot interleave with a pending append.
    static func makeExportFile() async -> URL? {
        let header = environmentSummary()
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let directory else {
                    continuation.resume(returning: nil)
                    return
                }
                var report = Data("\(header)\n".utf8)
                for name in ["audio-session.log.1", "audio-session.log"] {
                    if let chunk = try? Data(contentsOf: directory.appendingPathComponent(name)) {
                        report.append(chunk)
                    }
                }
                let stamp = Int(Date().timeIntervalSince1970)
                let export = FileManager.default.temporaryDirectory
                    .appendingPathComponent("cassette-audio-session-\(stamp).log")
                do {
                    try report.write(to: export)
                    continuation.resume(returning: export)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func clear() {
        queue.async {
            guard let directory else { return }
            for name in ["audio-session.log", "audio-session.log.1"] {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }
    #endif
}

/// `cassette://diagnostics/audio-session/<action>`: hidden switches for AudioSessionLog, so a TestFlight tester
/// can turn it on and send the file back without Xcode. No screen, no user-facing string.
nonisolated enum AudioSessionDiagnosticsLink: String, Sendable {
    case enable
    case disable
    case export
    case clear

    init?(url: URL) {
        guard url.scheme?.lowercased() == "cassette", url.host()?.lowercased() == "diagnostics" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0].lowercased() == "audio-session",
              let action = Self(rawValue: parts[1].lowercased()) else { return nil }
        self = action
    }
}

#if os(iOS)
@MainActor
enum AudioSessionDiagnosticsLinkHandler {
    /// Applies a diagnostics link. Returns false for any other URL, which the caller leaves untouched.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard let action = AudioSessionDiagnosticsLink(url: url) else { return false }
        switch action {
        case .enable:
            UserDefaults.standard.set(true, forKey: AudioSessionLog.enabledKey)
            AudioSessionLog.log("[LOG] enabled via link \(AudioSessionLog.environmentSummary())")
        case .disable:
            AudioSessionLog.log("[LOG] disabled via link")
            UserDefaults.standard.set(false, forKey: AudioSessionLog.enabledKey)
        case .clear:
            AudioSessionLog.clear()
        case .export:
            Task { await presentExport() }
        }
        return true
    }

    private static func presentExport() async {
        guard let file = await AudioSessionLog.makeExportFile() else { return }
        // A link cold-launches or foregrounds the scene; give the window a moment to become key first.
        try? await Task.sleep(for: .milliseconds(600))
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var presenter = scene?.keyWindow?.rootViewController
        while let presented = presenter?.presentedViewController { presenter = presented }
        guard let presenter else { return }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = presenter.view
        presenter.present(sheet, animated: true)
    }
}
#endif
