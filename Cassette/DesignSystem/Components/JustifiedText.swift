// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Multiline text with **justified** alignment (both edges flush) — which SwiftUI's `Text` cannot do
/// natively (it only offers leading/center/trailing). Wraps a platform label and reports its height via
/// `sizeThatFits`, so it lays out and clamps like a normal view inside SwiftUI stacks. Uses the dynamic
/// `.body` text style to match `.cassetteBody`. `lineLimit` of 0 means unlimited.
struct JustifiedText: View {
    let text: String
    var lineLimit: Int = 0
    var color: Color = .secondary

    var body: some View {
        Backing(text: text, lineLimit: lineLimit, color: color)
    }
}

#if canImport(UIKit)
private struct Backing: UIViewRepresentable {
    let text: String
    let lineLimit: Int
    let color: Color

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.numberOfLines = lineLimit
        let para = NSMutableParagraphStyle()
        para.alignment = .justified
        para.lineBreakMode = .byWordWrapping
        label.attributedText = NSAttributedString(string: text, attributes: [
            .paragraphStyle: para,
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor(color)
        ])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingCompressedSize.width
        let fit = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }
}
#elseif canImport(AppKit)
private struct Backing: NSViewRepresentable {
    let text: String
    let lineLimit: Int
    let color: Color

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.maximumNumberOfLines = lineLimit
        let para = NSMutableParagraphStyle()
        para.alignment = .justified
        para.lineBreakMode = .byWordWrapping
        field.attributedStringValue = NSAttributedString(string: text, attributes: [
            .paragraphStyle: para,
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor(color)
        ])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? 0
        guard width > 0 else { return nil }
        field.preferredMaxLayoutWidth = width
        return CGSize(width: width, height: ceil(field.intrinsicContentSize.height))
    }
}
#endif
