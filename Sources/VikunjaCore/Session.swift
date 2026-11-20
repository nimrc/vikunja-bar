import Foundation

/// The `**key**: value` lines agent-board writes into a card's description.
public enum CardFields {
    public static func parse(_ markdown: String) -> [String: String] {
        var out = [String: String]()
        for line in markdown.split(whereSeparator: \.isNewline) {
            guard let m = line.wholeMatch(of: /\s*\*\*(.+?)\*\*:\s*(.*?)\s*/) else { continue }
            out[String(m.1)] = String(m.2)
        }
        return out
    }
}

/// A Claude Code session recorded on an agent-board card.
public struct AgentSession: Sendable, Equatable {
    public let directory: String
    public let sessionID: String

    /// Needs both the card's 目录 and a UUID in 会话; anything else is not resumable.
    public init?(fields: [String: String]) {
        guard let dir = fields["目录"], dir.hasPrefix("/"),
              let sid = fields["会话"], UUID(uuidString: sid) != nil else { return nil }
        directory = dir
        sessionID = sid.lowercased()
    }

    public var resumeCommand: String { "claude --resume \(sessionID)" }

    /// For pasting into any shell.
    public var shellCommand: String { "cd \(Self.quote(directory)) && \(resumeCommand)" }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Opens a new Ghostty window in the directory with the resume command typed into the user's own shell.
    public var ghosttyScript: String {
        """
        tell application "Ghostty"
        \tset cfg to new surface configuration
        \tset initial working directory of cfg to \(Self.appleScriptString(directory))
        \tset initial input of cfg to \(Self.appleScriptString(resumeCommand)) & linefeed
        \tnew window with configuration cfg
        \tactivate
        end tell
        """
    }

    static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
