import SwiftUI
import VikunjaCore

struct TaskDetailView: View {
    let store: Store
    let taskID: Int
    @Binding var path: [Route]

    var body: some View {
        VStack(spacing: 0) {
            Header(title: store.tasks[taskID]?.identifier ?? "任务", path: $path) {
                if let url = store.client?.webURL(task: taskID) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.borderless)
                    .help("在浏览器中打开")
                }
            }
            Divider()
            if let e = store.error {
                ErrorBanner(message: e) { store.error = nil }
            }
            if let task = store.tasks[taskID] {
                ScrollView {
                    content(task)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden)
        .task { await store.loadTask(taskID) }
    }

    @ViewBuilder private func content(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                DoneButton(store: store, task: task)
                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .strikethrough(task.done)
                    .textSelection(.enabled)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                if let p = store.project(task.projectID) {
                    Field(name: "项目") {
                        HStack(spacing: 5) {
                            Circle().fill(Color(hex: p.hexColor) ?? .secondary.opacity(0.4)).frame(width: 7, height: 7)
                            Text(p.title)
                        }
                    }
                }
                if let d = task.dueDate {
                    Field(name: "截止") {
                        Text(d.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(!task.done && d < .now ? .red : .primary)
                    }
                }
                if let d = task.startDate { Field(name: "开始") { Text(d.formatted(date: .abbreviated, time: .shortened)) } }
                if let d = task.endDate { Field(name: "结束") { Text(d.formatted(date: .abbreviated, time: .shortened)) } }
                if let name = task.priorityName { Field(name: "优先级") { Text(name) } }
                if task.percentDone > 0 {
                    Field(name: "进度") {
                        ProgressView(value: task.percentDone).frame(width: 120)
                    }
                }
                if !task.labels.isEmpty {
                    Field(name: "标签") {
                        HStack(spacing: 4) { ForEach(task.labels) { LabelChip(label: $0) } }
                    }
                }
                if !task.assignees.isEmpty {
                    Field(name: "指派") { Text(task.assignees.map(\.displayName).joined(separator: "、")) }
                }
                if let by = task.createdBy, let created = task.created {
                    Field(name: "创建") {
                        Text("\(by.displayName) · \(created.formatted(.relative(presentation: .named)))")
                    }
                }
            }
            .font(.callout)

            if let session = AgentSession(fields: CardFields.parse(task.description)) {
                SessionBox(store: store, session: session)
            }

            if !task.description.isEmpty {
                Divider()
                Markdown(text: task.description)
            }

            let comments = store.comments[taskID] ?? []
            if !comments.isEmpty {
                Divider()
                Text("评论 \(comments.count)").font(.headline)
                ForEach(comments) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.author.displayName).font(.caption.weight(.semibold))
                            Text(c.created.formatted(.relative(presentation: .named)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Markdown(text: c.comment)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 10))
                }
            }
        }
    }
}

struct Field<Value: View>: View {
    let name: String
    @ViewBuilder var value: Value

    var body: some View {
        GridRow {
            Text(name).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value
        }
    }
}

/// Descriptions and comments are fetched as Markdown; SwiftUI renders inline styles and links.
struct Markdown: View {
    let text: String

    var body: some View {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let rendered = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        Text(rendered).font(.callout).textSelection(.enabled)
    }
}

/// Resumes the Claude Code session an agent-board card records.
struct SessionBox: View {
    let store: Store
    let session: AgentSession
    @State private var copied = false

    var body: some View {
        let exists = Self.directoryExists(session.directory)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text("Claude 会话").font(.headline)
            }
            Text(session.directory)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            HStack {
                Button {
                    resume()
                } label: {
                    Label("在 Ghostty 恢复", systemImage: "play.fill")
                }
                .buttonStyle(.glassProminent)
                .disabled(!exists)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.shellCommand, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "已复制" : "复制命令", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.glass)
            }
            if !exists {
                Text("目录已不存在（worktree 可能已清理），无法在原目录恢复。")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func resume() {
        var info: NSDictionary?
        NSAppleScript(source: session.ghosttyScript)?.executeAndReturnError(&info)
        if let info {
            let message = info[NSAppleScript.errorMessage] as? String ?? "未知错误"
            store.error = "打开 Ghostty 失败：\(message)"
        }
    }

    static func directoryExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
