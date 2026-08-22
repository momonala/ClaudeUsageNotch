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
    case day     = "1D"
    case week    = "7D"
    case month   = "30D"
    case allTime = "All"

    var sinceDate: Date {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch self {
        case .day:     return cal.date(byAdding: .hour, value: -24, to: Date())!
        case .week:    return cal.date(byAdding: .day,  value: -6,  to: today)!
        case .month:   return cal.date(byAdding: .day,  value: -29, to: today)!
        case .allTime: return Date(timeIntervalSince1970: 0)
        }
    }

    /// Rollup width for the spend/sessions-per-period charts: hourly for 1D,
    /// monthly for All, daily in between.
    var granularity: SeriesGranularity {
        switch self {
        case .day:          return .hour
        case .week, .month: return .day
        case .allTime:      return .month
        }
    }
}

enum SeriesGranularity: String {
    case hour, day, month

    var unitLabel: String {
        switch self {
        case .hour:  return "HOUR"
        case .day:   return "DAY"
        case .month: return "MONTH"
        }
    }

    var axisUnit: Calendar.Component {
        switch self {
        case .hour:  return .hour
        case .day:   return .day
        case .month: return .month
        }
    }
}

// MARK: - Chart cache

private struct ChartCache {
    var sessionBuckets:    [TimeBucket]   = []
    var weeklyBuckets:     [TimeBucket]   = []
    var creditBuckets:     [TimeBucket]   = []
    var analytics:         AnalyticsData  = .empty
    var sessionResetTimes: [Date]         = []
    var weeklyResetTimes:  [Date]         = []
    var creditResetTimes:  [Date]         = []
    var sessionNextReset:  Date?
    var weeklyNextReset:   Date?
    var creditNextReset:   Date?
    var cachedAt:          Date           = .distantPast
    var period:            LookbackPeriod = .month

    func isValid(for period: LookbackPeriod) -> Bool {
        self.period == period && Date().timeIntervalSince(cachedAt) < 60
    }
}

/// Process-global so the 60s cache survives view teardown on hover-away/return.
/// `@MainActor` pins all access to the main actor (the only place it's touched).
@MainActor private var chartCache = ChartCache()

// MARK: - Layout constants

private enum AnalyticsLayout {
    static let leftWidth:  CGFloat = 690
    static let rightWidth: CGFloat = 355
    static let colGap:     CGFloat = 1   // vertical divider width
    static let colSpacing: CGFloat = 10  // gap between col edge and divider
}

// MARK: - Root view

struct UsageChartView: View {
    @ObservedObject var appState: AppState
    let appSettings: AppSettings

    @State private var sessionBuckets:  [TimeBucket]  = []
    @State private var weeklyBuckets:   [TimeBucket]  = []
    @State private var creditBuckets:   [TimeBucket]  = []
    @State private var analytics:       AnalyticsData = .empty
    @State private var showQuota      = true
    @State private var lookback:        LookbackPeriod = .month
    @State private var isLoading      = true
    @State private var lastUpdatedAt:  Date?
    @State private var fetchError:     String?
    @State private var now:            Date = Date()
    @State private var sessionResetTimes: [Date] = []
    @State private var weeklyResetTimes:  [Date] = []
    @State private var creditResetTimes:  [Date] = []
    @State private var sessionNextReset:  Date?
    @State private var weeklyNextReset:   Date?
    @State private var creditNextReset:   Date?

