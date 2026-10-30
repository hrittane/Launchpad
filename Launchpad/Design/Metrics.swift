import SwiftUI

/// A black scrim layered over Liquid Glass. Light-mode glass is much brighter,
/// so it needs a stronger tint to keep the white Launchpad labels legible.
struct GlassTint: Equatable, Sendable {
    var light: Double
    var dark: Double

    func opacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? dark : light
    }

    func color(for scheme: ColorScheme) -> Color {
        Color.black.opacity(opacity(for: scheme))
    }
}

/// Centralized design constants. Every value is expressed at the 1440 × 900
/// reference size and scaled by `LayoutMetrics.scale` where appropriate.
enum Metrics {
    // MARK: Reference & margins

    static let referenceSize = CGSize(width: 1440, height: 900)
    static let scaleRange: ClosedRange<CGFloat> = 0.8...1.6
    static let gridHorizontalMarginRatio: CGFloat = 0.037
    static let gridTopMargin: CGFloat = 105
    static let gridBottomMargin: CGFloat = 59

    // MARK: Icons & labels

    static let defaultIconSize: CGFloat = 81
    static let iconShadowOpacity: Double = 0.35
    static let iconShadowRadius: CGFloat = 6
    static let iconShadowY: CGFloat = 3
    static let iconHoverScale: CGFloat = 1.05
    static let iconPressedScale: CGFloat = 0.92
    static let iconPressedBrightness: Double = -0.15
    static let iconCornerRadius: CGFloat = 22
    static let minimumHorizontalGap: CGFloat = 40
    static let minimumVerticalGap: CGFloat = 32

    static let labelSpacing: CGFloat = 10
    static let labelMaxLines = 1
    static let labelLineHeightFactor: CGFloat = 1.2
    static let labelShadowOpacity: Double = 0.6
    static let labelShadowRadius: CGFloat = 2
    static let labelShadowY: CGFloat = 1

    // MARK: Search

    static let searchWidth: CGFloat = 250
    static let searchFocusedWidth: CGFloat = 320
    static let searchHeight: CGFloat = 40
    static let searchTop: CGFloat = 29
    static let searchFontSize: CGFloat = 14
    static let searchPlaceholderOpacity: Double = 0.55
    /// Thin light rim that separates the glass pill from a bright wallpaper.
    static let searchOutlineOpacity: Double = 0.30

    // MARK: Page dots

    static let pageDotDiameter: CGFloat = 8
    static let pageDotSpacing: CGFloat = 14
    static let pageDotBottom: CGFloat = 18
    static let pageDotActiveOpacity: Double = 1.0
    static let pageDotInactiveOpacity: Double = 0.35
    static let folderPageDotDiameter: CGFloat = 7

    // MARK: Liquid Glass

    /// Tint layered over `.regular` glass. The material supplies depth and
    /// refraction; the tint only guarantees contrast for the white label text.
    static let glassTintSoft = GlassTint(light: 0.16, dark: 0.10)
    static let glassTintPanel = GlassTint(light: 0.20, dark: 0.14)
    /// The merge plate is a light sheen rather than a dark scrim, so it keeps
    /// the same white tint in both appearances.
    static let glassTintPlate: Double = 0.10

    // MARK: Folder

    static let folderPanelWidth: CGFloat = 560
    static let folderPanelHeight: CGFloat = 460
    static let folderPanelCornerRadius: CGFloat = 32
    static let folderColumns = 4
    static let folderRows = 3
    static let folderIconSize: CGFloat = 80
    static let folderLabelFontSize: CGFloat = 12
    static let folderPreviewIconSize: CGFloat = 24
    static let folderPreviewPadding: CGFloat = 8
    static let folderTitleFontSize: CGFloat = 24
    static let folderMaximumApps = 100

    // MARK: Background

    /// Flat black dimming over the blurred wallpaper. Light mode needs slightly
    /// less dimming because the wallpaper stays brighter to begin with.
    static let darkTintOpacity: Double = 0.25
    static let lightTintOpacity: Double = 0.22
    /// Solid fill used when the system asks for reduced transparency.
    static let reduceTransparencyBackground: Double = 0.85

    // MARK: Edit mode

    static let deleteBadgeSize: CGFloat = 22
    static let deleteBadgeOffset: CGFloat = 6
    static let focusRingWidth: CGFloat = 2
    static let focusRingOpacity: Double = 0.8
    static let focusRingCornerRadius: CGFloat = 24

    // MARK: Timing

