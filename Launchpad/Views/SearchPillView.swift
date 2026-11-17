import SwiftUI

/// The glass search pill at the top of the screen. Typing anywhere starts a
/// search; clicking the pill focuses the field.
struct SearchPillView: View {
    let metrics: LaunchpadMetrics
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onTap: () -> Void

    @State private var isOptionsHovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: metrics.searchFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))

            TextField("Search Applications", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: metrics.searchFontSize, weight: .regular))
                .foregroundStyle(.white.opacity(0.95))
                .tint(.white.opacity(0.7))
                .lineLimit(1)
                .focused(isFocused)
                .onSubmit(onSubmit)
                .accessibilityLabel(Text("Search Applications"))

            Spacer(minLength: 8)

            Button {
                onTap()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(isOptionsHovering ? 0.45 : 0.28), lineWidth: 1)
                        .background(
                            Circle().fill(.white.opacity(isOptionsHovering ? 0.14 : 0.02))
                        )
                    Image(systemName: "ellipsis")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(width: 20, height: 20)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isOptionsHovering = $0 }
            .accessibilityLabel(Text("Options"))
        }
        .padding(.horizontal, 15)
        .frame(width: metrics.searchWidth, height: metrics.searchHeight)
        // Keep clicks on the pill from reaching the grid underneath, which
        // dismisses the panel.
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .glassEffect(.clear, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Search Applications"))
    }
}
