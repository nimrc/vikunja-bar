import SwiftUI
import VikunjaCore

struct ConnectView: View {
    let store: Store
    @State private var server = ""
    @State private var token = ""
    @State private var connecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "checklist").font(.title2)
                Text("连接 Vikunja").font(.title3.weight(.semibold))
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("服务器").font(.caption).foregroundStyle(.secondary)
                TextField("https://vikunja.example.com", text: $server).textFieldStyle(.roundedBorder)
                Text("API Token").font(.caption).foregroundStyle(.secondary)
                SecureField("tk_…", text: $token).textFieldStyle(.roundedBorder)
            }
            HStack {
                Button {
                    connecting = true
                    Task {
                        await store.connect(server: server, token: token)
                        connecting = false
                    }
                } label: {
                    Text(connecting ? "连接中…" : "连接").frame(minWidth: 80)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(connecting || server.isEmpty || token.isEmpty)
                if let url = VikunjaClient.normalize(server: server) {
                    Button("创建 Token…") { NSWorkspace.shared.open(url.appending(path: "settings/api-tokens")) }
                        .buttonStyle(.glass)
                }
            }
            if let e = store.error {
                Text(e).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("在网页版「设置 → API tokens」新建一个 token，至少勾选：").font(.callout)
                ForEach(Self.scopes, id: \.self) { Text("• \($0)").font(.caption.monospaced()) }
                Text("Token 保存在钥匙串（com.nimrc.vikunja-bar）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    static let scopes = [
        "projects: read_all, read_one",
        "projects_views: read_all",
        "projects_views_tasks: read_all",
        "tasks: read_all, read_one, update, create",
        "tasks_comments: read_all",
        "other: user",
    ]
}
