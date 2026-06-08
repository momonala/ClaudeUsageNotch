import SwiftUI

/// Multi-provider compact pill shown inside the notch when 2+ providers are active.
///
/// Each provider gets a coloured dot + mini progress bar. The pill widens slightly
/// to fit both without feeling crowded. The colour of each dot reflects that
/// provider's worst-window status, giving an instant health overview at a glance.
struct ConstellationView: View {
    @ObservedObject var appState: AppState
    @State private var appeared = false

    private var activeSnaps: [(ProviderId, ServiceUsageSnapshot)] {
        appState.enabledProviders
            .compactMap { id in appState.snapshots[id].map { (id, $0) } }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NotchPillShape(topRadius: 0, bottomRadius: 14)
                .fill(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                ForEach(activeSnaps, id: \.0) { (id, snap) in
                    providerIndicator(snap, providerId: id)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 22)
        }
        .shadow(color: combinedGlowColor.opacity(appeared ? 0.35 : 0), radius: 10, y: 5)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.22)) { appeared = true }
        }
        .help(toolTip)
    }

    @ViewBuilder
    private func providerIndicator(_ snap: ServiceUsageSnapshot, providerId: ProviderId) -> some View {
        let status = snap.combinedStatus
        let color  = status.color
        let pct    = snap.sessionWindow.percentUsed
        let incident = appState.incidents[providerId].flatMap { $0.level.isActive ? $0 : nil }

        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill((incident?.level.tint ?? color).opacity(0.20))
                    .frame(width: 10, height: 10)
                    .blur(radius: 2.5)
                if let incident {
                    Image(systemName: incident.level.glyph)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(incident.level.tint)
                } else {
                    Circle().fill(color).frame(width: 4, height: 4)
                }
            }

            if !snap.showsPercentBar {
                Text(snap.shortLabel)
                    .font(Theme.notchFontTiny)
                    .foregroundColor(.white.opacity(0.82))
                    .frame(minWidth: 22, alignment: .trailing)
            } else {
                CompactProgressBar(
                    progress: pct,
                    color: color,
                    expectedProgress: snap.sessionWindow.expectedProgress()
                )
                .frame(width: 52, height: 2.5)

                Text("\(Int((pct * 100).rounded()))%")
                    .font(Theme.notchFontTiny)
                    .foregroundColor(.white.opacity(0.82))
                    .frame(minWidth: 22, alignment: .trailing)
            }
        }
    }

    private var combinedGlowColor: Color { appState.combinedStatus.color }

    private var toolTip: String {
        activeSnaps.map { (id, snap) in
            "\(id.displayName) \(snap.shortLabel)"
        }.joined(separator: " · ")
    }
}
