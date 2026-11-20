import Foundation
import Testing
@testable import VikunjaCore

@Suite struct DecodingTests {
    @Test func taskTreatsYearOneAsNoDateAndNullListsAsEmpty() throws {
        let json = """
        {"id":5,"title":"Order merch","description":"","done":false,"due_date":"2026-11-20T12:00:00Z",
         "start_date":"0001-01-01T00:00:00Z","end_date":"0001-01-01T00:00:00Z","priority":3,"percent_done":0,
         "project_id":2,"identifier":"#5","labels":null,"assignees":null,
         "created":"2026-11-17T09:28:13.245396Z","updated":"2026-11-17T09:28:13Z"}
        """
        let t = try VikunjaClient.decoder.decode(TaskItem.self, from: Data(json.utf8))
        #expect(t.dueDate == Date(timeIntervalSince1970: 1_795_176_000))
        #expect(t.startDate == nil)
        #expect(t.endDate == nil)
        #expect(t.labels.isEmpty)
        #expect(t.assignees.isEmpty)
        #expect(t.created != nil)
        #expect(t.priorityName == "高")
    }

    @Test func emptyPageHasNullItems() throws {
        let json = #"{"items":null,"page":1,"per_page":50,"total":0,"total_pages":0}"#
        let p = try VikunjaClient.decoder.decode(Page<Project>.self, from: Data(json.utf8))
        #expect(p.items.isEmpty)
    }

    @Test func savedFiltersHaveNegativeIDs() {
        #expect(Project(id: -2, title: "My Open Tasks").isSavedFilter)
        #expect(!Project(id: 2, title: "Studio").isSavedFilter)
    }
}

@Suite struct ClientTests {
    @Test(arguments: [
        ("vikunja.example.com", "https://vikunja.example.com"),
        ("https://vikunja.example.com/", "https://vikunja.example.com"),
        ("https://vikunja.example.com/api/v1", "https://vikunja.example.com"),
        ("http://127.0.0.1:3456/api/v2/", "http://127.0.0.1:3456"),
        ("https://example.com/vikunja/?x=1", "https://example.com/vikunja"),
    ])
    func normalizesServer(input: String, expected: String) {
        #expect(VikunjaClient.normalize(server: input)?.absoluteString == expected)
    }

    @Test func rejectsServerWithoutHost() {
        #expect(VikunjaClient.normalize(server: "  ") == nil)
    }

