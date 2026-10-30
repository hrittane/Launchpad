import SwiftUI

/// Page indicator dots. Hidden by the caller when there is only one page.
struct PageDots: View {
    /// How the indicator is drawn. The main grid floats the dots over the
    /// desktop, so it hosts them on a glass pill. The folder panel keeps them
    /// plain because that panel is already a glass surface.
    enum Style {
        case plain
        case glass
    }

    let pageCount: Int
    let currentPage: Int
    let diameter: CGFloat
    let spacing: CGFloat
    var style: Style = .plain
    let onSelect: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var hitSize: CGFloat { max(16, diameter + 8) }

    /// Padding scales with the dot size so the pill keeps its proportions when
    /// the window is small or large.
    private var pillPadding: EdgeInsets {
        let vertical = max(3, diameter * 0.55)
        let horizontal = max(6, diameter * 1.3)
        return EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    @ViewBuilder
    var body: some View {
        switch style {
        case .plain:
            dots
        case .glass:
            dots
                .padding(pillPadding)
                .liquidGlass(
                    .regular.tint(Metrics.pageDotPillTint.color(for: colorScheme)),
                    in: Capsule()
                )
        }
    }

    private var dots: some View {
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
