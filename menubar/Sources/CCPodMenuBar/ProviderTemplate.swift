import Foundation

struct ProviderTemplate {
    let id: String
    let displayName: String
    let category: Category
    let baseURL: String?
    let envKeys: [EnvField]
    let notes: String

    enum Category: String, CaseIterable {
        case domestic = "国内厂商"
        case relay = "中转站"
    }

    struct EnvField {
        let envName: String
        let label: String
        let placeholder: String
        let isURL: Bool

        init(envName: String, label: String, placeholder: String, isURL: Bool = false) {
            self.envName = envName
            self.label = label
            self.placeholder = placeholder
            self.isURL = isURL
        }
    }

    func generateJSON(values: [String: String]) -> [String: Any] {
        var env: [String: String] = [:]
        if let url = baseURL {
            env["ANTHROPIC_BASE_URL"] = url
        }
        for field in envKeys {
            let val = values[field.envName] ?? ""
            if field.isURL {
                env["ANTHROPIC_BASE_URL"] = val
            } else {
                env["ANTHROPIC_AUTH_TOKEN"] = val
            }
        }
        return ["env": env]
    }

    static let builtIn: [ProviderTemplate] = [
        ProviderTemplate(
            id: "minimax",
            displayName: "MiniMax",
            category: .domestic,
            baseURL: "https://api.minimax.io/anthropic",
            envKeys: [
                EnvField(envName: "api_key", label: "API Key", placeholder: "eyJhb...")
            ],
            notes: "原生 Anthropic 端点，无需代理"
        ),
        ProviderTemplate(
            id: "glm",
            displayName: "GLM (Z.AI)",
            category: .domestic,
            baseURL: "https://api.z.ai/api/anthropic",
            envKeys: [
                EnvField(envName: "api_key", label: "API Key", placeholder: "xxx.xxx")
            ],
            notes: "原生 Anthropic 端点，有免费模型"
        ),
        ProviderTemplate(
            id: "volcengine",
            displayName: "火山引擎",
            category: .domestic,
            baseURL: "https://ark.ap-southeast.bytepluses.com/api/coding",
            envKeys: [
                EnvField(envName: "api_key", label: "API Key", placeholder: "ark-xxx")
            ],
            notes: "Coding Plan 专用端点，多模型聚合"
        ),
        ProviderTemplate(
            id: "aliyun",
            displayName: "阿里云百炼",
            category: .domestic,
            baseURL: "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic",
            envKeys: [
                EnvField(envName: "api_key", label: "API Key", placeholder: "sk-sp-xxx")
            ],
            notes: "Coding Plan 专用，Key 须 sk-sp- 前缀"
        ),
        ProviderTemplate(
            id: "deepseek",
            displayName: "DeepSeek",
            category: .domestic,
            baseURL: "https://api.deepseek.com/v1",
            envKeys: [
                EnvField(envName: "api_key", label: "API Key", placeholder: "sk-xxx")
            ],
            notes: "OpenAI 兼容，需 LiteLLM 代理转 Anthropic"
        ),
        ProviderTemplate(
            id: "kimi",
            displayName: "Kimi",
            category: .domestic,
            baseURL: "https://api.moonshot.cn/v1",
            envKeys: [
                EnvField(envName: "api_key", label: "API Key", placeholder: "sk-xxx")
            ],
            notes: "OpenAI 兼容，需 LiteLLM 代理转 Anthropic"
        ),
        ProviderTemplate(
            id: "relay",
            displayName: "中转站",
            category: .relay,
            baseURL: nil,
            envKeys: [
                EnvField(envName: "base_url", label: "Base URL", placeholder: "https://api.example.com", isURL: true),
                EnvField(envName: "api_key", label: "API Key", placeholder: "sk-xxx")
            ],
            notes: "通用中转站，填入 URL 和 Key 即可"
        ),
    ]
}