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

/// High-frequency pointer position for an in-flight item drag.
///
/// A drag publishes a new location on every mouse-moved event. If that value
/// lived on the view model, each event would re-evaluate every icon on the
/// three visible pages. Keeping it in a tiny observable that only the floating
/// drag preview observes makes cursor tracking a cheap layer update.
final class ItemDragState: ObservableObject {
    @Published var location: CGPoint = .zero
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
