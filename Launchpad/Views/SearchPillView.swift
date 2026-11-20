import SwiftUI

/// The glass search pill at the top of the screen. Typing anywhere starts a
/// search; clicking the pill focuses the field.
struct SearchPillView: View {
    let metrics: LaunchpadMetrics
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onTap: () -> Void
    let onSettings: () -> Void

    @State private var isSettingsHovering = false

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: metrics.searchFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))

                ZStack(alignment: .leading) {
                    // A custom placeholder: the native prompt is drawn by the field
                    // editor with the system's secondary label colour, which turns
                    // black in light mode on top of the glass. It stays in the
                    // hierarchy and only fades, so clearing the query on the next
                    // presentation does not rebuild its sibling field editor.
                    Text("Search Applications")
                        .font(.system(size: metrics.searchFontSize, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .opacity(text.isEmpty ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: metrics.searchFontSize, weight: .regular))
                        .foregroundStyle(.white)
                        .tint(.white.opacity(0.7))
                        .lineLimit(1)
                        .focused(isFocused)
                        .onSubmit(onSubmit)
                        // The pill always sits on a wallpaper, so it is always dark:
                        // without this the field editor follows the system
                        // appearance and renders black text in light mode.
                        .environment(\.colorScheme, .dark)
                        .accessibilityLabel(Text("Search Applications"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            Button {
                onSettings()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(
                            .white.opacity(isSettingsHovering ? 0.45 : 0.28),
                            lineWidth: 1
                        )
                        .background(
                            Circle().fill(.white.opacity(isSettingsHovering ? 0.14 : 0.02))
                        )
                    Image(systemName: "gearshape")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(width: 20, height: 20)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isSettingsHovering = $0 }
            .accessibilityLabel(Text("Open Settings"))
        }
        .padding(.horizontal, 15)
        .frame(width: metrics.searchWidth, height: metrics.searchHeight)
        // Keep clicks on the pill from reaching the grid underneath, which
        // dismisses the panel.
        .contentShape(Capsule())
        .glassEffect(.clear, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Search Applications"))
    }
}
