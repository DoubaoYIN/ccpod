import SwiftUI

struct AddProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplate: ProviderTemplate?
    @State private var fieldValues: [String: String] = [:]
    @State private var customName: String = ""
    @State private var errorMessage: String?
    var onComplete: (() -> Void)?

    private let templates = ProviderTemplate.builtIn
    private let providersDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/providers", isDirectory: true)
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let tpl = selectedTemplate {
                formSection(tpl)
            } else {
                templateList
            }
        }
        .frame(width: 340, height: 380)
    }

    private var header: some View {
        HStack {
            if selectedTemplate != nil {
                Button(action: { selectedTemplate = nil; fieldValues = [:]; errorMessage = nil }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
            }
            Text(selectedTemplate?.displayName ?? "添加线路")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var templateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ProviderTemplate.Category.allCases, id: \.rawValue) { cat in
                    let items = templates.filter { $0.category == cat }
                    if !items.isEmpty {
                        Text(cat.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        ForEach(items, id: \.id) { tpl in
                            Button(action: {
                                selectedTemplate = tpl
                                customName = tpl.id == "relay" ? "" : tpl.id
                                fieldValues = [:]
                                errorMessage = nil
                            }) {
                                HStack {
                                    Text(badgeEmoji(tpl.id))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tpl.displayName).font(.system(size: 13))
                                        Text(tpl.notes)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func formSection(_ tpl: ProviderTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("名称").frame(width: 50, alignment: .trailing).font(.system(size: 12))
                        TextField("provider 名称", text: $customName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                    ForEach(tpl.envKeys, id: \.envName) { field in
                        HStack {
                            Text(field.label).frame(width: 50, alignment: .trailing).font(.system(size: 12))
                            TextField(field.placeholder, text: binding(for: field.envName))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }
                    }
                    if let err = errorMessage {
                        Text(err).font(.system(size: 11)).foregroundColor(.red)
                    }
                }
                .padding(12)
            }
            Spacer()
            HStack {
                Spacer()
                Button("添加") { save(tpl) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            .padding(.bottom, 12)
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { fieldValues[key, default: ""] },
            set: { fieldValues[key] = $0 }
        )
    }

    private func save(_ tpl: ProviderTemplate) {
        let name = customName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let filePath = providersDir.appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: filePath.path) {
            errorMessage = "线路 \"\(name)\" 已存在"
            return
        }

        let json = tpl.generateJSON(values: fieldValues)
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: providersDir, withIntermediateDirectories: true)
            try data.write(to: filePath)
            onComplete?()
            dismiss()
        } catch {
            errorMessage = "写入失败: \(error.localizedDescription)"
        }
    }

    private func badgeEmoji(_ id: String) -> String {
        switch id {
        case "minimax": return "🟠"
        case "glm": return "🟣"
        case "volcengine": return "🔴"
        case "aliyun": return "🟤"
        case "deepseek": return "🔷"
        case "kimi": return "🟡"
        case "relay": return "🔗"
        default: return "⚪"
        }
    }
}
