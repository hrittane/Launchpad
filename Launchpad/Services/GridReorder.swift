import Foundation

/// The layout the grid will commit if the current drag ends here.
///
/// `locations` maps every entry id to the page and slot it should occupy while
/// the drag preview is visible, so the views can reflow without changing their
/// identity (which would cancel the in-flight drag gesture).
struct GridReorderPreview: Equatable {
    struct Slot: Equatable {
        let page: Int
        let index: Int
    }

    let pages: [PageLayout]
    let locations: [String: Slot]
    let draggedEntryID: String
}

/// Pure reorder math shared by the live preview and the drop commit.
///
/// The dragged entry is removed from the flat list, inserted at the absolute
/// index of the cell under the cursor (`page * capacity + slot`), and the
/// result is repaginated. Because the preview is produced by exactly the same
/// function as the commit, the icon can never land somewhere other than where
/// it was shown.
enum GridReorder {
    static func preview(
        moving entryID: String,
        toPage page: Int,
        slot: Int,
        in pages: [PageLayout],
        capacity: Int
    ) -> GridReorderPreview? {
        let capacity = max(1, capacity)
        var flat = LayoutEngine.flatten(pages)
        guard let sourceIndex = flat.firstIndex(where: { $0.id == entryID }) else {
            return nil
        }

        let entry = flat.remove(at: sourceIndex)
        // Pages are packed, so the absolute post-removal index of the cursor's
        // cell is page * capacity + slot. Clamping appends to the very end when
        // the cursor is past the last item.
        let targetIndex = min(max(page, 0) * capacity + max(slot, 0), flat.count)
        flat.insert(entry, at: targetIndex)

        let result = LayoutEngine.paginate(flat, capacity: capacity)
        var locations: [String: GridReorderPreview.Slot] = [:]
        for (pageIndex, entries) in result.enumerated() {
            for (index, item) in entries.enumerated() {
                locations[item.id] = GridReorderPreview.Slot(page: pageIndex, index: index)
            }
        }
        return GridReorderPreview(pages: result, locations: locations, draggedEntryID: entryID)
    }
}
