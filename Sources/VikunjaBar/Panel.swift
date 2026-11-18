import SwiftUI
import VikunjaCore

enum Route: Hashable {
    case project(Int)
    case task(Int)
}

enum Tab: String, CaseIterable {
    case overview = "概览"
    case projects = "项目"
}

struct Panel: View {
    static let width: CGFloat = 400
    static let height: CGFloat = 580

    struct Start {
        var tab = Tab.overview
        var path = [Route]()
        var query = ""
    }

    @Bindable var store: Store
    @State private var tab = Tab.overview
    @State private var path = [Route]()
    @State private var query = ""
    private var initial: Start?

    init(store: Store) {
        self.store = store
    }

    /// Opens on a given screen; used by `--snapshot`.
    func start(_ s: Start) -> Panel {
        var p = self
        p.initial = s
        p._tab = State(initialValue: s.tab)
        p._path = State(initialValue: s.path)
        p._query = State(initialValue: s.query)
        return p
    }

    var body: some View {
        Group {
            if store.client == nil {
                ConnectView(store: store)
            } else {
                NavigationStack(path: $path) {
                    home
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .project(let id): ProjectTasksView(store: store, projectID: id, path: $path)
                            case .task(let id): TaskDetailView(store: store, taskID: id, path: $path)
                            }
                        }
                }
            }
        }
        .frame(width: Self.width, height: Self.height)
        .onAppear { store.refreshIfStale() }
    }

    private var home: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
                SearchField(text: $query)
                    .onChange(of: query) { store.search(query) }
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.refreshing)
                .help("刷新")
                AccountMenu(store: store)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
            if let e = store.error {
                ErrorBanner(message: e) { store.error = nil }
            }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                TaskList(store: store, tasks: store.searchResults, showProject: true, path: $path,
                         empty: "没有匹配的任务")
            } else {
                switch tab {
                case .overview: OverviewView(store: store, path: $path)
                case .projects: ProjectsView(store: store, path: $path)
                }
            }
        }
        .toolbar(.hidden)
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索任务", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }
}

struct AccountMenu: View {
    @Bindable var store: Store

    var body: some View {
        Menu {
            if let me = store.me, let server = store.client?.server.host() {
                Text("\(me.displayName) @ \(server)")
            }
            if let server = store.client?.server {
                Button("在浏览器中打开 Vikunja") { NSWorkspace.shared.open(server) }
            }
            Toggle("开机启动", isOn: $store.launchAtLogin)
            Divider()
            Button("断开账号") { store.signOut() }
            Button("退出") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).textSelection(.enabled)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(8)
        .background(.orange.opacity(0.1))
    }
}

struct OverviewView: View {
    let store: Store
    @Binding var path: [Route]

    var body: some View {
        let groups = Organize.overview(store.openTasks)
        if groups.isEmpty {
            EmptyState(text: store.lastUpdated == nil ? "加载中…" : "没有未完成的任务", symbol: "checkmark.seal")
        } else {
            List {
                ForEach(groups, id: \.0) { bucket, tasks in
                    Section {
                        ForEach(tasks) { task in
                            TaskRow(store: store, task: task, showProject: true) { path.append(.task(task.id)) }
                        }
                    } header: {
                        HStack {
                            Text(bucket.title)
                            Spacer()
                            Text("\(tasks.count)")
                        }
                        .foregroundStyle(bucket == .overdue ? .red : .secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }
}

struct ProjectsView: View {
    let store: Store
    @Binding var path: [Route]

    var body: some View {
        let tree = Organize.tree(store.projects)
        let filters = store.projects.filter(\.isSavedFilter)
        let counts = Dictionary(grouping: store.openTasks, by: \.projectID).mapValues(\.count)
        List {
            Section("项目") {
                ForEach(tree, id: \.project.id) { item in
                    ProjectRow(project: item.project, count: counts[item.project.id] ?? 0)
                        .padding(.leading, CGFloat(item.depth) * 16)
                        .contentShape(.rect)
                        .onTapGesture { path.append(.project(item.project.id)) }
                }
            }
            if !filters.isEmpty {
                Section("过滤器") {
                    ForEach(filters) { f in
                        ProjectRow(project: f, count: nil)
                            .contentShape(.rect)
                            .onTapGesture { path.append(.project(f.id)) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

struct ProjectRow: View {
    let project: Project
    let count: Int?

    var body: some View {
        HStack(spacing: 8) {
            if project.isSavedFilter {
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
            } else {
                Circle().fill(Color(hex: project.hexColor) ?? .secondary.opacity(0.4)).frame(width: 8, height: 8)
            }
            Text(project.title).lineLimit(1)
            if project.isFavorite {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
            }
            Spacer()
            if let count, count > 0 {
                Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct EmptyState: View {
    let text: String
    let symbol: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Color {
    /// Vikunja colors are 6-digit hex without `#`; empty means none.
    init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
