import SwiftUI

/// Top-centered search field. Width grows when focused and the clear button
/// appears only when there is text, matching the classic Launchpad behavior.
/// A circled options button on the right opens the same actions as the status
/// menu without taking over typing or Escape handling.
struct SearchBar: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    let scale: CGFloat

    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var width: CGFloat {
        (isFocused ? Metrics.searchFocusedWidth : Metrics.searchWidth) * scale
    }

    private var height: CGFloat { Metrics.searchHeight * scale }

    var body: some View {
        HStack(spacing: 8 * scale) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14 * scale, weight: .medium))
                .foregroundStyle(.white.opacity(Metrics.searchPlaceholderOpacity))
                .accessibilityHidden(true)

            ZStack(alignment: .leading) {
                if viewModel.searchText.isEmpty {
                    Text("Search Applications", comment: "Search field placeholder")
                        .font(.system(size: Metrics.searchFontSize * scale))
                        .foregroundStyle(.white.opacity(Metrics.searchPlaceholderOpacity))
                        .allowsHitTesting(false)
                }

                TextField("", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: Metrics.searchFontSize * scale))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($isFocused)
                    .onSubmit {
                        viewModel.handleReturn()
                    }
                    .accessibilityLabel(Text("Search apps", comment: "Search field accessibility label"))
            }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13 * scale))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search", comment: "Clear search button"))
                .transition(.opacity)
            }

            Menu {
                Button {
                    viewModel.onRequestPreferences?()
                } label: {
                    Text("Preferences…", comment: "Overlay options menu item")
                }
                Divider()
                Button {
                    viewModel.resetLayout()
                    viewModel.requestSearchFocus()
                } label: {
                    Text("Reset Layout", comment: "Preferences button")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 17 * scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("More options", comment: "Search options button"))
        }
        .padding(.leading, 14 * scale)
        .padding(.trailing, 8 * scale)
        .frame(width: width, height: height)
        .liquidGlass(
            .regular
                .tint(Metrics.glassTintSoft.color(for: colorScheme))
                .interactive(),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    Color.white.opacity(Metrics.searchOutlineOpacity),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .animation(widthAnimation, value: width)
        .onChange(of: viewModel.searchFocusToken) {
            isFocused = true
        }
        .onChange(of: viewModel.isVisible) { _, visible in
            if !visible { isFocused = false }
        }
        .accessibilityElement(children: .contain)
    }

    private var widthAnimation: Animation {
        viewModel.reduceMotion ? Metrics.Motion.reduced : .easeInOut(duration: 0.2)
    }
}
