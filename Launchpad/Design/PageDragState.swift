import SwiftUI

/// High-frequency paging offset kept out of `LaunchpadViewModel`.
///
/// A trackpad gesture publishes a new offset on every scroll event. If that
/// value lived on the view model, every view observing the model — including
/// all icons on the three visible pages — would re-evaluate its body at the
/// gesture frequency. Instead the offset lives in this tiny observable that
/// only the offset modifier observes, so paging stays a cheap layer transform.
final class PageDragState: ObservableObject {
    @Published var offset: CGFloat = 0
}

/// Applies a `PageDragState` offset without invalidating the wrapped content.
/// The modifier's body re-runs per scroll event, while the grid it wraps keeps
/// its existing view identity and rendered layers.
struct PageDragOffsetModifier: ViewModifier {
    @ObservedObject var state: PageDragState

    func body(content: Content) -> some View {
        content.offset(x: state.offset)
    }
}
