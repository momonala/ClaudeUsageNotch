import Foundation

/// OpenAI endpoints.
///
/// We only need to verify a key is live, so we use `GET /v1/models` — the one
/// endpoint that authenticates with a standard `sk-...` key without producing
/// any billable usage. (The old `/v1/dashboard/billing/*` endpoints required a
/// browser `sess-...` token and have been deprecated; see `OpenAIProvider`.)
enum OpenAIEndpoint {
    static let modelsURL = URL(string: "https://api.openai.com/v1/models")!

    static func headers(apiKey: String) -> [String: String] {
        [
            "Authorization": "Bearer \(apiKey)",
            "Accept":        "application/json"
        ]
    }
}
