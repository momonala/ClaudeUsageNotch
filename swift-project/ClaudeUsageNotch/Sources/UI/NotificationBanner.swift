import SwiftUI
import AppKit

/// Custom in-app notification banner.
///
/// Slides in from the right side of the notch screen, stays 4 seconds, slides out.
/// Requires zero permissions — works for unsigned/locally-built apps out of the box.
/// Notifications queue so they never overlap.
final class NotificationBannerController {
    static let shared = NotificationBannerController()
    private init() {}

    private var queue: [(title: String, body: String)] = []
    private var isShowing = false

    func show(title: String, body: String) {
        DispatchQueue.main.async {
            self.queue.append((title, body))
            if !self.isShowing { self.presentNext() }
        }
    }

    private func presentNext() {
        guard !queue.isEmpty else { isShowing = false; return }
        isShowing = true
        let item = queue.removeFirst()

        guard let screen = ScreenUtils.notchScreen() else { isShowing = false; return }
        let w: CGFloat = 300
        let h: CGFloat = 72
        let margin: CGFloat = 14

        let restX   = screen.frame.maxX - w - margin
        let menuH   = screen.frame.maxY - screen.visibleFrame.maxY
        let restY   = screen.frame.maxY - menuH - h - margin
        let offX    = screen.frame.maxX + margin

        let panel = NSPanel(
            contentRect: NSRect(x: offX, y: restY, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level           = NSWindow.Level(rawValue: Int(NSWindow.Level.popUpMenu.rawValue))
        panel.isOpaque        = false
        panel.backgroundColor = .clear
        panel.hasShadow       = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let hosting = NSHostingController(rootView: BannerView(title: item.title, message: item.body))
        panel.contentView = hosting.view
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.38
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(x: restX, y: restY, width: w, height: h), display: true)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(NSRect(x: offX, y: restY, width: w, height: h), display: true)
            } completionHandler: {
                panel.orderOut(nil)
                self.isShowing = false
                self.presentNext()
            }
        }
    }
}

// MARK: - System-material background

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material    = .hudWindow
        v.blendingMode = .behindWindow
        v.state       = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Banner SwiftUI view

private struct BannerView: View {
    let title: String
    let message: String
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accentWarm.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.accentWarm)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300, height: 72)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clear)
                .background(
                    VisualEffectBackground()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}
