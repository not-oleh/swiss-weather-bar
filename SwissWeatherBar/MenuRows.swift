import Cocoa

// MARK: - Menu helpers

/// Rounded for display, without the "-0" that formatting gives for values just below zero.
func shown(_ x: Double, _ digits: Int = 0) -> Double {
    let p = pow(10, Double(digits))
    let r = (x * p).rounded() / p
    return r == 0 ? 0 : r
}

/// A date formatter in Swiss time (see `swissTime`).
func swissFormatter(_ setup: (DateFormatter) -> Void) -> DateFormatter {
    let f = DateFormatter()
    f.timeZone = swissTime
    setup(f)
    return f
}

/// A non-interactive row. It is drawn by a custom view because AppKit greys out the
/// text of disabled menu items; tab-separated columns line up on the given tab stops.
/// VoiceOver reads the row as one sentence: `speech`, or the text without the tabs.
/// Columns listed in `rain` are drawn in blue, as weather apps usually show rain.
func row(_ text: String, tabs: [NSTextTab] = [], tip: String? = nil, secondary: Bool = false,
         speech: String? = nil, rain: Set<Int> = []) -> NSMenuItem {
    let inset = rowInset
    let font = secondary ? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                         : NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    let color: NSColor = secondary ? .secondaryLabelColor : .labelColor
    let height: CGFloat = secondary ? 20 : 22
    let view = NSView()
    var maxX: CGFloat = 0
    for (i, c) in text.components(separatedBy: "\t").enumerated() {
        let label = NSTextField(labelWithString: c)
        label.font = font
        label.textColor = rain.contains(i) ? .systemBlue : color
        label.setAccessibilityElement(false)
        label.sizeToFit()
        let w = label.frame.width
        var x = inset
        if i > 0, i - 1 < tabs.count {
            let s = tabs[i - 1]
            x = inset + s.location - (s.alignment == .right ? w : 0)
        }
        label.frame = NSRect(x: x, y: (height - label.frame.height) / 2, width: w, height: label.frame.height)
        maxX = max(maxX, label.frame.maxX)
        view.addSubview(label)
    }
    view.frame = NSRect(x: 0, y: 0, width: max(260, maxX + inset), height: height)
    view.toolTip = tip      // a menu item with a custom view ignores its own toolTip
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.staticText)
    view.setAccessibilityLabel(speech ?? text.split(separator: "\t").joined(separator: ", "))
    let m = NSMenuItem()
    m.view = view
    return m
}

/// Left edge of the text in standard menu items (after the checkmark column),
/// so custom rows line up with the headers and commands.
let rowInset: CGFloat = 22

func header(_ title: String) -> NSMenuItem {
    if #available(macOS 14, *) { return .sectionHeader(title: title) }
    let m = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
    m.isEnabled = false
    return m
}

// time | icon | temperature | rain chance — "100%" needs its own column
// or it runs into the temperature
let hourTabs = [NSTextTab(textAlignment: .left, location: 52), NSTextTab(textAlignment: .right, location: 112),
                NSTextTab(textAlignment: .right, location: 160)]
let dayTabs = [NSTextTab(textAlignment: .left, location: 84), NSTextTab(textAlignment: .right, location: 144),
               NSTextTab(textAlignment: .right, location: 184), NSTextTab(textAlignment: .right, location: 268)]

extension NSMenuItem {
    func withSecondaryStyle() -> NSMenuItem {
        let a = NSMutableAttributedString(attributedString: attributedTitle ?? NSAttributedString(string: title))
        a.addAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                         .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)],
                        range: NSRange(location: 0, length: a.length))
        attributedTitle = a
        return self
    }
}
