import SwiftUI

/// Top-centered search field. Width grows when focused and the clear button
/// appears only when there is text, matching the classic Launchpad behavior.
struct SearchBar: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    let scale: CGFloat

    @FocusState private var isFocused: Bool

    private var width: CGFloat {
        (isFocused ? Metrics.searchFocusedWidth : Metrics.searchWidth) * scale
    }

    private var height: CGFloat { Metrics.searchHeight * scale }

    var body: some View {
        HStack(spacing: 8 * scale) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13 * scale, weight: .medium))
                .foregroundStyle(.white.opacity(Metrics.searchPlaceholderOpacity))
                .accessibilityHidden(true)

            ZStack(alignment: .leading) {
                if viewModel.searchText.isEmpty {
                    Text("Search", comment: "Search field placeholder")
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
        }
        .padding(.horizontal, 10 * scale)
        .frame(width: width, height: height)
        .background {
            RoundedRectangle(cornerRadius: Metrics.searchCornerRadius * scale, style: .continuous)
                .fill(Color.white.opacity(Metrics.searchFieldOpacity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.searchCornerRadius * scale, style: .continuous)
                .stroke(Color.white.opacity(Metrics.searchBorderOpacity), lineWidth: 0.5)
        }
        .opacity(viewModel.isVisible ? 1 : 0)
        .animation(widthAnimation, value: width)
        .animation(visibilityAnimation, value: viewModel.isVisible)
        .onChange(of: viewModel.searchFocusToken) { _ in
            isFocused = true
        }
        .onChange(of: viewModel.isVisible) { visible in
            if !visible { isFocused = false }
        }
        .accessibilityElement(children: .contain)
    }

    private var widthAnimation: Animation {
        viewModel.reduceMotion ? Metrics.Motion.reduced : .easeInOut(duration: 0.2)
    }

    private var visibilityAnimation: Animation {
        if viewModel.reduceMotion { return Metrics.Motion.reduced }
        return viewModel.isVisible
            ? .easeOut(duration: Metrics.Durations.showBackground)
            : .easeIn(duration: Metrics.Durations.hideIcons)
    }
}
