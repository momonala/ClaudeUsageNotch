import SwiftUI
import Charts

// MARK: - Time-series bucket (existing)

struct TimeBucket: Identifiable {
    let id: Date
    let tokens: Int
    let quotaPct: Double
}

// MARK: - Lookback period

enum LookbackPeriod: String, CaseIterable {
    case week    = "7D"
    case month   = "30D"
    case allTime = "All"

    var sinceDate: Date {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch self {
        case .week:    return cal.date(byAdding: .day, value: -6,  to: today)!
        case .month:   return cal.date(byAdding: .day, value: -29, to: today)!
        case .allTime: return Date(timeIntervalSince1970: 0)
        }
    }
}

// MARK: - Chart cache

private struct ChartCache {
    var sessionBuckets: [TimeBucket]   = []
    var weeklyBuckets:  [TimeBucket]   = []
    var analytics:      AnalyticsData  = .empty
    var cachedAt:       Date           = .distantPast
    var period:         LookbackPeriod = .week

    func isValid(for period: LookbackPeriod) -> Bool {
        self.period == period && Date().timeIntervalSince(cachedAt) < 60
    }

    mutating func store(session: [TimeBucket], weekly: [TimeBucket], analytics: AnalyticsData, period: LookbackPeriod) {
        sessionBuckets = session
        weeklyBuckets  = weekly
        self.analytics = analytics
        self.period    = period
        cachedAt       = Date()
    }
}

private var chartCache = ChartCache()

// MARK: - Layout constants

private enum AnalyticsLayout {
    static let leftWidth:  CGFloat = 550
    static let rightWidth: CGFloat = 495
    static let colGap:     CGFloat = 1   // vertical divider width
    static let colSpacing: CGFloat = 10  // gap between col edge and divider
}

// MARK: - Root view

struct UsageChartView: View {
    @ObservedObject var appState: AppState
    let appSettings: AppSettings

    @State private var sessionBuckets:  [TimeBucket]  = []
    @State private var weeklyBuckets:   [TimeBucket]  = []
    @State private var analytics:       AnalyticsData = .empty
    @State private var showQuota      = true
    @State private var lookback:        LookbackPeriod = .week
    @State private var isLoading      = true
    @State private var lastUpdatedAt:  Date?
    @State private var fetchError:     String?
    @State private var now:            Date = Date()

