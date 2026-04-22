import SwiftUI

final class PopoverViewModel: ObservableObject {
    @Published var providers: [String] = []
    @Published var projects: [ProjectInfo] = []
    @Published var terminals: [String] = []
    @Published var sessions: [SessionInfo] = []

    @Published var selectedProvider: String = ""
    @Published var selectedProject: String = ""
    @Published var selectedTerminal: String = ""

    var onLaunch: ((String, String, String) -> Void)?
    var onSwitch: ((SessionInfo, String) -> Void)?
    var onQuit: (() -> Void)?

    func refresh(providerService: ProviderService, projectManager: ProjectManager, sessionManager: SessionManager) {
        providers = providerService.availableProviders()
        projects = projectManager.recentProjects()
        terminals = TerminalRegistry.shared.adapters.map { $0.name }
        sessions = sessionManager.sessions

        if selectedProvider.isEmpty || !providers.contains(selectedProvider) {
            selectedProvider = providerService.currentProvider() ?? providers.first ?? ""
        }
        if selectedProject.isEmpty || !projects.contains(where: { $0.path == selectedProject }) {
            selectedProject = projects.first?.path ?? ""
        }
        if selectedTerminal.isEmpty || !terminals.contains(selectedTerminal) {
            selectedTerminal = terminals.first ?? ""
        }
    }
}

struct PopoverContentView: View {
    @ObservedObject var vm: PopoverViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            launcherSection
            if !vm.sessions.isEmpty {
                Divider().padding(.vertical, 8)
                sessionsSection
            }
            Divider().padding(.vertical, 8)
            quitSection
        }
        .padding(16)
        .frame(width: 320, alignment: .topLeading)
        .fixedSize()
    }

    private var launcherSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("启动新会话")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            HStack {
                Text("线路").frame(width: 36, alignment: .trailing)
                    .font(.system(size: 13))
                Picker("", selection: $vm.selectedProvider) {
                    ForEach(vm.providers, id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("项目").frame(width: 36, alignment: .trailing)
                    .font(.system(size: 13))
                Picker("", selection: $vm.selectedProject) {
                    ForEach(vm.projects, id: \.path) { proj in
                        Text(proj.name).tag(proj.path)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("终端").frame(width: 36, alignment: .trailing)
                    .font(.system(size: 13))
                Picker("", selection: $vm.selectedTerminal) {
                    ForEach(vm.terminals, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("启动") {
                    vm.onLaunch?(vm.selectedProvider, vm.selectedProject, vm.selectedTerminal)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("正在运行")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            ForEach(vm.sessions, id: \.pid) { session in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(badgeEmoji(session.provider))
                        Text("\(session.provider) · \(session.projectName)")
                            .font(.system(size: 13))
                    }

                    HStack(spacing: 8) {
                        ForEach(vm.providers.filter { $0 != session.provider }, id: \.self) { target in
                            Button("切到 \(target)") {
                                vm.onSwitch?(session, target)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.leading, 20)
                }
            }
        }
    }

    private var quitSection: some View {
        HStack {
            Spacer()
            Button("退出 ccpod") {
                vm.onQuit?()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.system(size: 12))
            Spacer()
        }
    }

    private func badgeEmoji(_ provider: String) -> String {
        switch provider {
        case "official": return "🟢"
        case "easyclaude": return "🔵"
        default: return "⚪"
        }
    }
}
