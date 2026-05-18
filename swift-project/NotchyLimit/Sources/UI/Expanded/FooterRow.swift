import SwiftUI

struct FooterRow: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("v0.1.0")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Link("GitHub", destination: URL(string: "https://github.com/notchylimit/notchy-limit")!)
                .font(.system(size: 10))
                .foregroundColor(Theme.accentCool)
        }
    }
}
