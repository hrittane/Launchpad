import SwiftUI

/// Bare page indicator dots. Hidden by the caller when there is only one page.
/// The active page is solid white; the others are translucent white. The dots
/// sit directly on the blurred wallpaper, with no pill or glass behind them.
struct PageDots: View {
    let pageCount: Int
    let currentPage: Int
    let diameter: CGFloat
    let spacing: CGFloat
    let onSelect: (Int) -> Void

    private var hitSize: CGFloat { max(16, diameter + 8) }

    var body: some View {
        HStack(spacing: max(0, spacing - (hitSize - diameter))) {
            ForEach(0..<pageCount, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(Color.white.opacity(
                            index == currentPage
                                ? Metrics.pageDotActiveOpacity
                                : Metrics.pageDotInactiveOpacity
                        ))
                        .frame(width: diameter, height: diameter)
                        .frame(width: hitSize, height: hitSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(
                    "Page \(index + 1) of \(pageCount)",
                    comment: "Page dot accessibility label"
                ))
                .accessibilityAddTraits(index == currentPage ? [.isSelected] : [])
            }
        }
        .animation(.easeInOut(duration: 0.15), value: currentPage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Pages", comment: "Page dots accessibility label"))
    }
}
