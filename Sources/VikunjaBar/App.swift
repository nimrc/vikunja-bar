import AppKit
import SwiftUI
import VikunjaCore

@main
enum Entry {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let route = args.firstIndex(of: "--route").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
            Task {
                await snapshot(to: args[i + 1], route: route ?? "overview")
                exit(0)
            }
            RunLoop.main.run()
        }
        VikunjaBarApp.main()
    }
}

/// Renders the panel to a PNG. Uses VIKUNJA_URL and VIKUNJA_TOKEN when set, else the saved login.
/// Routes: overview, projects, project:<id>, task:<id>, search:<text>, settings.
@MainActor func snapshot(to path: String, route: String) async {
    _ = NSApplication.shared
    let env = ProcessInfo.processInfo.environment
    let credentials = env["VIKUNJA_URL"].flatMap(VikunjaClient.normalize(server:)).flatMap { url in
        env["VIKUNJA_TOKEN"].map { Credentials(server: url, token: $0) }
    } ?? Vault.load()
    let store = Store(credentials: route == "settings" ? nil : credentials)
    await store.refreshAll()

    let panel = Panel(store: store)
    var start = Panel.Start()
    let parts = route.split(separator: ":", maxSplits: 1).map(String.init)
    switch (parts.first ?? "", parts.count > 1 ? parts[1] : "") {
    case ("projects", _): start.tab = .projects
    case ("project", let id):
        start.tab = .projects
        if let id = Int(id) {
            start.path = [.project(id)]
            await store.loadProject(id)
        }
    case ("task", let id):
        if let id = Int(id) {
            start.path = [.task(id)]
            await store.loadTask(id)
        }
    case ("search", let q):
        start.query = q
        store.search(q)
        try? await Task.sleep(for: .milliseconds(800))
    default: break
    }

    let host = NSHostingView(rootView: panel.start(start).environment(\.colorScheme, .light))
    let size = NSSize(width: Panel.width, height: Panel.height)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.backgroundColor = .windowBackgroundColor
    window.contentView = host
    for _ in 0..<4 {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(250))
    }
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    if let e = store.error { print("error: \(e)") }
    print("\(path) \(Int(size.width))x\(Int(size.height))")
}

struct VikunjaBarApp: App {
    @State private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            Panel(store: store)
        } label: {
            let count = store.urgentCount
            Image(systemName: count > 0 ? "checklist.unchecked" : "checklist")
            if count > 0 { Text("\(count)") }
        }
        .menuBarExtraStyle(.window)
    }
}
