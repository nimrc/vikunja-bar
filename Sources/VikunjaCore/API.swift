import Foundation

public struct APIError: LocalizedError, Sendable, Equatable {
    public let status: Int
    public let message: String

    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }

    public var errorDescription: String? { "\(message)（HTTP \(status)）" }
}

/// Client for Vikunja's /api/v2, authenticated with an API token.
public struct VikunjaClient: Sendable {
    public let server: URL
    public let token: String
    let session: URLSession

    public init(server: URL, token: String, session: URLSession = .shared) {
        self.server = server
        self.token = token
        self.session = session
    }

    /// Accepts a bare host, the web app's URL, or one ending in /api/vN.
    public static func normalize(server input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard var c = URLComponents(string: s), let host = c.host, !host.isEmpty else { return nil }
        var path = c.path
        while path.hasSuffix("/") { path.removeLast() }
        if let r = path.range(of: #"/api/v\d+$"#, options: .regularExpression) { path.removeSubrange(r) }
        c.path = path
        c.query = nil
        c.fragment = nil
        return c.url
    }

    /// Where a task opens in the web app.
    public func webURL(task id: Int) -> URL { server.appending(path: "tasks/\(id)") }

    public func me() async throws -> User {
        try await get("user")
    }

    public func projects() async throws -> [Project] {
        try await all("projects", query: [:])
    }

    public func views(project: Int) async throws -> [ProjectView] {
        try await all("projects/\(project)/views", query: [:])
    }

    /// Tasks as a view shows them, with its filter and sort.
    public func tasks(project: Int, view: Int) async throws -> [TaskItem] {
        try await all("projects/\(project)/views/\(view)/tasks", query: [:])
    }

    /// Tasks across all projects. `filter` uses Vikunja's filter syntax, e.g. `done = false`.
    public func tasks(filter: String? = nil, search: String? = nil, sortBy: [String] = [],
                      limit: Int = 100) async throws -> [TaskItem] {
        var q = ["per_page": String(limit)]
        if let filter { q["filter"] = filter }
        if let search { q["q"] = search }
        var items = [URLQueryItem]()
        for s in sortBy {
            items.append(URLQueryItem(name: "sort_by", value: s))
            items.append(URLQueryItem(name: "order_by", value: "asc"))
        }
        let page: Page<TaskItem> = try await get("tasks", query: q, extra: items)
        return page.items
    }

    public func task(_ id: Int) async throws -> TaskItem {
        try await get("tasks/\(id)", query: ["format": "markdown"])
    }

    public func comments(task: Int) async throws -> [Comment] {
        try await all("tasks/\(task)/comments", query: ["format": "markdown"])
    }

    /// PATCH, because PUT replaces every field of the task.
    public func setDone(task: Int, done: Bool) async throws -> TaskItem {
        try await send("PATCH", "tasks/\(task)", body: ["done": done])
    }

    public func createTask(project: Int, title: String) async throws -> TaskItem {
        try await send("POST", "projects/\(project)/tasks", body: ["title": title])
    }

    // MARK: - Transport

    func all<Item: Decodable & Sendable>(_ path: String, query: [String: String]) async throws -> [Item] {
        var out = [Item]()
        var page = 1
        while true {
            var q = query
            q["page"] = String(page)
            q["per_page"] = "100"
            let p: Page<Item> = try await get(path, query: q)
            out += p.items
            if p.page >= p.totalPages || p.items.isEmpty { return out }
            page += 1
        }
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:], extra: [URLQueryItem] = []) async throws -> T {
        try await perform(request("GET", path, query: query, extra: extra))
    }

    func send<T: Decodable>(_ method: String, _ path: String, body: [String: any Sendable]) async throws -> T {
        var r = request(method, path, query: [:], extra: [])
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(r)
    }

    func request(_ method: String, _ path: String, query: [String: String], extra: [URLQueryItem]) -> URLRequest {
        var c = URLComponents(url: server.appending(path: "api/v2/" + path), resolvingAgainstBaseURL: false)!
        let items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } + extra
        c.queryItems = items.isEmpty ? nil : items
        var r = URLRequest(url: c.url!)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.timeoutInterval = 20
        return r
    }

    func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, message: Self.errorMessage(data) ?? HTTPURLResponse.localizedString(forStatusCode: status))
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    /// v2 errors carry `detail`/`title`; the auth middleware still answers with v1's `message`.
    static func errorMessage(_ data: Data) -> String? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["detail", "message", "title"] {
            if let s = o[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(s, strategy: .iso8601) { return date }
            if let date = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()
}
