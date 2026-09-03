import SwiftUI
import Charts

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

// MARK: - Fetched chart data

/// Everything one `/api/analytics` response yields, held as a single value so
/// the view's state and the cache below can't drift apart field by field.
private struct ChartData {
    var session = QuotaSeries()
    var weekly  = QuotaSeries()
    var credit  = QuotaSeries()
    var analytics: AnalyticsData = .empty
}

/// Process-global so the 60s cache survives view teardown on hover-away and
/// return. `@MainActor` pins all access to the main actor, the only place it's
/// touched.
@MainActor private var chartCache: (data: ChartData, period: LookbackPeriod, at: Date)?

@MainActor private func cachedChartData(for period: LookbackPeriod) -> (ChartData, Date)? {
    guard let cache = chartCache, cache.period == period,
          Date().timeIntervalSince(cache.at) < 60 else { return nil }
    return (cache.data, cache.at)
}

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

    @State private var data = ChartData()
    @State private var showQuota = true
    @State private var lookback: LookbackPeriod = .month
    @State private var isLoading = true
    @State private var lastUpdatedAt: Date?
    @State private var fetchError: String?
    @State private var now = Date()

    private var sessionWindow: UsageWindow? { appState.snapshot?.sessionWindow }
    private var weeklyWindow:  UsageWindow? { appState.snapshot?.weeklyWindow }
    private var creditWindow:  UsageWindow? { appState.snapshot?.creditWindow }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isLoading {
                    HStack { Spacer(); ProgressView().scaleEffect(0.7); Spacer() }
                        .frame(maxHeight: .infinity)
                } else if let fetchError {
                    Text(fetchError)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    columns
                }
            }
            .frame(maxHeight: .infinity)

            if let lastUpdatedAt {
                Rectangle().fill(Theme.stroke).frame(height: 0.5).padding(.top, 6)
                HStack {
                    Spacer()
                    Text("updated \(lastUpdatedAt.formatted(.dateTime.hour().minute().second()))  ·  \(relativeTime(from: lastUpdatedAt, to: now))")
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

    private var columns: some View {
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

    private func relativeTime(from date: Date, to reference: Date) -> String {
        let seconds = Int(reference.timeIntervalSince(date))
        switch seconds {
        case ..<60:     return "\(max(0, seconds))s ago"
        case 60..<3600: return "\(seconds / 60)m ago"
        default:        return "\(seconds / 3600)h ago"
        }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                windowSection("SESSION · 5H", window: sessionWindow, series: data.session,
                              xAxis: { hourAxis }, topPadding: 8)

                divider.padding(.top, 10)
                windowSection("WEEK · 7D", window: weeklyWindow, series: data.weekly,
                              xAxis: { dayAxis })

                if let creditWindow {
                    divider.padding(.top, 10)
                    sectionHeader("USAGE CREDITS · MONTH", window: creditWindow).padding(.top, 8)
                    creditChart
                        .frame(height: 108)
                        .padding(.top, 5)
                }

                divider.padding(.top, 10)
                analyticsHeader("SPEND PER \(lookback.granularity.unitLabel) · \(lookback.rawValue)").padding(.top, 8)
                seriesChart(data.analytics.dailyCost, yLabel: "Cost") { String(format: "$%.2f", $0) }
                    .frame(height: 88)
                    .padding(.top, 5)

                divider.padding(.top, 10)
                analyticsHeader("USAGE BY HOUR · \(lookback.rawValue)").padding(.top, 8)
                hourlyActivityChart
                    .frame(height: 88)
                    .padding(.top, 5)

                divider.padding(.top, 10)
                analyticsHeader("SESSIONS PER \(lookback.granularity.unitLabel) · \(lookback.rawValue)").padding(.top, 8)
                seriesChart(data.analytics.dailySessions, yLabel: "Sessions") { $0 == $0.rounded() ? "\(Int($0))" : nil }
                    .frame(height: 88)
                    .padding(.top, 5)
                    .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private func windowSection(
        _ label: String,
        window: UsageWindow?,
        series: QuotaSeries,
        @AxisContentBuilder xAxis: () -> some AxisContent,
        topPadding: CGFloat = 8
    ) -> some View {
        sectionHeader(label, window: window).padding(.top, topPadding)
        tokenChart(series, window: window, xAxis: xAxis)
            .frame(height: 108)
            .padding(.top, 5)
    }

    // MARK: - Right column

    private var rightColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TokenBreakdownSection(data: data.analytics, periodLabel: lookback.rawValue)
                divider.padding(.top, 10)
                CacheSection(data: data.analytics, periodLabel: lookback.rawValue).padding(.top, 10)
                divider.padding(.top, 10)
                ModelMixSection(data: data.analytics, periodLabel: lookback.rawValue).padding(.top, 10)
                divider.padding(.top, 10)
                RankedBreakdownSection(title: "PROJECTS BY TOKEN · \(lookback.rawValue)",
                                       items: data.analytics.projectBreakdown).padding(.top, 10)
                divider.padding(.top, 10)
                RankedBreakdownSection(title: "SKILLS BY TOKEN · \(lookback.rawValue)",
                                       items: data.analytics.skillBreakdown).padding(.top, 10)
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

            CostSection(data: data.analytics)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(height: 0.5)
    }

    private func sectionHeader(_ label: String, window: UsageWindow?) -> some View {
        let pct = window?.effectivePercentUsed() ?? 0
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(Theme.sectionLabelFont)
                .kerning(Theme.sectionLabelKerning)
                .foregroundColor(Theme.textSecondary)
            if let nextReset = window?.resetAtLabel() {
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
                    .foregroundColor((window?.effectiveStatus() ?? .unknown).color)
            }
        }
    }

    // MARK: - Left charts

    private var yLabel: String { showQuota ? "% Quota" : "Tokens" }
    private func yValue(_ bucket: TimeBucket) -> Double { showQuota ? bucket.quotaPct : Double(bucket.tokens) }

    private func tokenChart(
        _ series: QuotaSeries,
        window: UsageWindow?,
        @AxisContentBuilder xAxis: () -> some AxisContent
    ) -> some View {
        let expectedPct = window?.expectedProgress().map { $0 * 100 }
        let currentPct = (window?.effectivePercentUsed() ?? 0) * 100
        // Match the usage cards: green when under expected pace, orange when over.
        let overPace = expectedPct.map { currentPct > $0 } ?? false
        return Chart {
            ForEach(series.buckets) { bucket in
                areaAndLine(x: bucket.id, y: yValue(bucket), label: yLabel, interpolation: .catmullRom)
            }
            ForEach(series.allResets, id: \.self) { reset in
                resetRule(at: reset)
            }
            if showQuota, let expectedPct {
                RuleMark(y: .value("Expected", expectedPct))
                    .foregroundStyle((overPace ? Theme.statusWarning : Theme.statusHealthy).opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXAxis(content: xAxis)
        .chartYAxis { quotaOrTokenYAxis }
        .chartPlotStyle { $0.background(Color.clear) }
    }

    /// Unlike the session and weekly charts, always plots the real % of the
    /// credit pool (a step function held between polls) — there's no
    /// per-request token analog to dual-render with the Tokens/% Quota toggle.
    private var creditChart: some View {
        Chart {
            ForEach(data.credit.buckets) { bucket in
                areaAndLine(x: bucket.id, y: bucket.quotaPct, label: "% Used", interpolation: .stepEnd)
            }
            ForEach(data.credit.allResets, id: \.self) { reset in
                resetRule(at: reset)
            }
        }
        .chartXAxis { monthAxis }
        .chartYScale(domain: 0...100)
        .chartYAxis { percentYAxis }
        .chartPlotStyle { $0.background(Color.clear) }
    }

    private var hourlyActivityChart: some View {
        Chart(data.analytics.hourlyActivity) { hour in
            AreaMark(x: .value("Hour", hour.hour), y: .value("Avg requests", hour.value))
                .foregroundStyle(Self.areaGradient(topOpacity: 0.3))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Hour", hour.hour), y: .value("Avg requests", hour.value))
                .foregroundStyle(Theme.accentWarm.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
        }
        .chartXScale(domain: 0...23)
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, through: 23, by: 3))) { value in
                AxisGridLine().foregroundStyle(Theme.stroke)
                if let hour = value.as(Int.self) {
                    axisLabel(String(format: "%02d", hour), design: .rounded)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.stroke)
                if let n = value.as(Double.self) {
                    axisLabel(n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n))
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
    }

    private func seriesChart(_ values: [DailyValue], yLabel: String,
                             formatter: @escaping (Double) -> String?) -> some View {
        let unit = lookback.granularity.axisUnit
        return Chart(values) { value in
            AreaMark(x: .value("Time", value.date, unit: unit), y: .value(yLabel, value.value))
                .foregroundStyle(Self.areaGradient())
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Time", value.date, unit: unit), y: .value(yLabel, value.value))
                .foregroundStyle(Theme.accentWarm)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis { seriesXAxis }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.stroke)
                if let n = value.as(Double.self), let label = formatter(n) {
                    axisLabel(label)
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
    }

    // MARK: - Chart marks

    private static func areaGradient(topOpacity: Double = 0.55) -> LinearGradient {
        LinearGradient(
            colors: [Theme.accentWarm.opacity(topOpacity), Theme.accentWarm.opacity(0.05)],
            startPoint: .top, endPoint: .bottom
        )
    }

    @ChartContentBuilder
    private func areaAndLine(x: Date, y: Double, label: String,
                             interpolation: InterpolationMethod) -> some ChartContent {
        AreaMark(x: .value("Time", x), y: .value(label, y))
            .foregroundStyle(Self.areaGradient())
            .interpolationMethod(interpolation)
        LineMark(x: .value("Time", x), y: .value(label, y))
            .foregroundStyle(Theme.accentWarm)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(interpolation)
    }

    private func resetRule(at time: Date) -> some ChartContent {
        RuleMark(x: .value("Reset", time))
            .foregroundStyle(Color.green.opacity(0.55))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
    }

    // MARK: - Axes

    private func axisLabel(_ text: String, design: Font.Design = .monospaced) -> some AxisMark {
        AxisValueLabel(text)
            .font(.system(size: 8, design: design))
            .foregroundStyle(Theme.textSecondary)
    }

    /// Spend/sessions x-axis: hour-of-day for 1D, day-of-month otherwise
    /// (thinned to every third tick over 30D), month name for All.
    @AxisContentBuilder
    private var seriesXAxis: some AxisContent {
        switch lookback.granularity {
        case .hour:
            hourOfDayAxis(strideCount: 2)
        case .day:
            AxisMarks(values: .stride(by: .day, count: lookback == .month ? 3 : 1)) { value in
                AxisGridLine().foregroundStyle(Theme.stroke)
                if let date = value.as(Date.self) {
                    axisLabel("\(Calendar.current.component(.day, from: date))", design: .rounded)
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
    private func hourOfDayAxis(strideCount: Int) -> some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: strideCount)) { value in
            AxisGridLine().foregroundStyle(Theme.stroke)
            if let date = value.as(Date.self) {
                axisLabel(String(format: "%02d", Calendar.current.component(.hour, from: date)), design: .rounded)
            }
        }
    }

    @AxisContentBuilder
    private var hourAxis: some AxisContent { hourOfDayAxis(strideCount: 3) }

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
    private var percentYAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(Theme.stroke)
            if let pct = value.as(Double.self) {
                axisLabel(String(format: "%.0f%%", pct))
            }
        }
    }

    @AxisContentBuilder
    private var quotaOrTokenYAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(Theme.stroke)
            if let v = value.as(Double.self) {
                axisLabel(showQuota ? String(format: "%.1f%%", v) : "\(Int(v.rounded()))")
            }
        }
    }

    // MARK: - Data loading

    private func loadData() async {
        if let (cached, cachedAt) = cachedChartData(for: lookback) {
            data          = cached
            lastUpdatedAt = cachedAt
            isLoading     = false
            return
        }

        guard let baseURL = appSettings.apiURL() else {
            NSLog("[ClaudeUsageNotch] chart: no apiBaseURL set; remote disabled")
            isLoading = false
            return
        }

        isLoading = true
        let now = Date()
        // A full 24h so the 5h session window can be seen resetting several
        // times across the chart. The "Session" cost pill needs the *actual*
        // current session instead, hence the separate cutoff below.
        let sessionSince = now.addingTimeInterval(-24 * 3600)
        // The real start of the current 5h session, so the "Session" cost pill
        // doesn't pick up spend from outside the rolling window (which made it
        // possible for "Session" to exceed "Today"). Falls back to the 24h-back
        // value before the first poll has populated sessionWindow.
        let sessionCostSince = sessionWindow
            .flatMap { window in window.resetAt.map { $0.addingTimeInterval(-window.windowDuration) } }
            ?? sessionSince
        let weeklySince   = LookbackPeriod.week.sinceDate    // fixed 7d  → weekly pill + chart
        let monthSince    = LookbackPeriod.month.sinceDate   // fixed 30d → month pill
        let lookbackSince = lookback.sinceDate               // selector  → breakdowns + daily charts

        do {
            let remote = try await RemoteHistoryReader.fetchAnalytics(
                sessionSince: sessionSince, sessionCostSince: sessionCostSince, weeklySince: weeklySince,
                monthSince: monthSince, lookbackSince: lookbackSince,
                granularity: lookback.granularity.rawValue,
                baseURL: baseURL
            )
            NSLog("[ClaudeUsageNotch] chart: loaded analytics from remote \(baseURL.absoluteString)")

            let session = sessionWindow
            let weekly = weeklyWindow
            let fetched = await Task.detached(priority: .utility) {
                ChartData(
                    session: quotaSeries(
                        buckets: remote.sessionBuckets, quotaHistory: remote.sessionQuotaHistory,
                        currentPct: session?.effectivePercentUsed() ?? 0,
                        resetAt: session?.resetAt,
                        windowDuration: session?.windowDuration ?? 5 * 3600,
                        span: DateInterval(start: sessionSince, end: now)
                    ),
                    weekly: quotaSeries(
                        buckets: remote.weeklyBuckets, quotaHistory: remote.weeklyQuotaHistory,
                        currentPct: weekly?.effectivePercentUsed() ?? 0,
                        resetAt: weekly?.resetAt,
                        windowDuration: weekly?.windowDuration ?? 7 * 24 * 3600,
                        span: DateInterval(start: weeklySince, end: now)
                    ),
                    credit: creditSeries(
                        quotaHistory: remote.creditQuotaHistory,
                        span: DateInterval(start: monthSince, end: now)
                    ),
                    analytics: remote.toAnalyticsData()
                )
            }.value

            data          = fetched
            lastUpdatedAt = Date()
            fetchError    = nil
            chartCache    = (fetched, lookback, Date())
        } catch {
            NSLog("[ClaudeUsageNotch] chart: remote analytics failed: \(error.localizedDescription)")
            fetchError = error.localizedDescription
        }

        isLoading = false
    }
}