    private var sessionWindow: UsageWindow? { appState.activeSnapshot?.sessionWindow }
    private var weeklyWindow:  UsageWindow? { appState.activeSnapshot?.weeklyWindow }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isLoading {
                    HStack { Spacer(); ProgressView().scaleEffect(0.7); Spacer() }
                        .frame(maxHeight: .infinity)
                } else if let err = fetchError {
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        leftColumn
                            .frame(width: AnalyticsLayout.leftWidth)

                        Rectangle()
                            .fill(Theme.stroke)
                            .frame(width: AnalyticsLayout.colGap)
                            .padding(.horizontal, AnalyticsLayout.colSpacing)

                        rightColumn
                            .frame(width: AnalyticsLayout.rightWidth)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if let ts = lastUpdatedAt {
                Rectangle().fill(Theme.stroke).frame(height: 0.5).padding(.top, 6)
                HStack {
                    Spacer()
                    Text("updated \(ts.formatted(.dateTime.hour().minute().second()))  ·  \(relativeTime(from: ts, to: now))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.top, 4)
                .padding(.bottom, 2)
            }
        }
        .padding(.top, 6)
        .task { await loadData() }
        .onChange(of: lookback) {
            Task { await loadData() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
    }

    private func relativeTime(from date: Date, to reference: Date) -> String {
        let seconds = Int(reference.timeIntervalSince(date))
        switch seconds {
        case ..<60:       return "\(max(0, seconds))s ago"
        case 60..<3600:   return "\(seconds / 60)m ago"
        default:          return "\(seconds / 3600)h ago"
        }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggleRow

            divider.padding(.top, 9)
            sectionHeader("SESSION · 5H",
                          pct: sessionWindow?.percentUsed ?? 0,
                          status: sessionWindow?.status ?? .unknown)
                .padding(.top, 8)
            sessionChart
                .frame(height: 108)
                .padding(.top, 5)

            divider.padding(.top, 10)
            sectionHeader("WEEKLY · 7D",
                          pct: weeklyWindow?.percentUsed ?? 0,
                          status: weeklyWindow?.status ?? .unknown)
                .padding(.top, 8)
            weeklyChart
                .frame(height: 108)
                .padding(.top, 5)

            divider.padding(.top, 10)
            analyticsHeader("SPEND PER DAY · \(lookback.rawValue)").padding(.top, 8)
            costChart
                .frame(height: 88)
                .padding(.top, 5)

            divider.padding(.top, 10)
            analyticsHeader("SESSIONS PER DAY · \(lookback.rawValue)").padding(.top, 8)
            sessionCountChart
                .frame(height: 88)
                .padding(.top, 5)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            CostSection(data: analytics)
            divider.padding(.top, 10)
            TokenBreakdownSection(data: analytics, periodLabel: lookback.rawValue).padding(.top, 10)
            divider.padding(.top, 10)
            CacheSection(data: analytics, periodLabel: lookback.rawValue).padding(.top, 10)
            divider.padding(.top, 10)
            ModelMixSection(data: analytics, periodLabel: lookback.rawValue).padding(.top, 10)
            divider.padding(.top, 10)
            RankedBreakdownSection(title: "PROJECTS · \(lookback.rawValue)", items: analytics.projectBreakdown).padding(.top, 10)
            divider.padding(.top, 10)
            RankedBreakdownSection(title: "SKILLS · \(lookback.rawValue)",   items: analytics.skillBreakdown).padding(.top, 10)
        }
    }

    // MARK: - Layout primitives

    private var toggleRow: some View {
        HStack {
            Picker("", selection: $lookback) {
                ForEach(LookbackPeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()

            Spacer(minLength: 0)

            Picker("", selection: $showQuota) {
                Text("Tokens").tag(false)
                Text("% Quota").tag(true)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .font(.system(size: 10, design: .rounded))
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(height: 0.5)
    }

    @ViewBuilder
    private func sectionHeader(_ label: String, pct: Double, status: UsageStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(Theme.sectionLabelFont)
                .kerning(Theme.sectionLabelKerning)
                .foregroundColor(Theme.textSecondary)
            Spacer()
            if pct > 0 {
                Text("\(Int((pct * 100).rounded()))%")
                    .font(Theme.numericFont)
                    .foregroundColor(status.color)
            }
        }
    }

    // MARK: - Left charts

    private var yLabel: String { showQuota ? "% Quota" : "Tokens" }
    private func yValue(_ b: TimeBucket) -> Double { showQuota ? b.quotaPct : Double(b.tokens) }

    private var sessionChart: some View {
        Chart(sessionBuckets) { b in
            AreaMark(x: .value("Time", b.id), y: .value(yLabel, yValue(b)))
                .foregroundStyle(LinearGradient(
                    colors: [Theme.accentWarm.opacity(0.55), Theme.accentWarm.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Time", b.id), y: .value(yLabel, yValue(b)))
                .foregroundStyle(Theme.accentWarm)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis { hourAxis }
        .chartYAxis { yAxis }
        .chartPlotStyle { $0.background(Color.clear) }
    }

    private var weeklyChart: some View {
        Chart(weeklyBuckets) { b in
            AreaMark(x: .value("Day", b.id), y: .value(yLabel, yValue(b)))
                .foregroundStyle(LinearGradient(
                    colors: [Theme.accentWarm.opacity(0.55), Theme.accentWarm.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Day", b.id), y: .value(yLabel, yValue(b)))
                .foregroundStyle(Theme.accentWarm)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis { dayAxis }
        .chartYAxis { yAxis }
        .chartPlotStyle { $0.background(Color.clear) }
    }

    private var costChart: some View {
        dailyBarChart(analytics.dailyCost) { String(format: "$%.2f", $0) }
    }

    private var sessionCountChart: some View {
        dailyBarChart(analytics.dailySessions) { "\(Int($0))" }
    }

    private func dailyBarChart(_ data: [DailyValue], yLabel: @escaping (Double) -> String) -> some View {
        Chart(data) { d in
            BarMark(x: .value("Day", d.date, unit: .day),
                    y: .value("", d.value))
                .foregroundStyle(Theme.accentWarm.opacity(0.7))
                .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel(format: .dateTime.weekday(.narrow))
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Theme.stroke)
                if let n = v.as(Double.self) {
                    AxisValueLabel(yLabel(n))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
    }

    @AxisContentBuilder
    private var hourAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour)) { _ in
            AxisGridLine().foregroundStyle(Theme.stroke)
            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)))
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @AxisContentBuilder
    private var dayAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day)) { _ in
            AxisGridLine().foregroundStyle(Theme.stroke)
            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @AxisContentBuilder
    private var yAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(Theme.stroke)
            if let v = value.as(Double.self) {
                AxisValueLabel(showQuota
                    ? String(format: "%.1f%%", v)
                    : "\(Int(v.rounded()))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Data loading

    private func loadData() async {
        if chartCache.isValid(for: lookback) {
            sessionBuckets = chartCache.sessionBuckets
            weeklyBuckets  = chartCache.weeklyBuckets
            analytics      = chartCache.analytics
            lastUpdatedAt  = chartCache.cachedAt
            isLoading      = false
            return
        }

        isLoading = true
        let now          = Date()
        let sessionSince = now.addingTimeInterval(-5 * 3600)
        let weeklySince  = LookbackPeriod.week.sinceDate
        let monthlySince = lookback.sinceDate

        let base = appSettings.apiBaseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, let baseURL = URL(string: base) else {
            NSLog("[ClaudeUsageNotch] chart: no apiBaseURL set; remote disabled")
            isLoading = false
            return
        }

        do {
            let remote = try await RemoteHistoryReader.fetchAnalytics(
                sessionSince: sessionSince, weeklySince: weeklySince, monthlySince: monthlySince,
                baseURL: baseURL
            )
            NSLog("[ClaudeUsageNotch] chart: loaded analytics from remote \(baseURL.absoluteString)")

            let sessionPct = sessionWindow?.percentUsed ?? 0
            let weeklyPct  = weeklyWindow?.percentUsed  ?? 0

            let (session, weekly, newAnalytics) = await Task.detached(priority: .utility) {
                let session = toTimeBuckets(remote.sessionBuckets, currentPct: sessionPct)
                let weekly  = toTimeBuckets(remote.weeklyBuckets,  currentPct: weeklyPct)
                return (session, weekly, remote.toAnalyticsData())
            }.value

            chartCache.store(session: session, weekly: weekly, analytics: newAnalytics, period: lookback)
            sessionBuckets  = session
            weeklyBuckets   = weekly
            analytics       = newAnalytics
            lastUpdatedAt   = Date()
            fetchError      = nil
        } catch {
            NSLog("[ClaudeUsageNotch] chart: remote analytics failed: \(error.localizedDescription)")
            fetchError = error.localizedDescription
        }

        isLoading = false
    }

}

// Free function — callable from Task.detached without actor isolation.
// Applies cumulative quotaPct scaling on top of the server-aggregated bucket deltas.
private func toTimeBuckets(_ buckets: [RemoteAnalytics.BucketDTO], currentPct: Double) -> [TimeBucket] {
    let totalTokens = buckets.reduce(0) { $0 + $1.tokens }
    var cumulative  = 0
    return buckets.map { b in
        cumulative += b.tokens
        let pct = totalTokens > 0
            ? Double(cumulative) / Double(totalTokens) * currentPct * 100.0
            : 0.0
        return TimeBucket(id: b.timestamp, tokens: b.tokens, quotaPct: pct)
    }
}

// MARK: - Reusable primitives

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

private func analyticsHeader(_ label: String) -> some View {
    Text(label)
        .font(Theme.sectionLabelFont)
        .kerning(Theme.sectionLabelKerning)
        .foregroundColor(Theme.textSecondary)
}

// MARK: - Cost section

private struct CostSection: View {
    let data: AnalyticsData

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            Spacer(minLength: 0)
            statPill(label: "Session", value: formatCost(data.sessionCost))
            statPill(label: "Today", value: formatCost(data.todayCost))
            statPill(label: "Weekly", value: formatCost(data.weeklyCost))
            statPill(label: "Month", value: formatCost(data.monthCost))
            statPill(label: "Lifetime", value: formatCost(data.lifetimeCost))
            statPill(label: "Avg / day", value: formatCost(data.averageDailyCost))
        }
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(Theme.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
        }
    }

    private func formatCost(_ v: Double) -> String {
        v < 0.01 ? "<$0.01" : String(format: "$%.2f", v)
    }
}

// MARK: - Token breakdown section

private struct TokenBreakdownSection: View {
    let data: AnalyticsData
    let periodLabel: String

    private var t: TokenTypeBreakdown { data.tokenTypes }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            analyticsHeader("TOKENS · \(periodLabel)")
            RankedRow(label: "Input",       value: fmt(t.inputTokens),       fraction: t.inputFraction,       color: Theme.accentWarm)
            RankedRow(label: "Output",      value: fmt(t.outputTokens),      fraction: t.outputFraction,      color: Color(nsColor: .systemPurple))
            RankedRow(label: "Cache write", value: fmt(t.cacheCreateTokens), fraction: t.cacheCreateFraction, color: Color(nsColor: .systemOrange))
            RankedRow(label: "Cache read",  value: fmt(t.cacheReadTokens),   fraction: t.cacheReadFraction,   color: Theme.statusHealthy)
        }
    }

    private func fmt(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000)
            : n >= 1_000 ? String(format: "%.0fK", Double(n) / 1_000)
            : "\(n)"
    }
}

// MARK: - Cache efficiency section

private struct CacheSection: View {
    let data: AnalyticsData
    let periodLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            analyticsHeader("CACHE · \(periodLabel)")
            HStack(alignment: .top, spacing: 6) {
                Spacer().frame(width: 110)
                FractionBar(fraction: data.cacheHitRate, color: Theme.statusHealthy, height: 5)
                    .padding(.top, 3)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.0f%%", data.cacheHitRate * 100))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.statusHealthy)
                    if data.cacheSavingsUSD > 0.001 {
                        Text("~\(String(format: "$%.2f", data.cacheSavingsUSD)) saved")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

// MARK: - Model mix section

private struct ModelMixSection: View {
    let data: AnalyticsData
    let periodLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            analyticsHeader("MODELS · \(periodLabel)")
            if data.modelBreakdown.isEmpty {
                emptyLabel
            } else {
                ForEach(data.modelBreakdown) { item in
                    RankedRow(
                        label:    modelLabel(item.label),
                        value:    String(format: "%.0f%%", item.fraction * 100),
                        fraction: item.fraction,
                        color:    modelColor(item.label)
                    )
                }
            }
        }
    }

    private var emptyLabel: some View {
        Text("No data").font(Theme.captionFont).foregroundColor(Theme.textSecondary)
    }

    private func modelLabel(_ m: String) -> String {
        if m.contains("opus")   { return "Opus" }
        if m.contains("haiku")  { return "Haiku" }
        if m.contains("sonnet") { return "Sonnet" }
        return m
    }

    private func modelColor(_ m: String) -> Color {
        if m.contains("opus")  { return Color(nsColor: .systemPurple) }
        if m.contains("haiku") { return Theme.statusHealthy }
        return Theme.accentWarm
    }
}

// MARK: - Ranked breakdown section (projects, skills, etc.)

private struct RankedBreakdownSection: View {
    let title: String
    let items: [RankedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            analyticsHeader(title)
            if items.isEmpty {
                Text("No data").font(Theme.captionFont).foregroundColor(Theme.textSecondary)
            } else {
                ForEach(items) { item in
                    RankedRow(
                        label:    item.label,
                        value:    String(format: "%.0f%%", item.fraction * 100),
                        fraction: item.fraction
                    )
                }
            }
        }
    }
}

