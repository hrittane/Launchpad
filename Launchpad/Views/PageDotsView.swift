import SwiftUI

/// Page indicator dots. Bare at rest, a small glass capsule on hover, matching
/// frames 003/021 and 016 of the reference. Each dot is clickable.
struct PageDotsView: View {
    let pageCount: Int
    let currentPage: Int
    let metrics: LaunchpadMetrics
    let onSelect: (Int) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: metrics.dotSpacing) {
            ForEach(0..<max(pageCount, 1), id: \.self) { page in
                Button {
                    onSelect(page)
                } label: {
                    Circle()
                        .fill(.white.opacity(page == currentPage ? 1.0 : 0.30))
                        .frame(width: metrics.dotSize, height: metrics.dotSize)
                        .frame(width: metrics.dotSpacing, height: metrics.dotSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Page \(page + 1)"))
                .accessibilityAddTraits(page == currentPage ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isHovering {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.clear, in: .capsule)
                    .transition(.opacity)
            }
        }
        .contentShape(Capsule())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(.easeOut(duration: 0.15), value: pageCount)
        .animation(.easeOut(duration: 0.2), value: currentPage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Page \(currentPage + 1) of \(max(pageCount, 1))"))
    }
}