    @Test func errorMessagePrefersDetail() {
        let v2 = Data(#"{"title":"Not Found","status":404,"detail":"This task does not exist","code":4002}"#.utf8)
        let v1 = Data(#"{"code":11,"message":"missing, malformed, expired or otherwise invalid token provided"}"#.utf8)
        #expect(VikunjaClient.errorMessage(v2) == "This task does not exist")
        #expect(VikunjaClient.errorMessage(v1) == "missing, malformed, expired or otherwise invalid token provided")
        #expect(VikunjaClient.errorMessage(Data("oops".utf8)) == nil)
    }

    @Test func requestCarriesTokenAndQuery() {
        let c = VikunjaClient(server: URL(string: "https://v.example.com/sub")!, token: "tk_1")
        let r = c.request("GET", "tasks", query: ["per_page": "5", "filter": "done = false"],
                          extra: [URLQueryItem(name: "sort_by", value: "due_date")])
        #expect(r.url?.absoluteString == "https://v.example.com/sub/api/v2/tasks?filter=done%20%3D%20false&per_page=5&sort_by=due_date")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer tk_1")
        #expect(c.webURL(task: 7).absoluteString == "https://v.example.com/sub/tasks/7")
    }

    @Test func followsPagesAndPatchesDone() async throws {
        let session = StubProtocol.session { request in
            let url = request.url!
            switch (request.httpMethod, url.path) {
            case ("GET", "/api/v2/projects"):
                let page = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                    .queryItems!.first { $0.name == "page" }!.value!
                let item = page == "1" ? #"{"id":1,"title":"Inbox"}"# : #"{"id":2,"title":"Home"}"#
                return (200, #"{"items":[\#(item)],"page":\#(page),"per_page":1,"total":2,"total_pages":2}"#)
            case ("PATCH", "/api/v2/tasks/9"):
                let body = try! JSONSerialization.jsonObject(with: StubProtocol.body(request)) as! [String: Any]
                #expect(body as NSDictionary == ["done": true] as NSDictionary)
                return (200, #"{"id":9,"title":"T","done":true,"project_id":1}"#)
            case ("GET", "/api/v2/tasks/404"):
                return (404, #"{"title":"Not Found","status":404,"detail":"This task does not exist"}"#)
            default:
                return (500, "{}")
            }
        }
        let c = VikunjaClient(server: URL(string: "https://stub.test")!, token: "t", session: session)
        #expect(try await c.projects().map(\.title) == ["Inbox", "Home"])
        #expect(try await c.setDone(task: 9, done: true).done)
        await #expect(throws: APIError(status: 404, message: "This task does not exist")) {
            try await c.task(404)
        }
    }
}

@Suite struct OrganizeTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    // 2026-11-18 10:00 in Shanghai
    let now = Date(timeIntervalSince1970: 1_794_967_200)

    func task(_ id: Int, dueIn hours: Double?, priority: Int = 0, done: Bool = false) -> TaskItem {
        TaskItem(id: id, title: "t\(id)", done: done, dueDate: hours.map { now.addingTimeInterval($0 * 3600) },
                 priority: priority, projectID: 1)
    }

    @Test func groupsByDueDate() {
        let tasks = [
            task(1, dueIn: -1), task(2, dueIn: 5), task(3, dueIn: 30), task(4, dueIn: 24 * 10),
            task(5, dueIn: nil), task(6, dueIn: -2, done: true),
        ]
        let groups = Organize.overview(tasks, now: now, calendar: calendar)
        #expect(groups.map(\.0) == [.overdue, .today, .week, .later, .undated])
        #expect(groups.map { $0.1.map(\.id) } == [[1], [2], [3], [4], [5]])
        #expect(Organize.urgentCount(tasks, now: now, calendar: calendar) == 2)
    }

    @Test func sameDueDateSortsByPriority() {
        let groups = Organize.overview([task(1, dueIn: 3, priority: 1), task(2, dueIn: 3, priority: 4)],
                                       now: now, calendar: calendar)
        #expect(groups.first?.1.map(\.id) == [2, 1])
    }

    @Test func treePutsChildrenUnderParentsAndDropsArchivedAndFilters() {
        let projects = [
            Project(id: 3, title: "Home", position: 3),
            Project(id: 1, title: "Inbox", position: 1),
            Project(id: 4, title: "Kitchen", parentProjectID: 3, position: 1),
            Project(id: 5, title: "Old", isArchived: true, position: 2),
            Project(id: 6, title: "Orphan", parentProjectID: 99, position: 9),
            Project(id: -2, title: "My Open Tasks"),
        ]
        let tree = Organize.tree(projects)
        #expect(tree.map(\.project.id) == [1, 3, 4, 6])
        #expect(tree.map(\.depth) == [0, 0, 1, 0])
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (Int, String)
    nonisolated(unsafe) static var handlers = [String: Handler]()
    static let lock = NSLock()

    static func session(_ handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = handler }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.httpAdditionalHeaders = ["X-Stub": id]
        return URLSession(configuration: config)
    }

    static func body(_ request: URLRequest) -> Data {
        if let d = request.httpBody { return d }
        guard let s = request.httpBodyStream else { return Data() }
        s.open()
        defer { s.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while s.hasBytesAvailable {
            let n = s.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Stub") ?? ""
        let handler = Self.lock.withLock { Self.handlers[id] }
        let (status, body) = handler?(request) ?? (500, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite struct SessionTests {
    let description = """
    **当前进展**: token id=3 已建

    **仓库**: vikunja

    **目录**: /Users/tswang/code/app/vikunja

    **Agent**: claude · herdr w1:p3

    **会话**: F5E492DE-8C0A-4E54-BF86-440BA2A4E354
    """

    @Test func parsesAgentBoardFields() {
        let f = CardFields.parse(description)
        #expect(f["仓库"] == "vikunja")
        #expect(f["Agent"] == "claude · herdr w1:p3")
        #expect(f["当前进展"] == "token id=3 已建")
    }

    @Test func buildsResumeCommands() throws {
        let s = try #require(AgentSession(fields: CardFields.parse(description)))
        #expect(s.resumeCommand == "claude --resume f5e492de-8c0a-4e54-bf86-440ba2a4e354")
        #expect(s.shellCommand == "cd '/Users/tswang/code/app/vikunja' && claude --resume f5e492de-8c0a-4e54-bf86-440ba2a4e354")
        #expect(s.ghosttyScript.contains(#"set initial working directory of cfg to "/Users/tswang/code/app/vikunja""#))
    }

    @Test func quotesAwkwardPaths() throws {
        let s = try #require(AgentSession(fields: ["目录": #"/tmp/it's "x""#, "会话": UUID().uuidString]))
        #expect(s.shellCommand.hasPrefix(#"cd '/tmp/it'\''s "x"' && "#))
        #expect(s.ghosttyScript.contains(#"to "/tmp/it's \"x\"""#))
    }

    @Test(arguments: [
        ["目录": "/x"],
        ["会话": "f5e492de-8c0a-4e54-bf86-440ba2a4e354"],
        ["目录": "relative", "会话": "f5e492de-8c0a-4e54-bf86-440ba2a4e354"],
        ["目录": "/x", "会话": "not-a-uuid; rm -rf /"],
    ])
    func rejectsIncompleteOrUnsafeFields(fields: [String: String]) {
        #expect(AgentSession(fields: fields) == nil)
    }
}
