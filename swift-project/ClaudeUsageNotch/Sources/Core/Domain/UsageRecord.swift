import Foundation

struct UsageRecord {
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let model: String
    let requestId: String?
    let project: String
    let attributionSkill: String?
    let sessionId: String?
    let webSearches: Int
    let webFetches: Int

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens }

    var estimatedCostUSD: Double {
        ModelPricing.cost(
            input: inputTokens, output: outputTokens,
            cacheCreate: cacheCreationTokens, cacheRead: cacheReadTokens,
            model: model
        )
    }
}

enum ModelPricing {
    static func cost(input: Int, output: Int, cacheCreate: Int, cacheRead: Int, model: String) -> Double {
        let (inputRate, outputRate) = rates(for: model)
        let inputCost      = Double(input + cacheCreate) * inputRate  / 1_000_000
        let outputCost     = Double(output)              * outputRate / 1_000_000
        let cacheReadCost  = Double(cacheRead)           * inputRate  * 0.1 / 1_000_000
        return inputCost + outputCost + cacheReadCost
    }

    private static func rates(for model: String) -> (input: Double, output: Double) {
        if model.contains("opus")  { return (15.0, 75.0) }
        if model.contains("haiku") { return (0.80,  4.0) }
        return (3.0, 15.0)  // sonnet default
    }
}
