// SearchPanel.swift: type to find any menu bar icon, Enter (or a click) opens its menu.
// A floating panel that takes the keyboard without bringing Menu Bar Guard to the front.
import AppKit
import SwiftUI

@MainActor final class SearchModel: ObservableObject {
    @Published var query = ""
    @Published var all: [BarEntry] = []
    @Published var selected = 0
    @Published var openCount = 0
    var sectionOf: (BarEntry) -> BarSection = { _ in .visible }
    var results: [BarEntry] { SectionLogic.search(query, all) }
}

@MainActor final class SearchController {
    let model = SearchModel()
    private var panel: NonActivatingPanel?
    private var monitor: Any?
    private var keyMonitor: Any?
    var onPick: (BarEntry) -> Void = { _ in }
    var isShown: Bool { panel?.isVisible == true }

    func toggle(entries: [BarEntry], images: ItemImages) { isShown ? hide() : show(entries: entries, images: images) }

    func show(entries: [BarEntry], images: ItemImages) {
        model.all = entries; model.query = ""; model.selected = 0; model.openCount += 1
        let p = panel ?? make(images: images)
        panel = p
        guard let screen = MenuBarGeometry.screen else { return }
        let size = CGSize(width: 460, height: 380)
        let top = screen.frame.maxY - MenuBarGeometry.height(screen) - 60
        p.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height), display: true)
        p.orderFrontRegardless()
        p.makeKey()          // keyboard without activating the app (non-activating panel)
        monitor = monitor ?? NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        keyMonitor = keyMonitor ?? NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.isShown else { return e }
            return MainActor.assumeIsolated { self.key(e) ? nil : e }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Arrow keys move, Enter opens, Esc closes.
    private func key(_ e: NSEvent) -> Bool {
        let n = model.results.count
        switch e.keyCode {
        case 53: hide(); return true
        case 125: if n > 0 { model.selected = min(n - 1, model.selected + 1) }; return true
        case 126: model.selected = max(0, model.selected - 1); return true
        case 36, 76: pickSelected(); return true
        default: return false
        }
    }

    func pickSelected() {
        let r = model.results
        guard r.indices.contains(model.selected) else { return }
        let e = r[model.selected]
        hide(); onPick(e)
    }

    private func make(images: ItemImages) -> NonActivatingPanel {
        let p = NonActivatingPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                                   backing: .buffered, defer: true)
        p.level = .floating
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        let view = SearchView(model: model, images: images) { [weak self] e in self?.hide(); self?.onPick(e) }
        p.contentView = NSHostingView(rootView: view)
        return p
    }

    func snapshot(entries: [BarEntry], query: String, images: ItemImages, dark: Bool, path: String) {
        model.all = entries; model.query = query; model.selected = 0
        Snap.render(AnyView(SearchView(model: model, images: images) { _ in }), size: CGSize(width: 460, height: 380), dark: dark, path: path)
    }
}

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var images: ItemImages
    let pick: (BarEntry) -> Void
    @FocusState private var focused: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search menu bar icons", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 16)).focused($focused)
                    .onChange(of: model.query) { _, _ in model.selected = 0 }
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, e in
                            row(e, selected: i == model.selected).id(e.id)
                                .onTapGesture { pick(e) }
                        }
                    }
                    .padding(6)
                    .animation(.spring(duration: 0.25, bounce: 0.1), value: model.selected)
                }
                .onChange(of: model.selected) { _, v in if results.indices.contains(v) { proxy.scrollTo(results[v].id) } }
            }
            if results.isEmpty {
                Text(model.all.isEmpty ? "No icons found. Menu Bar Guard needs Accessibility access." : "Nothing matches.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 20)
            }
        }
        .frame(width: 460, height: 380)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .tint(guardAccent)
        .scaleEffect(shown || reduceMotion ? 1 : 0.97)
        .opacity(shown ? 1 : 0)
        .animation(.spring(duration: 0.32, bounce: 0.15), value: shown)
        .onAppear { shown = true; focused = true }
        .onChange(of: model.openCount) { _, _ in shown = false; focused = true; DispatchQueue.main.async { shown = true } }
    }

    private func row(_ e: BarEntry, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if let img = images.image(e) {
                    Image(nsImage: img).interpolation(.high).frame(width: max(22, min(e.width, 60)), height: 22)
                } else {
                    AppIcon(bundleID: e.bundleID, pid: e.pid).frame(width: 20, height: 20)
                }
            }
            .frame(width: 60)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(model.sectionOf(e).title).font(.system(size: 10.5)).foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary)
            }
            Spacer()
            if selected { Image(systemName: "return").font(.system(size: 11, weight: .semibold)) }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? guardAccent : Color.clear))
        .contentShape(Rectangle())
    }
}
