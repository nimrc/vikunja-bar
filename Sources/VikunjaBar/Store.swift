import Foundation
import Observation
import ServiceManagement
import VikunjaCore

@MainActor @Observable
final class Store {
    private(set) var client: VikunjaClient?
    private(set) var me: User?
    private(set) var projects = [Project]()
    /// Every open task, for the overview and the menu bar count.
    private(set) var openTasks = [TaskItem]()
    private(set) var projectTasks = [Int: [TaskItem]]()
    private(set) var tasks = [Int: TaskItem]()
    private(set) var comments = [Int: [Comment]]()
    private(set) var searchResults = [TaskItem]()
    private(set) var lastUpdated: Date?
    private(set) var refreshing = false
    var error: String?

    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                self.error = "开机启动设置失败：\(error.localizedDescription)"
            }
        }
    }

    private var poller: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(credentials: Credentials? = Vault.load()) {
        if let credentials {
            client = VikunjaClient(server: credentials.server, token: credentials.token)
            startPolling()
        }
    }

    var urgentCount: Int { Organize.urgentCount(openTasks) }

    func project(_ id: Int) -> Project? { projects.first { $0.id == id } }

    // MARK: - Account

    /// Checks the token against the server before saving it.
    func connect(server input: String, token: String) async {
        guard let server = VikunjaClient.normalize(server: input) else {
            error = "服务器地址无效"
            return
        }
        let candidate = VikunjaClient(server: server, token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            me = try await candidate.me()
            try Vault.save(Credentials(server: server, token: candidate.token))
            client = candidate
            error = nil
            startPolling()
        } catch {
            self.error = "连接失败：\(error.localizedDescription)"
        }
    }

    func signOut() {
        poller?.cancel()
        Vault.delete()
        client = nil
        me = nil
        projects = []
        openTasks = []
        projectTasks = [:]
        tasks = [:]
        comments = [:]
        searchResults = []
        lastUpdated = nil
    }

    // MARK: - Loading

    private func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func refreshIfStale() {
        if let lastUpdated, Date.now.timeIntervalSince(lastUpdated) < 60 { return }
        Task { await refreshAll() }
    }

    func refreshAll() async {
        guard let client, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            async let user = client.me()
            async let projectList = client.projects()
            async let open = client.tasks(filter: "done = false", sortBy: ["due_date", "id"], limit: 250)
            (me, projects, openTasks) = try await (user, projectList, open)
            lastUpdated = .now
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Loads a project's tasks through its first list view, so its filter (usually `done = false`) applies.
    func loadProject(_ id: Int) async {
        guard let client else { return }
        do {
            let views = try await client.views(project: id).sorted { $0.position < $1.position }
            guard let view = views.first(where: { $0.viewKind == "list" }) ?? views.first else {
                projectTasks[id] = []
                return
            }
            projectTasks[id] = try await client.tasks(project: id, view: view.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadTask(_ id: Int) async {
        guard let client else { return }
        do {
            async let task = client.task(id)
            async let list = client.comments(task: id)
            (tasks[id], comments[id]) = try await (task, list)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func search(_ query: String) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let client else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let found = try await client.tasks(search: q, sortBy: ["done", "due_date"], limit: 50)
                if !Task.isCancelled { searchResults = found }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    // MARK: - Changes

    func toggleDone(_ task: TaskItem) async {
        guard let client else { return }
        do {
            apply(try await client.setDone(task: task.id, done: !task.done))
        } catch {
            self.error = "更新失败：\(error.localizedDescription)"
        }
    }

    func addTask(project: Int, title: String) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard let client, !title.isEmpty else { return false }
        do {
            let task = try await client.createTask(project: project, title: title)
            projectTasks[project, default: []].insert(task, at: 0)
            openTasks.append(task)
            return true
        } catch {
            self.error = "添加失败：\(error.localizedDescription)"
            return false
        }
    }

    /// Updates every list that shows the task; a finished task stays in place until the next reload.
    private func apply(_ task: TaskItem) {
        if tasks[task.id] != nil {
            // PATCH answers in HTML; keep the markdown description already loaded.
            tasks[task.id]?.done = task.done
        }
        for (project, list) in projectTasks {
            if let i = list.firstIndex(where: { $0.id == task.id }) { projectTasks[project]?[i].done = task.done }
        }
        if let i = searchResults.firstIndex(where: { $0.id == task.id }) { searchResults[i].done = task.done }
        if task.done {
            openTasks.removeAll { $0.id == task.id }
        } else if !openTasks.contains(where: { $0.id == task.id }) {
            openTasks.append(task)
        }
    }
}
