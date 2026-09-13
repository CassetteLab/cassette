// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Testing
@testable import Cassette

// Locks the decoding the audio-session diagnostic log relies on: a mislabeled reason or error code would send the
// investigation of issue #49 the wrong way, and a link that parses too loosely would toggle logging by accident.

@Suite("Audio session diagnostics")
struct AudioSessionDiagnosticsTests {

    @Test("interruption reasons decode by raw value, routeDisconnected included")
    func interruptionReasons() {
        #expect(AudioSessionLog.describe(interruptionReason: 0) == "default(0)")
        #expect(AudioSessionLog.describe(interruptionReason: 4) == "routeDisconnected(4)")
        #expect(AudioSessionLog.describe(interruptionReason: 42) == "unknown(42)")
        #expect(AudioSessionLog.describe(interruptionReason: nil) == "absent")
    }

    @Test("interruption options tell shouldResume apart from an empty or missing value")
    func interruptionOptions() {
        #expect(AudioSessionLog.describe(interruptionOptions: 1) == "shouldResume(1)")
        #expect(AudioSessionLog.describe(interruptionOptions: 0) == "none(0)")
        #expect(AudioSessionLog.describe(interruptionOptions: nil) == "absent")
    }

    @Test("route change reasons decode by raw value")
    func routeChangeReasons() {
        #expect(AudioSessionLog.describe(routeChangeReason: 1) == "newDeviceAvailable(1)")
        #expect(AudioSessionLog.describe(routeChangeReason: 2) == "oldDeviceUnavailable(2)")
        #expect(AudioSessionLog.describe(routeChangeReason: 8) == "routeConfigurationChange(8)")
        #expect(AudioSessionLog.describe(routeChangeReason: 5) == "unknown(5)")
    }

    @Test("category options list every set bit, including the ones Cassette requests")
    func categoryOptions() {
        #expect(AudioSessionLog.describe(categoryOptions: 0x44) == "allowBluetoothHFP|allowAirPlay(0x44)")
        #expect(AudioSessionLog.describe(categoryOptions: 0) == "none(0x0)")
        #expect(AudioSessionLog.describe(categoryOptions: 0x1_0001) == "mixWithOthers|0x10000(0x10001)")
    }

    @Test("iOS 27 context values decode, and a missing context reads as absent")
    func iOS27Contexts() {
        #expect(AudioSessionLog.describe(deactivationSource: 2) == "system(2)")
        #expect(AudioSessionLog.describe(deactivationSource: nil) == "absent")
        #expect(AudioSessionLog.describe(resumptionRecommendation: 1) == "shouldResume(1)")
        #expect(AudioSessionLog.describe(resumptionRecommendation: 0) == "shouldNotResume(0)")
    }

    @Test("session error codes show their four-character form when they have one")
    func errorCodes() {
        #expect(AudioSessionLog.fourCC(560_557_684) == "!int")
        #expect(AudioSessionLog.fourCC(561_017_449) == "!pri")
        #expect(AudioSessionLog.fourCC(-50) == nil)
        #expect(AudioSessionLog.fourCC(0) == nil)

        let busy = NSError(domain: NSOSStatusErrorDomain, code: 560_557_684)
        #expect(AudioSessionLog.describe(error: busy) == "domain=\(NSOSStatusErrorDomain) code=560557684 '!int'")
        let param = NSError(domain: NSOSStatusErrorDomain, code: -50)
        #expect(AudioSessionLog.describe(error: param) == "domain=\(NSOSStatusErrorDomain) code=-50")
    }

    @Test("diagnostics links parse their four actions, case-insensitively")
    func linksParse() throws {
        for action in ["enable", "disable", "export", "clear"] {
            let url = try #require(URL(string: "cassette://diagnostics/audio-session/\(action)"))
            #expect(AudioSessionDiagnosticsLink(url: url)?.rawValue == action)
        }
        let shouted = try #require(URL(string: "CASSETTE://Diagnostics/Audio-Session/ENABLE"))
        #expect(AudioSessionDiagnosticsLink(url: shouted) == .enable)
    }

    #if os(iOS)
    @Test("export writes a self-contained report that opens with the environment header")
    func exportReport() async throws {
        let url = try #require(await AudioSessionLog.makeExportFile())
        defer { try? FileManager.default.removeItem(at: url) }
        let report = try String(contentsOf: url, encoding: .utf8)
        #expect(report.hasPrefix("[ENV] app="))
        #expect(url.lastPathComponent.hasPrefix("cassette-audio-session-"))
    }
    #endif

    @Test("any other URL is not a diagnostics link")
    func otherLinksIgnored() throws {
        let others = [
            "cassette://diagnostics/audio-session",
            "cassette://diagnostics/audio-session/enable/now",
            "cassette://diagnostics/rcc/enable",
            "cassette://player/audio-session/enable",
            "https://diagnostics/audio-session/enable",
            "cassette://album/42"
        ]
        for string in others {
            let url = try #require(URL(string: string))
            #expect(AudioSessionDiagnosticsLink(url: url) == nil, "\(string) must not parse")
        }
    }
}