    enum Durations {
        static let showBackground: Double = 0.18
        static let hideBackground: Double = 0.14
        static let hover: Double = 0.15
        static let pressed: Double = 0.10
        static let searchCrossFade: Double = 0.2
        static let folderOpen: Double = 0.35
        static let folderClose: Double = 0.25
        static let jiggle: Double = 0.13
        static let jiggleReturn: Double = 0.15
        static let dragHoverFolder: Double = 0.45
        static let dragEdgeFlip: Double = 0.7
        static let removeItem: Double = 0.2
        static let reducedMotion: Double = 0.15
        static let layoutSaveDebounce: Double = 0.5
        static let pageScrollCooldown: Double = 0.4
        static let pageSlide: Double = 0.30
        static let pageSnapBuffer: Double = 0.02
        static let hotCornerDwell: Double = 0.3
        static let longPress: Double = 0.5
        static let folderDoubleClick: Double = 0.24
        static let searchDebounce: Double = 0.08
    }

    // MARK: Interaction thresholds

    static let pageCommitDistanceRatio: CGFloat = 0.25
    static let pageCommitVelocity: CGFloat = 500
    static let rubberBandResistance: CGFloat = 0.35
    /// Pointer travel before an icon press becomes a drag. A lower threshold
    /// turns ordinary clicks into drags, which swallows the click and enters
    /// edit mode instead of launching the app.
    static let itemDragThreshold: CGFloat = 8
    static let folderMergeDistanceRatio: CGFloat = 0.4
    static let edgeFlipThreshold: CGFloat = 60
    static let hotCornerMargin: CGFloat = 3

    // MARK: Jiggle

    static let jiggleAngle: Double = 2
    static let jiggleTranslation: CGFloat = 0.5

    // MARK: Animations

    enum Motion {
        static let page = Animation.timingCurve(0.22, 0.90, 0.25, 1.0, duration: Durations.pageSlide)
        static let folder = Animation.spring(response: 0.33, dampingFraction: 0.88)
        /// Reflow animation for tiles displaced by a drag. The blend duration
        /// lets a new target take over mid-flight instead of restarting the
        /// spring from rest, which is what made rapid slot changes feel stuttery.
        static let reorder = Animation.spring(response: 0.30, dampingFraction: 0.85, blendDuration: 0.10)
        static let hover = Animation.easeInOut(duration: Durations.hover)
        static let pressed = Animation.easeOut(duration: Durations.pressed)
        static let reduced = Animation.easeInOut(duration: Durations.reducedMotion)
    }
}

/// Layout math for the main grid at a concrete screen size.
///
/// The effective icon size shrinks when the requested size, minimum gaps, or
/// the label block cannot fit a cell. This is the clarification that keeps a
/// 7 × 5 grid usable on a 1440 × 900 display.
struct LayoutMetrics {
    let screenSize: CGSize
    let scale: CGFloat
    let columns: Int
    let rows: Int
    let requestedIconSize: CGFloat
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    let labelBlockHeight: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let horizontalMargin: CGFloat
    let topMargin: CGFloat
    let bottomMargin: CGFloat
    let itemBlockHeight: CGFloat

    init(screenSize: CGSize, settings: AppSettings) {
        self.screenSize = screenSize
        let rawScale = screenSize.width / Metrics.referenceSize.width
        let scale = min(max(rawScale, Metrics.scaleRange.lowerBound), Metrics.scaleRange.upperBound)
        self.scale = scale
        self.columns = min(max(settings.columns, 5), 9)
        self.rows = min(max(settings.rows, 4), 6)
        self.requestedIconSize = CGFloat(settings.iconSize) * scale
        self.labelFontSize = CGFloat(settings.labelFontSize) * scale

        let horizontalMargin = screenSize.width * Metrics.gridHorizontalMarginRatio
        let topMargin = Metrics.gridTopMargin * scale
        let bottomMargin = Metrics.gridBottomMargin * scale
        self.horizontalMargin = horizontalMargin
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin

        let availableWidth = max(1, screenSize.width - horizontalMargin * 2)
        let availableHeight = max(1, screenSize.height - topMargin - bottomMargin)
        let cellWidth = availableWidth / CGFloat(self.columns)
        let cellHeight = availableHeight / CGFloat(self.rows)
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight

        let lineHeight = (self.labelFontSize * Metrics.labelLineHeightFactor).rounded(.up)
        let labelBlockHeight = lineHeight * CGFloat(Metrics.labelMaxLines)
        self.labelBlockHeight = labelBlockHeight
        let spacing = Metrics.labelSpacing * scale
        let maxByWidth = cellWidth - Metrics.minimumHorizontalGap * scale
        let maxByHeightGap = cellHeight - Metrics.minimumVerticalGap * scale
        let maxByLabel = cellHeight - spacing - labelBlockHeight
        let effective = min(self.requestedIconSize, maxByWidth, maxByHeightGap, maxByLabel)
        self.iconSize = max(28, min(effective, self.requestedIconSize))
        self.itemBlockHeight = self.iconSize + spacing + labelBlockHeight
    }

    /// The full grid area, excluding the search field and page dots.
    var gridRect: CGRect {
        CGRect(
            x: horizontalMargin,
            y: topMargin,
            width: screenSize.width - horizontalMargin * 2,
            height: screenSize.height - topMargin - bottomMargin
        )
    }

