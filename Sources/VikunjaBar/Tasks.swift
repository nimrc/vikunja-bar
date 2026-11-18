import SwiftUI
import VikunjaCore

struct TaskList: View {
    let store: Store
    let tasks: [TaskItem]
    let showProject: Bool
    @Binding var path: [Route]
    let empty: String

    var body: some View {
        if tasks.isEmpty {
            EmptyState(text: empty, symbol: "tray")
        } else {
            List(tasks) { task in
                TaskRow(store: store, task: task, showProject: showProject) { path.append(.task(task.id)) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

struct TaskRow: View {
    let store: Store
    let task: TaskItem
    let showProject: Bool
    let open: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            DoneButton(store: store, task: task)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? .secondary : .primary)
                    .lineLimit(2)
                TaskMeta(store: store, task: task, showProject: showProject)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture(perform: open)
    }
}

struct DoneButton: View {
    let store: Store
    let task: TaskItem
    @State private var busy = false

    var body: some View {
        Button {
            busy = true
            Task {
                await store.toggleDone(task)
                busy = false
            }
        } label: {
            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.done ? Color.accentColor : .secondary)
                .imageScale(.large)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help(task.done ? "标记为未完成" : "标记为完成")
    }
}

struct TaskMeta: View {
    let store: Store
    let task: TaskItem
    let showProject: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showProject, let p = store.project(task.projectID) {
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: p.hexColor) ?? .secondary.opacity(0.4)).frame(width: 6, height: 6)
                    Text(p.title).lineLimit(1)
                }
            }
            if let due = task.dueDate {
                Label(DueText.short(due), systemImage: "calendar")
                    .foregroundStyle(!task.done && due < .now ? .red : .secondary)
            }
            if task.priority >= 3, let name = task.priorityName {
                Label(name, systemImage: "flag.fill").foregroundStyle(task.priority >= 4 ? .red : .orange)
            }
            ForEach(task.labels.prefix(2)) { LabelChip(label: $0) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }
}

struct LabelChip: View {
    let label: VikunjaCore.Label

    var body: some View {
        let color = Color(hex: label.hexColor) ?? .gray
        Text(label.title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: .capsule)
    }
}

enum DueText {
    static func short(_ date: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "今天 \(time)" }
        if calendar.isDateInTomorrow(date) { return "明天 \(time)" }
        if calendar.isDateInYesterday(date) { return "昨天 \(time)" }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month().day())
        }
        return date.formatted(.dateTime.year().month().day())
    }
}

struct ProjectTasksView: View {
    let store: Store
    let projectID: Int
    @Binding var path: [Route]
    @State private var newTitle = ""
    @State private var adding = false
    @State private var loaded = false

    var body: some View {
        let project = store.project(projectID)
        VStack(spacing: 0) {
            Header(title: project?.title ?? "项目", path: $path) {
                Button {
                    Task { await store.loadProject(projectID) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新")
            }
            if project?.isSavedFilter == false {
                HStack {
                    Image(systemName: "plus").foregroundStyle(.secondary)
                    TextField("添加任务，回车保存", text: $newTitle)
                        .textFieldStyle(.plain)
                        .disabled(adding)
                        .onSubmit {
                            adding = true
                            Task {
                                if await store.addTask(project: projectID, title: newTitle) { newTitle = "" }
                                adding = false
                            }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            Divider()
            if let e = store.error {
                ErrorBanner(message: e) { store.error = nil }
            }
            if let tasks = store.projectTasks[projectID] {
                TaskList(store: store, tasks: tasks, showProject: project?.isSavedFilter ?? false, path: $path,
                         empty: "没有任务")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden)
        .task {
            guard !loaded else { return }
            loaded = true
            await store.loadProject(projectID)
        }
    }
}

/// A back button and title, since the menu bar window has no toolbar.
struct Header<Trailing: View>: View {
    let title: String
    @Binding var path: [Route]
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Button {
                _ = path.popLast()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("返回")
            Text(title).font(.headline).lineLimit(1)
            Spacer()
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
