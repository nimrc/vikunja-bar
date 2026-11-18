import Foundation

public struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    public let items: [Item]
    public let page: Int
    public let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case items, page
        case totalPages = "total_pages"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An empty page comes back as `"items": null`.
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        page = try c.decode(Int.self, forKey: .page)
        totalPages = try c.decode(Int.self, forKey: .totalPages)
    }
}

public struct User: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let username: String
    public let name: String

    public init(id: Int, username: String, name: String) {
        self.id = id
        self.username = username
        self.name = name
    }

    public var displayName: String { name.isEmpty ? username : name }
}

public struct Project: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let title: String
    public let parentProjectID: Int
    public let hexColor: String
    public let isArchived: Bool
    public let isFavorite: Bool
    public let position: Double

    enum CodingKeys: String, CodingKey {
        case id, title, position
        case parentProjectID = "parent_project_id"
        case hexColor = "hex_color"
        case isArchived = "is_archived"
        case isFavorite = "is_favorite"
    }

    public init(id: Int, title: String, parentProjectID: Int = 0, hexColor: String = "",
                isArchived: Bool = false, isFavorite: Bool = false, position: Double = 0) {
        self.id = id
        self.title = title
        self.parentProjectID = parentProjectID
        self.hexColor = hexColor
        self.isArchived = isArchived
        self.isFavorite = isFavorite
        self.position = position
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        parentProjectID = try c.decodeIfPresent(Int.self, forKey: .parentProjectID) ?? 0
        hexColor = try c.decodeIfPresent(String.self, forKey: .hexColor) ?? ""
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        position = try c.decodeIfPresent(Double.self, forKey: .position) ?? 0
    }

    /// Saved filters are listed as projects with negative ids.
    public var isSavedFilter: Bool { id < 0 }
}

public struct ProjectView: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let title: String
    public let viewKind: String
    public let position: Double

    enum CodingKeys: String, CodingKey {
        case id, title, position
        case viewKind = "view_kind"
    }

    public init(id: Int, title: String, viewKind: String, position: Double) {
        self.id = id
        self.title = title
        self.viewKind = viewKind
        self.position = position
    }
}

public struct Label: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let title: String
    public let hexColor: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case hexColor = "hex_color"
    }

    public init(id: Int, title: String, hexColor: String) {
        self.id = id
        self.title = title
        self.hexColor = hexColor
    }
}

public struct TaskItem: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public var title: String
    public var description: String
    public var done: Bool
    public var dueDate: Date?
    public var startDate: Date?
    public var endDate: Date?
    public var priority: Int
    public var percentDone: Double
    public let projectID: Int
    public let identifier: String
    public var labels: [Label]
    public var assignees: [User]
    public let createdBy: User?
    public let created: Date?
    public let updated: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, done, priority, identifier, labels, assignees, created, updated
        case dueDate = "due_date"
        case startDate = "start_date"
        case endDate = "end_date"
        case percentDone = "percent_done"
        case projectID = "project_id"
        case createdBy = "created_by"
    }

    public init(id: Int, title: String, description: String = "", done: Bool = false, dueDate: Date? = nil,
                startDate: Date? = nil, endDate: Date? = nil, priority: Int = 0, percentDone: Double = 0,
                projectID: Int, identifier: String = "", labels: [Label] = [], assignees: [User] = [],
                createdBy: User? = nil, created: Date? = nil, updated: Date? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.done = done
        self.dueDate = dueDate
        self.startDate = startDate
        self.endDate = endDate
        self.priority = priority
        self.percentDone = percentDone
        self.projectID = projectID
        self.identifier = identifier
        self.labels = labels
        self.assignees = assignees
        self.createdBy = createdBy
        self.created = created
        self.updated = updated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        dueDate = try Self.date(c, .dueDate)
        startDate = try Self.date(c, .startDate)
        endDate = try Self.date(c, .endDate)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        percentDone = try c.decodeIfPresent(Double.self, forKey: .percentDone) ?? 0
        projectID = try c.decode(Int.self, forKey: .projectID)
        identifier = try c.decodeIfPresent(String.self, forKey: .identifier) ?? ""
        labels = try c.decodeIfPresent([Label].self, forKey: .labels) ?? []
        assignees = try c.decodeIfPresent([User].self, forKey: .assignees) ?? []
        createdBy = try c.decodeIfPresent(User.self, forKey: .createdBy)
        created = try Self.date(c, .created)
        updated = try Self.date(c, .updated)
    }

    /// Vikunja sends unset dates as year 1 rather than null.
    static func date(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Date? {
        guard let d = try c.decodeIfPresent(Date.self, forKey: key) else { return nil }
        return d.timeIntervalSince1970 < 0 ? nil : d
    }

    public static let priorityNames = ["无", "低", "中", "高", "紧急", "立即"]

    public var priorityName: String? {
        priority > 0 && priority < Self.priorityNames.count ? Self.priorityNames[priority] : nil
    }
}

public struct Comment: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let comment: String
    public let author: User
    public let created: Date

    public init(id: Int, comment: String, author: User, created: Date) {
        self.id = id
        self.comment = comment
        self.author = author
        self.created = created
    }
}
