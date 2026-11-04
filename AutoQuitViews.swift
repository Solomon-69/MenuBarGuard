// AutoQuitViews.swift: the priority list and the log, used by the panel and the Settings window.
import AppKit
import SwiftUI

struct PriorityList: View {
    @ObservedObject var engine: Engine
    @State private var dragging: String?


    var body: some View {
        VStack(spacing: 8) {
            if !engine.quit.isEmpty { closedBox }
            Text("Top = keep longest. Roomy closes from the bottom up, only apps with Auto-quit on.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(engine.rules) { r in
                        row(r)
                            .onDrag { dragging = r.bundleID; return NSItemProvider(object: r.bundleID as NSString) }
                            .onDrop(of: [.text], delegate: ReorderDrop(item: r, engine: engine, dragging: $dragging))
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(duration: 0.3, bounce: 0.1), value: engine.rules.map(\.bundleID))
            }
        }
    }

    private var closedBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Closed by Roomy", systemImage: "moon.zzz.fill").font(.system(size: 11, weight: .semibold))
                Spacer()
                if engine.quit.count > 1 { Button("Restart all") { engine.restartAll() }.buttonStyle(MiniButton()) }
            }
            ForEach(engine.quit) { q in
                HStack {
                    icon(q.path ?? engine.appPath(bundleID: q.bundleID)).frame(width: 20, height: 20)
                    Text(q.name).font(.system(size: 12))
                    Spacer()
                    Button("Restart") { engine.restart(q) }.buttonStyle(MiniButton())
                }
            }
        }
        .padding(10).card()
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private func row(_ r: Rule) -> some View {
        let running = engine.layout?.items.contains { $0.bundleID == r.bundleID }
            ?? !NSRunningApplication.runningApplications(withBundleIdentifier: r.bundleID).isEmpty
        let closed = engine.quit.contains { $0.bundleID == r.bundleID }
        return HStack(spacing: 10) {
            icon(engine.appPath(r)).frame(width: 28, height: 28).opacity(running ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 0) {
                Text(r.name).font(.system(size: 12.5, weight: .medium))
                Text(closed ? "Closed by Roomy" : running ? "In the menu bar" : "Not running")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { engine.setNever(r.bundleID, !r.neverQuit) } label: {
                Image(systemName: r.neverQuit ? "lock.fill" : "lock.open")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(r.neverQuit ? guardAccent : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(r.neverQuit ? guardAccent.opacity(0.16) : Color.clear))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain).focusEffectDisabled().help("Never quit this app")
            VStack(spacing: 1) {
                SmoothSwitch(isOn: r.autoQuit, title: "Auto-quit \(r.name)", tint: guardAccent, width: 34) { engine.setAuto(r.bundleID, $0) }
                    .opacity(r.neverQuit ? 0.3 : 1).allowsHitTesting(!r.neverQuit)
                Text("Auto-quit").font(.system(size: 8.5)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .card()
    }

    func icon(_ path: String?) -> some View {
        Image(nsImage: path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
            .resizable().interpolation(.high)
    }

}

struct LogList: View {
    @ObservedObject var engine: Engine


    var body: some View {
        VStack(spacing: 8) {
            if engine.log.isEmpty {
                Spacer()
                Text("Nothing yet. When Roomy closes or restarts an app, it is written here.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(engine.log.prefix(80)) { e in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: symbol(e.kind)).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(color(e.kind)).frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                                    Text(e.date.formatted(date: .abbreviated, time: .standard)).font(.system(size: 9.5)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8).card()
                        }
                    }
                }
                HStack { Spacer(); Button("Clear log") { engine.clearLog() }.buttonStyle(MiniButton()) }
            }
        }
    }

    private func symbol(_ k: String) -> String {
        switch k { case "quit": return "power"; case "restore": return "arrow.clockwise"; case "warn": return "exclamationmark.triangle.fill"; default: return "info.circle" }
    }
    private func color(_ k: String) -> Color {
        switch k { case "quit": return .red; case "restore": return guardAccent; case "warn": return .orange; default: return .secondary }
    }

}
