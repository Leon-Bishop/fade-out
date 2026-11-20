import AppKit
import SwiftUI

@main
struct FadeOutApp: App {
    @StateObject private var model = MixerModel()

    var body: some Scene {
        MenuBarExtra {
            MixerView(model: model)
        } label: {
            Image(nsImage: MenuGlyph.make(dimmed: model.hasReducedSound))
                .accessibilityLabel("Fade Out")
        }
        .menuBarExtraStyle(.window)
    }
}

private enum MenuGlyph {
    static func make(dimmed: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { rect in
            let color = NSColor.labelColor.withAlphaComponent(dimmed ? 0.52 : 1)
            color.setStroke()
            let speaker = NSBezierPath()
            speaker.lineWidth = 1.8
            speaker.lineJoinStyle = .round
            speaker.move(to: NSPoint(x: 2, y: 7))
            speaker.line(to: NSPoint(x: 5, y: 7))
            speaker.line(to: NSPoint(x: 9, y: 11))
            speaker.line(to: NSPoint(x: 9, y: 2))
            speaker.line(to: NSPoint(x: 5, y: 6))
            speaker.line(to: NSPoint(x: 2, y: 6))
            speaker.stroke()
            for (x, height, alpha) in [(13.0, 9.0, 1.0), (17.0, 6.0, 0.65), (20.0, 3.0, 0.35)] {
                color.withAlphaComponent(CGFloat(alpha)).setStroke()
                let wave = NSBezierPath()
                wave.lineWidth = 1.7
                wave.lineCapStyle = .round
                wave.move(to: NSPoint(x: x, y: 9 - height / 2))
                wave.curve(to: NSPoint(x: x, y: 9 + height / 2),
                           controlPoint1: NSPoint(x: x + 2, y: 7),
                           controlPoint2: NSPoint(x: x + 2, y: 11))
                wave.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
