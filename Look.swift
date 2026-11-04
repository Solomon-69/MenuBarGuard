// Look.swift: the menu bar look (tint, shadow, border, rounded or split shape). A see-through,
// click-through window sits just under the menu bar's own layer, so menus and icons stay on top.
import AppKit
import Combine
import SwiftUI

@MainActor final class LookModel: ObservableObject {
    @Published var config = LookConfig()
    @Published var appMenusMaxX: CGFloat = 300
    @Published var iconsMinX: CGFloat = 900
    @Published var notch: ClosedRange<CGFloat>?
    @Published var width: CGFloat = 1470
    @Published var height: CGFloat = 32
}

@MainActor final class LookController {
    let prefs: Prefs
    let model = LookModel()
    private var windows: [NSWindow] = []
    private var bag = Set<AnyCancellable>()
    var iconsMinX: () -> CGFloat? = { nil }

    init(prefs: Prefs) { self.prefs = prefs }

    func start() {
        prefs.$look.sink { [weak self] c in DispatchQueue.main.async { self?.model.config = c; self?.update() } }.store(in: &bag)
        let ws = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild(); self?.update() }
        }
    }

    var isShown: Bool { windows.contains { $0.isVisible } }

    private func rebuild() { windows.forEach { $0.orderOut(nil) }; windows = [] }

    /// Shows, hides or redraws the overlay for the current settings.
    func update() {
        let c = prefs.look
        guard c.on, let screen = MenuBarGeometry.screen else { windows.forEach { $0.orderOut(nil) }; return }
        if !c.fullScreen && Self.frontIsFullScreen(screen) { windows.forEach { $0.orderOut(nil) }; return }
        let w = windows.first ?? make()
        if windows.isEmpty { windows = [w] }
        let h = MenuBarGeometry.height(screen)
        model.width = screen.frame.width; model.height = h
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea { model.notch = (l.maxX - screen.frame.minX)...(r.minX - screen.frame.minX) } else { model.notch = nil }
        model.iconsMinX = (iconsMinX() ?? screen.frame.maxX * 0.6) - screen.frame.minX
        Task.detached { let x = Scanner.appMenusMaxX(); await MainActor.run { if x > 80 { self.model.appMenusMaxX = x } } }
        w.setFrame(CGRect(x: screen.frame.minX, y: screen.frame.maxY - h - 12, width: screen.frame.width, height: h + 12), display: true)
        w.orderFrontRegardless()
    }

    private func make() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        // On macOS 26+ the menu bar paints its own backdrop, so the tint must sit on the menu bar layer itself
        // (icons are one layer higher and stay on top; app menu text shows through the see-through tint).
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)))
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.contentView = NSHostingView(rootView: LookView(model: model))
        return w
    }

    /// Is the app in front filling the whole screen (a full-screen space)?
    static func frontIsFullScreen(_ s: NSScreen) -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return (b["Width"] ?? 0) >= s.frame.width && (b["Height"] ?? 0) >= s.frame.height
        }
    }

    func snapshot(config: LookConfig, dark: Bool, path: String) {
        let m = LookModel()
        m.config = config; m.config.on = true
        m.width = 900; m.height = 32; m.appMenusMaxX = 260; m.iconsMinX = 620; m.notch = 380...520
        let v = ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.25, green: 0.35, blue: 0.55), Color(red: 0.55, green: 0.4, blue: 0.5)], startPoint: .leading, endPoint: .trailing)
            LookView(model: m)
            HStack { Text("  Finder   File   Edit   View").font(.system(size: 13, weight: .medium)).foregroundStyle(.white); Spacer() }.frame(height: 32)
        }
        Snap.render(AnyView(v.frame(width: 900, height: 90)), size: CGSize(width: 900, height: 90), dark: dark, path: path)
    }
}

struct LookView: View {
    @ObservedObject var model: LookModel

    var body: some View {
        let c = model.config
        ZStack(alignment: .topLeading) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, r in
                piece(c).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
            }
        }
        .frame(width: model.width, height: model.height + 12, alignment: .topLeading)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: model.config)
    }

    /// The shape(s) to paint, in view coordinates.
    private var pieces: [CGRect] {
        let h = model.height
        switch model.config.shape {
        case .full: return [CGRect(x: 0, y: 0, width: model.width, height: h)]
        case .rounded: return [CGRect(x: 4, y: 2, width: model.width - 8, height: h - 4)]
        case .split:
            let room = (model.notch?.lowerBound ?? model.width) - 6          // the left piece never runs into the notch
            let leftEnd = max(160, min(room, model.appMenusMaxX + 14))
            let left = CGRect(x: 4, y: 2, width: leftEnd - 4, height: h - 4)
            let start = max(model.notch?.upperBound ?? 0, model.iconsMinX - 8)
            let right = CGRect(x: start, y: 2, width: model.width - start - 4, height: h - 4)
            return [left, right]
        }
    }

    @ViewBuilder private func piece(_ c: LookConfig) -> some View {
        let r: CGFloat = c.shape == .full ? 0 : CGFloat(c.radius)
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        shape.fill(fill(c))
            .overlay(shape.strokeBorder(c.border ? c.borderColor.color : .clear, lineWidth: CGFloat(c.borderWidth)))
            .shadow(color: c.shadow ? .black.opacity(0.35) : .clear, radius: 5, y: 2)
    }

    private func fill(_ c: LookConfig) -> AnyShapeStyle {
        switch c.tint {
        case .none: return AnyShapeStyle(Color.clear)
        case .solid: return AnyShapeStyle(c.solid.color)
        case .gradient: return AnyShapeStyle(LinearGradient(colors: [c.from.color, c.to.color], startPoint: .leading, endPoint: .trailing))
        }
    }
}
