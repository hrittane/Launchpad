import CoreGraphics

/// Layout measurements derived from the reference frames in `screenshots/`.
///
/// The reference frames are 1107 × 720 pt. Everything that should scale with
/// the display is expressed as a fraction of width/height; text stays at a
/// legible fixed size.
struct LaunchpadMetrics {
    let size: CGSize
    var columns: Int = LaunchpadMetrics.defaultColumns
    var rows: Int = LaunchpadMetrics.defaultRows
    /// User multiplier for the icon size derived from the grid density.
    var iconScale: CGFloat = 1
    /// User multiplier for the label font size.
    var labelScale: CGFloat = 1
    var showsLabels: Bool = true

    static let defaultColumns = 7
    static let defaultRows = 5

    var pageCapacity: Int { columns * rows }

    // MARK: Grid

    /// The reference grid spans 75 % of the screen width between the first and
    /// last column centres. The pitch therefore shrinks as columns are added,
    /// which is what makes an 8- or 9-column grid fit without zooming.
    private static let gridWidthFraction: CGFloat = 0.7498
    /// The reference grid spans 59.7 % of the screen height between the first
    /// and last row centres.
    private static let gridHeightFraction: CGFloat = 0.597

    /// 59 px at 1107 wide (5.33 % of width) for the default 7 × 5 grid.
    ///
    /// This is the *visible* squircle. `NSWorkspace` icons are full 1024 px
    /// canvases whose artwork occupies ~824 px, so the image is drawn larger and
    /// then clipped back to this footprint.
    var iconSize: CGFloat {
        let columnLimited = columnPitch * 0.4267
        // The grid is width-constrained, but a six-row grid would overflow the
        // screen if the icons kept their width-derived size.
        let rowLimited = rowPitch * 0.62
        return min(max(min(columnLimited, rowLimited) * iconScale, 28), 118)
    }

    /// 1024 / 824 — macOS app icon artwork inset inside its canvas.
    var iconArtworkScale: CGFloat { 1.243 }

    /// 138.33 px at 1107 wide (12.49 % of width) for seven columns.
    var columnPitch: CGFloat {
        guard size.width > 0 else { return 0 }
        let gaps = max(columns - 1, 1)
        return size.width * Self.gridWidthFraction / CGFloat(gaps)
    }

    /// 107.5 px at 720 high (14.93 % of height) for five rows.
    var rowPitch: CGFloat {
        let gaps = max(rows - 1, 1)
        return size.height * Self.gridHeightFraction / CGFloat(gaps)
    }

    /// First icon's top edge: 94 px at 720 high (13.06 % of height).
    var gridTop: CGFloat {
        size.height * 0.1306
    }

    var labelGap: CGFloat {
        showsLabels ? max(6, iconSize * 0.22) : 0
    }

    var labelHeight: CGFloat {
        guard showsLabels else { return 0 }
        return max(12, min(size.width * 0.0152, 22) * labelScale)
    }

    /// Reference labels are ~10 px tall at 1107 wide (≈17 pt at 1920). They
    /// shrink with the icons when the grid gets denser.
    var labelFontSize: CGFloat {
        let base = min(max(size.width * 0.00885, 12), 18)
        let defaultIcon = size.width * 0.0533
        let density = defaultIcon > 0 ? iconSize / defaultIcon : 1
        return min(max(base * density * labelScale, 9), 22)
    }

    var cellHeight: CGFloat {
        iconSize + labelGap + labelHeight
    }

    var gridWidth: CGFloat {
        columnPitch * CGFloat(columns - 1) + iconSize
    }

    func columnX(_ column: Int) -> CGFloat {
        size.width / 2 - columnPitch * CGFloat(columns - 1) / 2 + CGFloat(column) * columnPitch
    }

    func rowTop(_ row: Int) -> CGFloat {
        gridTop + CGFloat(row) * rowPitch
    }

    // MARK: Search

    /// 181 × 30 px at 1107 × 720 (16.35 % W, 4.17 % H).
    var searchWidth: CGFloat {
        min(max(size.width * 0.1635, 190), 330)
    }

    var searchHeight: CGFloat {
        min(max(size.height * 0.0425, 30), 52)
    }

    var searchTop: CGFloat {
        size.height * 0.0514
    }

    var searchFontSize: CGFloat {
        min(max(size.height * 0.0153, 11), 15)
    }

    // MARK: Page dots

    var dotsCenterY: CGFloat {
        size.height * 0.889
    }

    /// 6 px dots at 1107 wide.
    var dotSize: CGFloat {
        max(6, size.width * 0.0054)
    }

    var dotSpacing: CGFloat {
        max(12, size.width * 0.0113)
    }

    // MARK: Folders

    var folderColumns: Int { 7 }
    var folderRows: Int { 3 }
    var folderIconSize: CGFloat { min(max(size.width * 0.047, 42), 96) }
    var folderPanelWidth: CGFloat { size.width * 0.865 }

    /// 328 / 1107 of the reference width, capped so tall displays keep the
    /// panel inside the safe area.
    var folderPanelHeight: CGFloat {
        min(size.width * 0.2963, size.height * 0.62)
    }

    var folderPanelCornerRadius: CGFloat { max(22, size.width * 0.027) }
    var folderNameFontSize: CGFloat { min(max(size.width * 0.0117, 15), 26) }

    /// Title sits above the panel (reference: 31 px gap at 1107 wide).
    var folderTitleGap: CGFloat { max(12, size.width * 0.014) }

    /// Inner grid padding: 42 px top and 14 px bottom at 1107 wide.
    var folderGridTop: CGFloat { size.width * 0.038 }
    var folderGridBottom: CGFloat { size.width * 0.0126 }
}