    private var sessionWindow: UsageWindow? { appState.snapshot?.sessionWindow }
    private var weeklyWindow:  UsageWindow? { appState.snapshot?.weeklyWindow }
    private var creditWindow:  UsageWindow? { appState.snapshot?.creditWindow }

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
                    VStack(alignment: .leading, spacing: 0) {
                        headerRow
                        divider.padding(.top, 9)
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
        .task(id: lookback) { await loadData() }
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("SESSION · 5H",
                              pct: sessionWindow?.effectivePercentUsed() ?? 0,
                              status: sessionWindow?.effectiveStatus() ?? .unknown,
                              nextReset: sessionWindow?.resetAtLabel())
                    .padding(.top, 8)
                sessionChart
                    .frame(height: 108)
                    .padding(.top, 5)

                divider.padding(.top, 10)
                sectionHeader("WEEK · 7D",
                              pct: weeklyWindow?.effectivePercentUsed() ?? 0,
                              status: weeklyWindow?.effectiveStatus() ?? .unknown,
                              nextReset: weeklyWindow?.resetAtLabel())
                    .padding(.top, 8)
                weeklyChart
                    .frame(height: 108)
                    .padding(.top, 5)

                if let creditWindow {
                    divider.padding(.top, 10)
                    sectionHeader("USAGE CREDITS · MONTH",
                                  pct: creditWindow.effectivePercentUsed(),
                                  status: creditWindow.effectiveStatus(),
                                  nextReset: creditWindow.resetAtLabel())
                        .padding(.top, 8)
                    creditChart
                        .frame(height: 108)
                        .padding(.top, 5)
                }

                divider.padding(.top, 10)
                analyticsHeader("SPEND PER \(lookback.granularity.unitLabel) · \(lookback.rawValue)").padding(.top, 8)
                costChart
                    .frame(height: 88)
                    .padding(.top, 5)

                divider.padding(.top, 10)
                analyticsHeader("USAGE BY HOUR · \(lookback.rawValue)").padding(.top, 8)
                hourlyActivityChart
                    .frame(height: 88)
                    .padding(.top, 5)

                divider.padding(.top, 10)
                analyticsHeader("SESSIONS PER \(lookback.granularity.unitLabel) · \(lookback.rawValue)").padding(.top, 8)
                sessionCountChart
                    .frame(height: 88)
                    .padding(.top, 5)
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Right column

    private var rightColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TokenBreakdownSection(data: analytics, periodLabel: lookback.rawValue)
                divider.padding(.top, 10)
                CacheSection(data: analytics, periodLabel: lookback.rawValue).padding(.top, 10)
                divider.padding(.top, 10)
                ModelMixSection(data: analytics, periodLabel: lookback.rawValue).padding(.top, 10)
                divider.padding(.top, 10)
                RankedBreakdownSection(title: "PROJECTS BY TOKEN · \(lookback.rawValue)", items: analytics.projectBreakdown).padding(.top, 10)
                divider.padding(.top, 10)
                RankedBreakdownSection(title: "SKILLS BY TOKEN · \(lookback.rawValue)",   items: analytics.skillBreakdown).padding(.top, 10)
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Layout primitives

    private var headerRow: some View {
        HStack(spacing: 0) {
            Picker("", selection: $lookback) {
                ForEach(LookbackPeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()

            Picker("", selection: $showQuota) {
                Text("Tokens").tag(false)
                Text("% Quota").tag(true)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .font(.system(size: 10, design: .rounded))
            .fixedSize()
            .padding(.leading, 8)

            Spacer(minLength: 0)

            CostSection(data: analytics)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(height: 0.5)
    }

    @ViewBuilder
    private func sectionHeader(_ label: String, pct: Double, status: UsageStatus, nextReset: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(Theme.sectionLabelFont)
                .kerning(Theme.sectionLabelKerning)
                .foregroundColor(Theme.textSecondary)
            if let nextReset {
                Text("· next \(nextReset)")
                    .font(Theme.sectionLabelFont)
                    .kerning(Theme.sectionLabelKerning)
                    .foregroundColor(Theme.textSecondary.opacity(0.6))
                    .padding(.leading, 4)
            }
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

    private func tokenChart(
        _ data: [TimeBucket],
        resetTimes: [Date] = [],
        nextReset: Date? = nil,
        expectedPct: Double? = nil,
        currentPct: Double = 0,
        @AxisContentBuilder xAxis: () -> some AxisContent
    ) -> some View {
        let allResets = resetTimes + (nextReset.map { [$0] } ?? [])
        // Match the usage cards: green when under expected pace, orange when over.
        let overPace = expectedPct.map { currentPct > $0 } ?? false
        let paceLineColor: Color = overPace ? Theme.statusWarning : Theme.statusHealthy
        return Chart {
            ForEach(data) { b in
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
            ForEach(allResets, id: \.self) { t in
                RuleMark(x: .value("Reset", t))
                    .foregroundStyle(Color.green.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            if showQuota, let pace = expectedPct {
                RuleMark(y: .value("Expected", pace))
                    .foregroundStyle(paceLineColor.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXAxis(content: xAxis)
        .chartYAxis { yAxis }
        .chartPlotStyle { $0.background(Color.clear) }
    }

    private var sessionChart: some View {
        tokenChart(sessionBuckets, resetTimes: sessionResetTimes, nextReset: sessionNextReset,
                   expectedPct: sessionWindow?.expectedProgress().map { $0 * 100 },
                   currentPct: (sessionWindow?.effectivePercentUsed() ?? 0) * 100) { hourAxis }
    }
    private var weeklyChart: some View {
        tokenChart(weeklyBuckets, resetTimes: weeklyResetTimes, nextReset: weeklyNextReset,
                   expectedPct: weeklyWindow?.expectedProgress().map { $0 * 100 },
                   currentPct: (weeklyWindow?.effectivePercentUsed() ?? 0) * 100) { dayAxis }
    }

    /// Unlike `sessionChart`/`weeklyChart`, always plots real % of the credit
    /// pool (a step function held between polls) — there's no per-request
    /// token analog to dual-render with the Tokens/% Quota toggle.
    private var creditChart: some View {
        let allResets = creditResetTimes + (creditNextReset.map { [$0] } ?? [])
        return Chart {
            ForEach(creditBuckets) { b in
                AreaMark(x: .value("Time", b.id), y: .value("% Used", b.quotaPct))
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.accentWarm.opacity(0.55), Theme.accentWarm.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.stepEnd)
                LineMark(x: .value("Time", b.id), y: .value("% Used", b.quotaPct))
                    .foregroundStyle(Theme.accentWarm)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.stepEnd)
            }
            ForEach(allResets, id: \.self) { t in
                RuleMark(x: .value("Reset", t))
                    .foregroundStyle(Color.green.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .chartXAxis { monthAxis }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.stroke)
                if let v = value.as(Double.self) {
                    AxisValueLabel(String(format: "%.0f%%", v))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
    }

    private var costChart: some View {
        seriesChart(analytics.dailyCost, yLabel: "Cost") { String(format: "$%.2f", $0) }
    }

    private var hourlyActivityChart: some View {
        Chart(analytics.hourlyActivity) { h in
            AreaMark(x: .value("Hour", h.hour), y: .value("Avg requests", h.value))
                .foregroundStyle(LinearGradient(
                    colors: [Theme.accentWarm.opacity(0.3), Theme.accentWarm.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Hour", h.hour), y: .value("Avg requests", h.value))
                .foregroundStyle(Theme.accentWarm.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
        }
        .chartXScale(domain: 0...23)
        .chartXAxis {
            AxisMarks(values: stride(from: 0, through: 23, by: 3).map { $0 }) { v in
                AxisGridLine().foregroundStyle(Theme.stroke)
                if let h = v.as(Int.self) {
                    AxisValueLabel(String(format: "%02d", h))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Theme.stroke)
                if let n = v.as(Double.self) {
                    AxisValueLabel(n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
    }

    private var sessionCountChart: some View {
        seriesChart(analytics.dailySessions, yLabel: "Sessions") { $0 == $0.rounded() ? "\(Int($0))" : nil }
    }

    private func seriesChart(_ data: [DailyValue], yLabel: String, formatter: @escaping (Double) -> String?) -> some View {
        let unit = lookback.granularity.axisUnit
        return Chart(data) { d in
            AreaMark(x: .value("Time", d.date, unit: unit), y: .value(yLabel, d.value))
                .foregroundStyle(LinearGradient(
                    colors: [Theme.accentWarm.opacity(0.55), Theme.accentWarm.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Time", d.date, unit: unit), y: .value(yLabel, d.value))
                .foregroundStyle(Theme.accentWarm)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis { seriesXAxis(lookback.granularity, lookback: lookback) }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Theme.stroke)
                if let n = v.as(Double.self), let label = formatter(n) {
                    AxisValueLabel(label)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
    }

    // Spend/sessions chart x-axis: hour-of-day for 1D, day for 7D (all ticks), day for 30D (every 3rd).
    @AxisContentBuilder
    private func seriesXAxis(_ granularity: SeriesGranularity, lookback: LookbackPeriod) -> some AxisContent {
        switch granularity {
        case .hour:
            AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                AxisGridLine().foregroundStyle(Theme.stroke)
                if let date = value.as(Date.self) {
                    let h = Calendar.current.component(.hour, from: date)
                    AxisValueLabel(String(format: "%02d", h))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        case .day:
            if lookback == .month {
                AxisMarks(values: .stride(by: .day, count: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    if let date = value.as(Date.self) {
                        let d = Calendar.current.component(.day, from: date)
                        AxisValueLabel("\(d)")
                            .font(.system(size: 8, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } else {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    if let date = value.as(Date.self) {
                        let d = Calendar.current.component(.day, from: date)
                        AxisValueLabel("\(d)")
                            .font(.system(size: 8, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        case .month:
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @AxisContentBuilder
    private var hourAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 3)) { value in
            AxisGridLine().foregroundStyle(Theme.stroke)
            if let date = value.as(Date.self) {
                let h = Calendar.current.component(.hour, from: date)
                AxisValueLabel(String(format: "%02d", h))
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
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
    private var monthAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: 5)) { _ in
            AxisGridLine().foregroundStyle(Theme.stroke)
            AxisValueLabel(format: .dateTime.day())
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
            sessionBuckets    = chartCache.sessionBuckets
            weeklyBuckets     = chartCache.weeklyBuckets
            creditBuckets     = chartCache.creditBuckets
            analytics         = chartCache.analytics
            sessionResetTimes = chartCache.sessionResetTimes
            weeklyResetTimes  = chartCache.weeklyResetTimes
            creditResetTimes  = chartCache.creditResetTimes
            sessionNextReset  = chartCache.sessionNextReset
            weeklyNextReset   = chartCache.weeklyNextReset
            creditNextReset   = chartCache.creditNextReset
            lastUpdatedAt     = chartCache.cachedAt
            isLoading         = false
            return
        }

        isLoading = true
        let now           = Date()
        // Fetch a full 24h so the 5h session window can be seen resetting several
        // times across the chart, even though the window itself is only 5h long.
        // This is for the session_buckets chart only — NOT the "Session" cost
        // pill, which needs the actual current session (see sessionCostSince).
        let sessionSince     = now.addingTimeInterval(-24 * 3600)
        // The real start of the current 5h session, so the "Session" cost pill
        // doesn't pick up spend from outside the actual rolling window (which
        // made it possible for "Session" to exceed "Today"). Falls back to the
        // 24h-back value before the first poll has populated sessionWindow.
        let sessionCostSince = sessionWindow?.resetAt.map { $0.addingTimeInterval(-(sessionWindow?.windowDuration ?? 5 * 3600)) } ?? sessionSince
        let weeklySince   = LookbackPeriod.week.sinceDate    // fixed 7d  → Weekly pill + chart
        let monthSince    = LookbackPeriod.month.sinceDate   // fixed 30d → Month pill
        let lookbackSince = lookback.sinceDate               // selector  → breakdowns + daily charts

        let base = appSettings.apiBaseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, let baseURL = URL(string: base) else {
            NSLog("[ClaudeUsageNotch] chart: no apiBaseURL set; remote disabled")
            isLoading = false
            return
        }

        do {
            let remote = try await RemoteHistoryReader.fetchAnalytics(
                sessionSince: sessionSince, sessionCostSince: sessionCostSince, weeklySince: weeklySince,
                monthSince: monthSince, lookbackSince: lookbackSince,
                granularity: lookback.granularity.rawValue,
                baseURL: baseURL
            )
            NSLog("[ClaudeUsageNotch] chart: loaded analytics from remote \(baseURL.absoluteString)")

            let sessionPct      = sessionWindow?.effectivePercentUsed() ?? 0
            let weeklyPct       = weeklyWindow?.effectivePercentUsed() ?? 0
            let sessionReset    = sessionWindow?.resetAt
            let sessionDuration = sessionWindow?.windowDuration
            let weeklyReset     = weeklyWindow?.resetAt
            let weeklyDuration  = weeklyWindow?.windowDuration

            let (session, weekly, credit, newAnalytics) = await Task.detached(priority: .utility) {
                let session = toTimeBuckets(remote.sessionBuckets, quotaHistory: remote.sessionQuotaHistory,
                                            currentPct: sessionPct,
                                            resetAt: sessionReset, windowDuration: sessionDuration)
                let weekly  = toTimeBuckets(remote.weeklyBuckets, quotaHistory: remote.weeklyQuotaHistory,
                                            currentPct: weeklyPct,
                                            resetAt: weeklyReset, windowDuration: weeklyDuration)
                let credit  = creditTimeBuckets(from: remote.creditQuotaHistory)
                return (session, weekly, credit, remote.toAnalyticsData())
            }.value

            sessionBuckets    = session
            weeklyBuckets     = weekly
            creditBuckets     = credit
            analytics         = newAnalytics
            sessionResetTimes = extractResetTimes(from: remote.sessionQuotaHistory, after: sessionSince, before: now)
            weeklyResetTimes  = extractResetTimes(from: remote.weeklyQuotaHistory,  after: weeklySince,  before: now)
            creditResetTimes  = extractResetTimes(from: remote.creditQuotaHistory,  after: monthSince,   before: now)
            sessionNextReset  = nextResetTime(from: remote.sessionQuotaHistory)
            weeklyNextReset   = nextResetTime(from: remote.weeklyQuotaHistory)
            creditNextReset   = nextResetTime(from: remote.creditQuotaHistory)
            lastUpdatedAt     = Date()
            fetchError        = nil

            chartCache.sessionBuckets    = session
            chartCache.weeklyBuckets     = weekly
            chartCache.creditBuckets     = credit
            chartCache.analytics         = newAnalytics
            chartCache.sessionResetTimes = sessionResetTimes
            chartCache.weeklyResetTimes  = weeklyResetTimes
            chartCache.creditResetTimes  = creditResetTimes
            chartCache.sessionNextReset  = sessionNextReset
            chartCache.weeklyNextReset   = weeklyNextReset
            chartCache.creditNextReset   = creditNextReset
            chartCache.period            = lookback
            chartCache.cachedAt          = Date()
        } catch {
            NSLog("[ClaudeUsageNotch] chart: remote analytics failed: \(error.localizedDescription)")
            fetchError = error.localizedDescription
        }

        isLoading = false
    }

}

// Most recent snapshot whose resets_at is still in the future — the next projected reset.
private func nextResetTime(from history: [RemoteAnalytics.QuotaPointDTO]) -> Date? {
    let now = Date()
    return history.reversed().compactMap(\.resetsAt).first { $0 > now }
}

// Unique past resets_at values within (after, before] — one per reset event that occurred.
private func extractResetTimes(
    from history: [RemoteAnalytics.QuotaPointDTO],
    after: Date,
    before: Date
) -> [Date] {
    let times = history.compactMap(\.resetsAt).filter { $0 > after && $0 <= before }
    return Array(Set(times)).sorted()
}

// Free function — callable from Task.detached without actor isolation.
//
// `quotaHistory` is real, provider-polled quota readings (from quota_snapshots on
// the sync server) — ground truth. When present, `quotaPct` is built by holding
// each reading's value forward to the next one (a step function), which needs no
// reset-awareness: a reset just shows up as a real drop in the polled data.
//
// `quotaHistory` is empty until a client has been pushing readings (see
// QuotaSyncService) for long enough to cover the requested span — e.g. right after
// this feature ships, or for lookback periods older than that. In that case we fall
// back to the previous *synthetic reconstruction*: it scales each bucket's
// cumulative token share by the current window percentage, so it approximates
// "% quota over time" — it is not real historical quota and shouldn't be read as
// such, but it's a reasonable placeholder where no real data exists yet.
//
// The synthetic path is reset-aware when `resetAt`/`windowDuration` are known: the
// rolling quota window resets every `windowDuration` ending at `resetAt`, so the
// cumulative is zeroed at each window boundary, dropping to 0 at a reset instead of
// climbing monotonically across the whole chart span. Tokens are converted to
// percent at a constant rate anchored so the *current* cycle ends at `currentPct`;
// older cycles use the same per-token rate (their true end percent is unknown).
// `buckets` are assumed chronological, as the running cumulative already requires.
private func toTimeBuckets(
    _ buckets: [RemoteAnalytics.BucketDTO],
    quotaHistory: [RemoteAnalytics.QuotaPointDTO],
    currentPct: Double,
    resetAt: Date?,
    windowDuration: TimeInterval?
) -> [TimeBucket] {
    if !quotaHistory.isEmpty {
        return realTimeBuckets(buckets, quotaHistory: quotaHistory)
    }

    guard let resetAt, let windowDuration, windowDuration > 0 else {
        return legacyTimeBuckets(buckets, currentPct: currentPct)
    }

    // Cycle 0 is the current window (the `windowDuration` ending at `resetAt`);
    // 1 is the previous window, etc. Index decreases as time moves forward.
    func cycleIndex(of timestamp: Date) -> Int {
        Int(floor(resetAt.timeIntervalSince(timestamp) / windowDuration))
    }

    // Percent points per token. The quota token-limit is ~constant across cycles,
    // so a single rate keeps relative magnitudes between cycles honest. Calibrate
    // it from the current cycle, the only one whose end percent we actually know.
    let cycleTotals = Dictionary(grouping: buckets, by: { cycleIndex(of: $0.timestamp) })
        .mapValues { $0.reduce(0) { $0 + $1.tokens } }
    let currentCycleTokens = cycleTotals[0] ?? 0
    let pctPerToken: Double
    if currentPct > 0, currentCycleTokens > 0 {
        // Anchored: the current cycle's cumulative ends exactly at currentPct.
        pctPerToken = (currentPct * 100.0) / Double(currentCycleTokens)
    } else {
        // The current cycle can't calibrate (just reset / no tokens yet). Rather
        // than collapse every past cycle to a flat 0, fall back to a relative
        // rate that maps the busiest cycle's cumulative to 100%, so the history
        // and its resets stay visible. Snaps back to the anchored scale as soon
        // as the current cycle records any usage.
        let maxCycleTokens = cycleTotals.values.max() ?? 0
        pctPerToken = maxCycleTokens > 0 ? 100.0 / Double(maxCycleTokens) : 0.0
    }

    var cumulative  = 0
    var activeCycle: Int? = nil
    return buckets.map { b in
        let cycle = cycleIndex(of: b.timestamp)
        if cycle != activeCycle {
            cumulative  = 0
            activeCycle = cycle
        }
        cumulative += b.tokens
        return TimeBucket(id: b.timestamp, tokens: b.tokens, quotaPct: Double(cumulative) * pctPerToken)
    }
}

// Ground-truth path: hold each real reading forward until the next one (a step
// function). Buckets before the first reading get 0 rather than a guess — honest
// about there being no real data yet for that stretch, rather than fabricating one.
// `quotaHistory` is assumed chronological (the server returns it ordered by timestamp).
private func realTimeBuckets(
    _ buckets: [RemoteAnalytics.BucketDTO],
    quotaHistory: [RemoteAnalytics.QuotaPointDTO]
) -> [TimeBucket] {
    var nextReading = 0
    var heldPct: Double = 0
    var heldResetAt: Date? = nil
    return buckets.map { b in
        while nextReading < quotaHistory.count, quotaHistory[nextReading].timestamp <= b.timestamp {
            heldPct = quotaHistory[nextReading].percentUsed * 100.0
            heldResetAt = quotaHistory[nextReading].resetsAt
            nextReading += 1
        }
        // The held reading's own reset time has passed by this bucket — its
        // window already rolled over, so show 0 instead of pinning to the
        // stale pre-reset value until a fresh post-reset poll lands.
        if let heldResetAt, b.timestamp >= heldResetAt {
            return TimeBucket(id: b.timestamp, tokens: b.tokens, quotaPct: 0)
        }
        return TimeBucket(id: b.timestamp, tokens: b.tokens, quotaPct: heldPct)
    }
}

// Credit history has no per-request token analog to bucket against, so each real
// polled reading becomes its own point directly (no session/weekly-style bucket
// grid, and no synthetic fallback — the chart is simply empty until readings exist).
private func creditTimeBuckets(from quotaHistory: [RemoteAnalytics.QuotaPointDTO]) -> [TimeBucket] {
    quotaHistory.map { TimeBucket(id: $0.timestamp, tokens: 0, quotaPct: $0.percentUsed * 100.0) }
}

// Fallback when the reset boundary is unknown: a single cumulative normalized so
// the whole span ends at `currentPct`. No reset drop (no boundary to drop at).
private func legacyTimeBuckets(_ buckets: [RemoteAnalytics.BucketDTO], currentPct: Double) -> [TimeBucket] {
    let totalTokens = buckets.reduce(0) { $0 + $1.tokens }
    // End the span at currentPct when it's known; otherwise (0%, just reset)
    // normalize the cumulative shape to 100% so the curve stays visible instead
    // of going flat. Matches the reset-aware path's fallback behavior.
    let endPct = currentPct > 0 ? currentPct * 100.0 : 100.0
    var cumulative  = 0
    return buckets.map { b in
        cumulative += b.tokens
        let pct = totalTokens > 0
            ? Double(cumulative) / Double(totalTokens) * endPct
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
            statPill(label: "Session", value: formatCost(data.sessionCost))
            statPill(label: "Today", value: formatCost(data.todayCost))
            statPill(label: "Week", value: formatCost(data.weeklyCost))
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
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
                HStack(alignment: .center, spacing: 4) {
                    Text(String(format: "%.0f%%", data.cacheHitRate * 100))
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

// MARK: - Model mix section

private struct ModelMixSection: View {
    let data: AnalyticsData
    let periodLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            analyticsHeader("MODELS BY TOKEN · \(periodLabel)")
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

