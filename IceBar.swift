// IceBar.swift: a small bar just under the menu bar (and the notch) that shows the hidden icons.
// Clicking one opens that icon's real menu. Never takes focus from the app you are using.
import AppKit
import SwiftUI

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class IceBarController {
    private var panel: NonActivatingPanel?
    private var monitor: Any?
    private let model = IceBarModel()
    var onPick: (BarEntry) -> Void = { _ in }
    var isShown: Bool { panel?.isVisible == true }

    func show(entries: [BarEntry], images: ItemImages, under anchor: CGRect?) {
        model.entries = entries
        model.openCount += 1
        let p = panel ?? makePanel(images: images)
        panel = p
        let host = p.contentView as? NSHostingView<IceBarView>
        host?.layoutSubtreeIfNeeded()
        let size = host?.fittingSize ?? CGSize(width: 200, height: 40)
        guard let screen = MenuBarGeometry.screen else { return }
        let top = screen.frame.maxY - MenuBarGeometry.height(screen) - 4
        let anchorMid = anchor.map { $0.midX } ?? screen.frame.midX
        let x = min(max(screen.frame.minX + 8, anchorMid - size.width + 26), screen.frame.maxX - size.width - 8)
        p.setFrame(CGRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        p.orderFrontRegardless()
        if monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func makePanel(images: ItemImages) -> NonActivatingPanel {
        let p = NonActivatingPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        let view = IceBarView(model: model, images: images) { [weak self] e in self?.hide(); self?.onPick(e) }
        let host = NSHostingView(rootView: view)
        host.sizingOptions = [.intrinsicContentSize]
        p.contentView = host
        return p
    }

    /// For tests: draw the bar into a PNG without showing it.
    func snapshot(entries: [BarEntry], images: ItemImages, dark: Bool, path: String) {
        model.entries = entries
        let v = IceBarView(model: model, images: images) { _ in }.environment(\.colorScheme, dark ? .dark : .light)
        Snap.render(AnyView(v.padding(20).background(Color(nsColor: .windowBackgroundColor))), size: nil, dark: dark, path: path)
    }
}

@MainActor final class IceBarModel: ObservableObject {
    @Published var entries: [BarEntry] = []
    @Published var openCount = 0
}

struct IceBarView: View {
    @ObservedObject var model: IceBarModel
    @ObservedObject var images: ItemImages
    let pick: (BarEntry) -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            if model.entries.isEmpty {
                Text("No hidden icons. Move some in Settings > Menu Bar Layout.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10)
            }
            ForEach(model.entries) { e in IceBarItem(entry: e, image: images.image(e), pick: pick) }
        }
        .padding(.horizontal, 6).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        .fixedSize()
        .padding(6)
        .scaleEffect(shown || reduceMotion ? 1 : 0.96, anchor: .topTrailing)
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : -6)
        .animation(.spring(duration: 0.3, bounce: 0), value: shown)
        .onAppear { shown = true }
        .onChange(of: model.openCount) { _, _ in shown = false; DispatchQueue.main.async { shown = true } }
    }
}

/// One hidden icon: its real picture if there is one, otherwise the app icon and name.
struct IceBarItem: View {
    let entry: BarEntry
    let image: NSImage?
    let pick: (BarEntry) -> Void
    @State private var hover = false

    var body: some View {
        Button { pick(entry) } label: {
            Group {
                if let image {
                    Image(nsImage: image).interpolation(.high).frame(width: entry.width, height: 24)
                } else {
                    HStack(spacing: 4) {
                        AppIcon(bundleID: entry.bundleID, pid: entry.pid).frame(width: 16, height: 16)
                        Text(entry.appName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                }
            }
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hover ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .onHover { h in withAnimation(.spring(duration: 0.2)) { hover = h } }
        .help(entry.title)
        .accessibilityLabel(entry.title)
    }
}

/// The app's icon, from its running copy or its location on disk.
struct AppIcon: View {
    let bundleID: String
    var pid: Int32 = 0
    var body: some View {
        let img = NSRunningApplication(processIdentifier: pid)?.icon
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        Image(nsImage: img).resizable().interpolation(.high)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Draws any SwiftUI view into a PNG without putting a window on screen.
enum Snap {
    @MainActor static func render(_ view: AnyView, size: CGSize?, dark: Bool, path: String) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        let s = size ?? host.fittingSize
        host.frame = CGRect(origin: .zero, size: s)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }
}
