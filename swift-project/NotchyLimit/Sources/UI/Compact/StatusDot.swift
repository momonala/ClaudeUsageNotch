import SwiftUI

struct StatusDot: View {
    var status: UsageStatus
    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
            .shadow(color: status.color.opacity(0.6), radius: 4)
    }
}
