import SwiftUI

func analyticsHeader(_ label: String) -> some View {
    Text(label)
        .font(Theme.sectionLabelFont)
        .kerning(Theme.sectionLabelKerning)
        .foregroundColor(Theme.textSecondary)
}

// MARK: - Row primitives

private struct FractionBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: max(2, geo.size.width * CGFloat(fraction)))
            }
        }
        .frame(height: height)
    }
}

private struct RankedRow: View {
    let label: String
    let value: String
    let fraction: Double
    var color: Color = Theme.accentWarm

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(Theme.textLabel)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
            FractionBar(fraction: fraction, color: color, height: 5)
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

private struct EmptyBreakdownLabel: View {
    var body: some View {
        Text("No data").font(Theme.captionFont).foregroundColor(Theme.textSecondary)
    }
}

private func percentLabel(_ fraction: Double) -> String {
    String(format: "%.0f%%", fraction * 100)
}

// MARK: - Cost pills

struct CostSection: View {
    let data: AnalyticsData

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            statPill("Session",   data.sessionCost)
            statPill("Today",     data.todayCost)
            statPill("Week",      data.weeklyCost)
            statPill("Month",     data.monthCost)
            statPill("Lifetime",  data.lifetimeCost)
            statPill("Avg / day", data.averageDailyCost)
        }
    }

    private func statPill(_ label: String, _ cost: Double) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(Theme.textSecondary)
            Text(cost < 0.01 ? "<$0.01" : String(format: "$%.2f", cost))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
        }
    }
}

// MARK: - Token types

struct TokenBreakdownSection: View {
    let data: AnalyticsData
    let periodLabel: String

    var body: some View {
        let t = data.tokenTypes
        VStack(alignment: .leading, spacing: 7) {
            analyticsHeader("TOKENS · \(periodLabel)")
            RankedRow(label: "Input",       value: abbreviated(t.inputTokens),       fraction: t.inputFraction,       color: Theme.accentWarm)
            RankedRow(label: "Output",      value: abbreviated(t.outputTokens),      fraction: t.outputFraction,      color: Color(nsColor: .systemPurple))
            RankedRow(label: "Cache write", value: abbreviated(t.cacheCreateTokens), fraction: t.cacheCreateFraction, color: Color(nsColor: .systemOrange))
            RankedRow(label: "Cache read",  value: abbreviated(t.cacheReadTokens),   fraction: t.cacheReadFraction,   color: Theme.statusHealthy)
        }
    }

    private func abbreviated(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000     { return String(format: "%.0fK", Double(count) / 1_000) }
        return "\(count)"
    }
}

// MARK: - Cache efficiency

struct CacheSection: View {
    let data: AnalyticsData
    let periodLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            analyticsHeader("CACHE · \(periodLabel)")
            HStack(alignment: .top, spacing: 6) {
                Spacer().frame(width: 110)
                FractionBar(fraction: data.cacheHitRate, color: Theme.statusHealthy, height: 5)
                    .padding(.top, 3)
                HStack(alignment: .center, spacing: 4) {
                    Text(percentLabel(data.cacheHitRate))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.statusHealthy)
                    if data.cacheSavingsUSD > 0.5 {
                        Text("$\(Int(data.cacheSavingsUSD.rounded()))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Model mix

struct ModelMixSection: View {
    let data: AnalyticsData
    let periodLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            analyticsHeader("MODELS BY TOKEN · \(periodLabel)")
            if data.modelBreakdown.isEmpty {
                EmptyBreakdownLabel()
            } else {
                ForEach(data.modelBreakdown) { item in
                    RankedRow(
                        label:    Self.displayName(item.label),
                        value:    percentLabel(item.fraction),
                        fraction: item.fraction,
                        color:    Self.color(item.label)
                    )
                }
            }
        }
    }

    private static func displayName(_ model: String) -> String {
        if model.contains("opus")   { return "Opus" }
        if model.contains("haiku")  { return "Haiku" }
        if model.contains("sonnet") { return "Sonnet" }
        return model
    }

    private static func color(_ model: String) -> Color {
        if model.contains("opus")  { return Color(nsColor: .systemPurple) }
        if model.contains("haiku") { return Theme.statusHealthy }
        return Theme.accentWarm
    }
}

// MARK: - Ranked breakdowns (projects, skills)

struct RankedBreakdownSection: View {
    let title: String
    let items: [RankedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            analyticsHeader(title)
            if items.isEmpty {
                EmptyBreakdownLabel()
            } else {
                ForEach(items) { item in
                    RankedRow(label: item.label,
                              value: percentLabel(item.fraction),
                              fraction: item.fraction)
                }
            }
        }
    }
}
