// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Cassette

@Suite("Justified biography layout")
@MainActor
struct JustifiedTextLayoutTests {
    private let biography = String(repeating:
        "A long artist biography should wrap within the available space. ", count: 40)

    @Test("Biographies do not impose their single-line width on a scroll view", arguments: [3, 0])
    func minimumWidth(lineLimit: Int) {
        let host = NSHostingView(rootView: ScrollView {
            JustifiedText(text: biography, lineLimit: lineLimit)
        })

        #expect(host.fittingSize.width == 0)
    }

    @Test("Collapsed and expanded biographies wrap when resized")
    func wrappingAndExpansion() throws {
        let collapsed = NSHostingView(rootView: ScrollView {
            JustifiedText(text: biography, lineLimit: 3)
        })
        let expanded = NSHostingView(rootView: ScrollView {
            JustifiedText(text: biography, lineLimit: 0)
        })
        var expandedHeights: [CGFloat] = []

        for width in [CGFloat(320), 800] {
            for host in [collapsed, expanded] {
                host.frame = NSRect(x: 0, y: 0, width: width, height: 700)
                host.layoutSubtreeIfNeeded()
            }
            let collapsedLabel = try #require(label(in: collapsed))
            let expandedLabel = try #require(label(in: expanded))
            let lineHeight = try #require(collapsedLabel.font).boundingRectForFont.height

            #expect(collapsedLabel.frame.height > lineHeight)
            #expect(collapsedLabel.frame.height <= ceil(lineHeight * 3))
            #expect(expandedLabel.frame.height > collapsedLabel.frame.height)
            #expect(collapsedLabel.alignmentRect(forFrame: collapsedLabel.frame).width == width)
            #expect(expandedLabel.alignmentRect(forFrame: expandedLabel.frame).width == width)
            expandedHeights.append(expandedLabel.frame.height)
        }
        #expect(expandedHeights[0] > expandedHeights[1])
    }

    private func label(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.lazy.compactMap { label(in: $0) }.first
    }
}
#endif
