import SwiftUI

/// The permission repair banner, shown next to the search field while gesture
/// blocking is enabled but macOS has not granted Accessibility to this build.
///
/// An ad-hoc signature is identified by the build's code hash, so every update
/// leaves the old switch in System Settings looking enabled while the running
/// app is untrusted. Without this banner that failure is silent: the desktop
/// swipe and Show Desktop simply start leaking again.
struct AccessibilityBanner: View {
    let metrics: LaunchpadMetrics
    let onFix: () -> Void

    @State private var isButtonHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: max(10, metrics.searchFontSize - 2), weight: .semibold))
                .foregroundStyle(Color.orange)

            Text("Allow gesture blocking")
                .font(.system(size: max(11, metrics.searchFontSize - 1), weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Button("Grant Access", action: onFix)
                .buttonStyle(.plain)
                .font(.system(size: max(11, metrics.searchFontSize - 1), weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: max(20, metrics.searchHeight - 10))
                .background(
                    Capsule().fill(.white.opacity(isButtonHovering ? 0.26 : 0.16))
                )
                .onHover { isButtonHovering = $0 }
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .frame(height: metrics.searchHeight)
        .glassEffect(.clear, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.20), lineWidth: 1)
        }
        .help(
            "macOS needs Accessibility access for this build, usually after an update. "
                + "Grant Access re-approves it."
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Gesture blocking needs Accessibility access"))
    }
}
