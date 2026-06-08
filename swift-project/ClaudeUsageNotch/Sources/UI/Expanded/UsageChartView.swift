import SwiftUI
import Charts

struct TimeBucket: Identifiable {
    let id: Date
    let tokens: Int      // delta tokens consumed in this bucket
    let quotaPct: Double // cumulative % of window quota used up to end of this bucket
}

// File-level cache survives view recreation on hover-away/return.
private struct ChartCache {
    var sessionBuckets: [TimeBucket] = []
    var weeklyBuckets:  [TimeBucket] = []
    var cachedAt:       Date         = .distantPast

    var isValid: Bool { Date().timeIntervalSince(cachedAt) < 60 }

    mutating func store(session: [TimeBucket], weekly: [TimeBucket]) {
        sessionBuckets = session
        weeklyBuckets  = weekly
        cachedAt       = Date()
    }
}

private var chartCache = ChartCache()

struct UsageChartView: View {
    @ObservedObject var appState: AppState

    @State private var sessionBuckets: [TimeBucket] = []
    @State private var weeklyBuckets:  [TimeBucket] = []
    @State private var showQuota = false
    @State private var isLoading = true

    private var sessionWindow: UsageWindow? { appState.activeSnapshot?.sessionWindow }
    private var weeklyWindow:  UsageWindow? { appState.activeSnapshot?.weeklyWindow }

    private var yLabel: String { showQuota ? "% Quota" : "Tokens" }
    private func yValue(_ b: TimeBucket) -> Double { showQuota ? b.quotaPct : Double(b.tokens) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggleRow

            if isLoading {
                HStack { Spacer(); ProgressView().scaleEffect(0.7); Spacer() }
                    .frame(maxHeight: .infinity)
            } else {
                rule.padding(.top, 9)

                sectionHeader("SESSION · 5H",
                              pct: sessionWindow?.percentUsed ?? 0,
                              status: sessionWindow?.status ?? .unknown)
                    .padding(.top, 9)

                sessionChart
                    .frame(height: 86)
                    .padding(.top, 5)

                rule.padding(.top, 12)

                sectionHeader("WEEKLY · 7D",
                              pct: weeklyWindow?.percentUsed ?? 0,
                              status: weeklyWindow?.status ?? .unknown)
                    .padding(.top, 9)

                weeklyChart
                    .frame(height: 86)
                    .padding(.top, 5)
            }
        }
        .task { await loadData() }
    }

    // MARK: - Layout components

    private var toggleRow: some View {
        HStack {
            Spacer()
            Picker("", selection: $showQuota) {
                Text("Tokens").tag(false)
                Text("% Quota").tag(true)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .font(.system(size: 10, design: .rounded))
            .frame(width: 120)
            .padding(.trailing, 8)
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(height: 0.5)
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

    // MARK: - Charts

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
            BarMark(x: .value("Day", b.id, unit: .day), y: .value(yLabel, yValue(b)))
                .foregroundStyle(Theme.accentWarm.opacity(0.85))
                .cornerRadius(3)
        }
        .chartXAxis { dayAxis }
        .chartYAxis { yAxis }
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
        // Serve from cache if still fresh — avoids re-parsing JSONL on quick hover-away/return.
        if chartCache.isValid {
            sessionBuckets = chartCache.sessionBuckets
            weeklyBuckets  = chartCache.weeklyBuckets
            isLoading      = false
            return
        }

        isLoading = true
        let now           = Date()
        let sessionCutoff = now.addingTimeInterval(-5 * 3600)
        let weeklyCutoff  = now.addingTimeInterval(-6 * 24 * 3600)

        let sessionPct = sessionWindow?.percentUsed ?? 0
        let weeklyPct  = weeklyWindow?.percentUsed  ?? 0

        let all = await Task.detached(priority: .utility) {
            LocalHistoryReader.read(since: weeklyCutoff)
        }.value

        let session = makeBuckets(
            records: all.filter { $0.timestamp >= sessionCutoff },
            unit: .minute, from: sessionCutoff, count: 5 * 60,
            currentPct: sessionPct
        )
        let weekly = makeBuckets(
            records: all,
            unit: .day, from: weeklyCutoff, count: 7,
            currentPct: weeklyPct
        )

        chartCache.store(session: session, weekly: weekly)
        sessionBuckets = session
        weeklyBuckets  = weekly
        isLoading      = false
    }

    private func makeBuckets(records: [UsageRecord], unit: Calendar.Component,
                              from start: Date, count: Int,
                              currentPct: Double) -> [TimeBucket] {
        let cal          = Calendar.current
        let alignedStart = cal.dateInterval(of: unit, for: start)?.start ?? start

        var grouped: [Date: Int] = [:]
        for r in records {
            guard let slot = cal.dateInterval(of: unit, for: r.timestamp)?.start else { continue }
            grouped[slot] = (grouped[slot] ?? 0) + r.totalTokens
        }

        let totalTokens = records.reduce(0) { $0 + $1.totalTokens }
        var cumulative  = 0

        return (0..<count).map { i in
            let slot  = cal.date(byAdding: unit, value: i, to: alignedStart)!
            let delta = grouped[slot] ?? 0
            cumulative += delta
            let pct = totalTokens > 0
                ? Double(cumulative) / Double(totalTokens) * currentPct * 100.0
                : 0.0
            return TimeBucket(id: slot, tokens: delta, quotaPct: pct)
        }
    }
}
