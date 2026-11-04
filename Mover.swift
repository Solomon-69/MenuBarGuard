// Mover.swift: moves a menu bar icon to another section. macOS only lets icons be rearranged by a
// Command-drag, so this does a very fast Command-drag for you (about a fifth of a second) and puts
// the pointer back where it was. Needs Accessibility permission.
import AppKit
import CoreGraphics

enum Mover {
    /// Drags from `from` to `to` (both top-left based screen points) with Command held.
    static func commandDrag(from: CGPoint, to: CGPoint) -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return false }
        let back = CGEvent(source: nil)?.location ?? from
        func post(_ type: CGEventType, _ p: CGPoint) {
            guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
            e.flags = .maskCommand
            e.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, from); usleep(25_000)
        post(.leftMouseDown, from); usleep(60_000)
        let steps = 8
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y)); usleep(18_000)
        }
        post(.leftMouseUp, to); usleep(40_000)
        // Let go of Command and put the pointer back.
        if let up = CGEvent(source: src) { up.flags = []; up.type = .flagsChanged; up.post(tap: .cghidEventTap) }
        CGWarpMouseCursorPosition(back)
        CGAssociateMouseAndMouseCursorPosition(1)
        return true
    }

    /// One plain click (only used when an app's icon ignores the Accessibility "press").
    static func click(at p: CGPoint) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let back = CGEvent(source: nil)?.location ?? p
        for t in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(30_000)
        }
        CGWarpMouseCursorPosition(back)
    }
}
