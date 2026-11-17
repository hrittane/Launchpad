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

    static let defaultColumns = 7
    static let defaultRows = 5

    var pageCapacity: Int { columns * rows }

    // MARK: Grid

    /// 59 px at 1107 wide (5.33 % of width).
    ///
    /// This is the *visible* squircle. `NSWorkspace` icons are full 1024 px
    /// canvases whose artwork occupies ~824 px, so the image is drawn larger and
    /// then clipped back to this footprint.
    var iconSize: CGFloat {
        min(max(size.width * 0.0533, 52), 118)
    }

    /// 1024 / 824 — macOS app icon artwork inset inside its canvas.
    var iconArtworkScale: CGFloat { 1.243 }

    /// 138.33 px at 1107 wide (12.49 % of width).
    var columnPitch: CGFloat {
        guard size.width > 0 else { return 0 }
        return size.width * 0.1249
    }

    /// 107.5 px at 720 high (14.93 % of height).
    var rowPitch: CGFloat {
        size.height * 0.1493
    }

    /// First icon's top edge: 94 px at 720 high (13.06 % of height).
    var gridTop: CGFloat {
        size.height * 0.1306
    }

    var labelGap: CGFloat {
        max(9, iconSize * 0.22)
    }

    var labelHeight: CGFloat {
        max(16, min(size.width * 0.0152, 22))
    }

    /// Reference labels are ~10 px tall at 1107 wide (≈17 pt at 1920).
    var labelFontSize: CGFloat {
        min(max(size.width * 0.00885, 12), 18)
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