    var pageDotCenterY: CGFloat {
        screenSize.height - Metrics.pageDotBottom * scale
    }

    var searchSize: CGSize {
        CGSize(width: Metrics.searchWidth * scale, height: Metrics.searchHeight * scale)
    }

    var searchTopOffset: CGFloat {
        Metrics.searchTop * scale
    }

    func cellRect(at index: Int) -> CGRect {
        guard columns > 0, rows > 0 else { return .zero }
        let row = index / columns
        let column = index % columns
        return CGRect(
            x: gridRect.minX + CGFloat(column) * cellWidth,
            y: gridRect.minY + CGFloat(row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
    }

    /// Icon frame for a flat index on a page, with the item block centered.
    func iconFrame(at index: Int) -> CGRect {
        let cell = cellRect(at: index)
        let blockTop = cell.midY - itemBlockHeight / 2
        return CGRect(
            x: cell.midX - iconSize / 2,
            y: blockTop,
            width: iconSize,
            height: iconSize
        )
    }

    /// Largest requested icon size (in settings points) this grid can show.
    ///
    /// `iconSize` clamps requests to the cell and label block, so a preferences
    /// slider must not offer values above this cap: dragging into that range
    /// would change the setting without changing the rendered grid.
    var maximumIconSize: CGFloat {
        let maxByWidth = cellWidth - Metrics.minimumHorizontalGap * scale
        let maxByHeightGap = cellHeight - Metrics.minimumVerticalGap * scale
        let maxByLabel = cellHeight - Metrics.labelSpacing * scale - labelBlockHeight
        let cap = max(28, min(maxByWidth, maxByHeightGap, maxByLabel))
        return cap / scale
    }

    func iconCenter(at index: Int) -> CGPoint {
        let frame = iconFrame(at: index)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Returns the flat slot nearest to a point, or nil when the point is
    /// outside the grid. Used by custom drag-and-drop hit testing.
    func slot(at point: CGPoint) -> Int? {
        guard gridRect.contains(point) else { return nil }
        let column = Int((point.x - gridRect.minX) / cellWidth)
        let row = Int((point.y - gridRect.minY) / cellHeight)
        guard (0..<columns).contains(column), (0..<rows).contains(row) else { return nil }
        return row * columns + column
    }

    func pageIndex(forHorizontalOffset offset: CGFloat) -> Int {
        guard screenSize.width > 0 else { return 0 }
        return Int((-offset / screenSize.width).rounded())
    }
}

/// Layout math for the opened folder panel.
struct FolderMetrics {
    let panelSize: CGSize
    let scale: CGFloat
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    let columns: Int
    let rows: Int

    init(screenSize: CGSize, settings: AppSettings) {
        let raw = screenSize.width / Metrics.referenceSize.width
        let scale = min(max(raw, Metrics.scaleRange.lowerBound), Metrics.scaleRange.upperBound)
        self.scale = scale
        let width = min(Metrics.folderPanelWidth * scale, screenSize.width * 0.92)
        let height = min(Metrics.folderPanelHeight * scale, screenSize.height * 0.9)
        self.panelSize = CGSize(width: width, height: height)
        self.columns = Metrics.folderColumns
        self.rows = Metrics.folderRows
        self.iconSize = Metrics.folderIconSize * scale
        self.labelFontSize = Metrics.folderLabelFontSize * scale
    }

    var capacity: Int { columns * rows }

    /// Region available to the folder's grid inside the panel.
    var gridRect: CGRect {
        let titleHeight: CGFloat = 76 * scale
        let footerHeight: CGFloat = 42 * scale
        let horizontalInset: CGFloat = 34 * scale
        return CGRect(
            x: horizontalInset,
            y: titleHeight,
            width: panelSize.width - horizontalInset * 2,
            height: panelSize.height - titleHeight - footerHeight
        )
    }

    func cellRect(at index: Int) -> CGRect {
        let cellWidth = gridRect.width / CGFloat(columns)
        let cellHeight = gridRect.height / CGFloat(rows)
        let row = index / columns
        let column = index % columns
        return CGRect(
            x: gridRect.minX + CGFloat(column) * cellWidth,
            y: gridRect.minY + CGFloat(row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
    }

    func iconFrame(at index: Int) -> CGRect {
        let cell = cellRect(at: index)
        return CGRect(
            x: cell.midX - iconSize / 2,
            y: cell.midY - iconSize / 2 - 8 * scale,
            width: iconSize,
            height: iconSize
        )
    }

    func slot(at point: CGPoint) -> Int? {
        guard gridRect.contains(point) else { return nil }
        let cellWidth = gridRect.width / CGFloat(columns)
        let cellHeight = gridRect.height / CGFloat(rows)
        let column = Int((point.x - gridRect.minX) / cellWidth)
        let row = Int((point.y - gridRect.minY) / cellHeight)
        guard (0..<columns).contains(column), (0..<rows).contains(row) else { return nil }
        return row * columns + column
    }
}
