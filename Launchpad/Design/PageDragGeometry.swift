import CoreGraphics

/// Pure geometry for one-page-at-a-time swipe interaction.
///
/// A drag or scroll previews at most a single page width. Values beyond that
/// are clamped so a fast gesture cannot reveal unrendered pages, and the
/// first/last page keeps the usual rubber-band resistance. Keeping the math
/// outside the view model makes the snap rules directly testable.
enum PageDragGeometry {
    static func boundedOffset(
        translation: CGFloat,
        page: Int,
        pageCount: Int,
        width: CGFloat
    ) -> CGFloat {
        let limit = max(1, width)
        let clamped = min(max(translation, -limit), limit)
        let atStart = page <= 0
        let atEnd = page >= max(0, pageCount - 1)
        if (atStart && clamped > 0) || (atEnd && clamped < 0) {
            return clamped * Metrics.rubberBandResistance
        }
        return clamped
    }

    static func targetPage(
        from page: Int,
        translation: CGFloat,
        velocity: CGFloat,
        pageCount: Int,
        width: CGFloat
    ) -> Int {
        let limit = max(1, width)
        var target = page
        if translation < -limit * Metrics.pageCommitDistanceRatio
            || velocity < -Metrics.pageCommitVelocity {
            target += 1
        } else if translation > limit * Metrics.pageCommitDistanceRatio
            || velocity > Metrics.pageCommitVelocity {
            target -= 1
        }
        return min(max(target, 0), max(0, pageCount - 1))
    }
}
