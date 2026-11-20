import AppKit
import SwiftUI

/// The opened folder: dimmed grid behind a frosted panel with the folder's
/// applications. Clicking outside or pressing Escape closes it.
struct FolderView: View {
    let folder: AppFolder
    let apps: [AppItem]
    let metrics: LaunchpadMetrics
    let isEditing: Bool
    let draggingAppID: String?
    let isDraggingOut: Bool
    /// True for a folder that was just created: the name field takes focus and
    /// the suggested name is selected so typing replaces it.
    let promptsForName: Bool
    let onLaunch: (AppItem) -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onNamePromptShown: () -> Void
    let onAppDragChanged: (AppItem, CGPoint) -> Void
    let onAppDragEnded: (AppItem, CGPoint) -> Void
    let onPanelFrameChange: (CGRect) -> Void

    @State private var draftName: String
    @State private var appeared = false
    @FocusState private var isNameFocused: Bool

    init(
        folder: AppFolder,
        apps: [AppItem],
        metrics: LaunchpadMetrics,
        isEditing: Bool,
        draggingAppID: String?,
        isDraggingOut: Bool,
        promptsForName: Bool,
        onLaunch: @escaping (AppItem) -> Void,
        onClose: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onNamePromptShown: @escaping () -> Void,
        onAppDragChanged: @escaping (AppItem, CGPoint) -> Void,
        onAppDragEnded: @escaping (AppItem, CGPoint) -> Void,
        onPanelFrameChange: @escaping (CGRect) -> Void
    ) {
        self.folder = folder
        self.apps = apps
        self.metrics = metrics
        self.isEditing = isEditing
        self.draggingAppID = draggingAppID
        self.isDraggingOut = isDraggingOut
        self.promptsForName = promptsForName
        self.onLaunch = onLaunch
        self.onClose = onClose
        self.onRename = onRename
        self.onNamePromptShown = onNamePromptShown
        self.onAppDragChanged = onAppDragChanged
        self.onAppDragEnded = onAppDragEnded
        self.onPanelFrameChange = onPanelFrameChange
        _draftName = State(initialValue: folder.name)
    }

    var body: some View {
        ZStack {
            // Tap target that closes the folder. The dim itself is drawn by the
            // grid behind (see `LaunchpadView`), so that the menu-bar cover can
            // fade with it in step.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)

            VStack(spacing: metrics.folderTitleGap) {
                nameField
                panel
            }
            .scaleEffect(appeared ? 1 : 0.86)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.3, bounce: 0.12)) {
                appeared = true
            }
        }
        .onDisappear {
            commitName()
        }
        // While an app is dragged out of the folder the whole sheet fades away
        // so the grid behind is visible and can receive the drop.
        .opacity(isDraggingOut ? 0 : 1)
        .allowsHitTesting(!isDraggingOut)
        .animation(.easeOut(duration: 0.15), value: isDraggingOut)
        // Let the sheet finish zooming in before taking the keyboard, then
        // select the suggested name so typing replaces it.
        .task(id: promptsForName) {
            guard promptsForName else { return }
            try? await Task.sleep(for: .milliseconds(150))
            isNameFocused = true
            try? await Task.sleep(for: .milliseconds(120))
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            onNamePromptShown()
        }
    }

    private var nameField: some View {
        ZStack {
            if draftName.isEmpty {
                Text("Folder")
                    .font(.system(size: metrics.folderNameFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            TextField("", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: metrics.folderNameFontSize, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .focused($isNameFocused)
                .onSubmit(commitName)
                // The folder sheet always sits on the wallpaper: keep the field
                // editor dark so light mode cannot render its text in black.
                .environment(\.colorScheme, .dark)
                .accessibilityLabel(Text("Folder name"))
        }
        .frame(width: metrics.folderPanelWidth * 0.5, height: 30)
    }

    private var panel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.folderPanelCornerRadius, style: .continuous)
                .fill(.white.opacity(0.11))

            folderGrid
        }
        .frame(width: metrics.folderPanelWidth, height: metrics.folderPanelHeight)
        // The opened folder is the same clear glass as its resting tile and its
        // lifted plate, so the surface does not change material when it opens.
        // Glass sits behind the panel's own content, keeping the app grid crisp
        // instead of sampling it as backdrop.
        .glassEffect(
            .clear,
            in: RoundedRectangle(cornerRadius: metrics.folderPanelCornerRadius, style: .continuous)
        )
        .overlay {
            GlassRim(cornerRadius: metrics.folderPanelCornerRadius, intensity: 0.8)
        }
        .contentShape(
            RoundedRectangle(cornerRadius: metrics.folderPanelCornerRadius, style: .continuous)
        )
        .onTapGesture {
            // Keeps clicks on the panel from reaching the dimmed backdrop.
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(LaunchpadCanvas.space))
        } action: { frame in
            onPanelFrameChange(frame)
        }
    }

    private var folderGrid: some View {
        let iconSize: CGFloat = metrics.folderIconSize
        let columnPitch: CGFloat = metrics.folderPanelWidth / CGFloat(metrics.folderColumns)
        let gridTop: CGFloat = metrics.folderGridTop
        let bottom: CGFloat = metrics.folderGridBottom
        let rowPitch: CGFloat = (metrics.folderPanelHeight - gridTop - bottom) / CGFloat(metrics.folderRows)
        let labelFont: CGFloat = max(11, metrics.labelFontSize * 0.9)
        let labelWidth: CGFloat = columnPitch - 12

        return ZStack(alignment: .topLeading) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                let column = index % metrics.folderColumns
                let row = index / metrics.folderColumns
                if row < metrics.folderRows {
                    FolderAppIcon(
                        item: app,
                        iconSize: iconSize,
                        labelFontSize: labelFont,
                        labelWidth: labelWidth,
                        artworkScale: metrics.iconArtworkScale,
                        isEditing: isEditing,
                        isDragging: draggingAppID == app.id,
                        wiggleSeed: Double(index),
                        onLaunch: { onLaunch(app) },
                        onDragChanged: { location in onAppDragChanged(app, location) },
                        onDragEnded: { location in onAppDragEnded(app, location) }
                    )
                    .position(
                        x: columnPitch * (CGFloat(column) + 0.5),
                        y: gridTop + rowPitch * (CGFloat(row) + 0.5)
                    )
                }
            }
        }
        .frame(width: metrics.folderPanelWidth, height: metrics.folderPanelHeight, alignment: .topLeading)
        // Reordering inside the folder animates the remaining icons into their
        // new slots, so the gap under the pointer moves with the drag.
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: apps.map(\.id))
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        onRename(trimmed)
    }
}

/// An icon inside an opened folder: smaller than the grid icons and without
/// editing affordances — but it still jiggles with the grid in edit mode.
private struct FolderAppIcon: View {
    let item: AppItem
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    let labelWidth: CGFloat
    let artworkScale: CGFloat
    let isEditing: Bool
    let isDragging: Bool
    /// Per-icon seed for the edit-mode jiggle (see `IconWiggle`).
    let wiggleSeed: Double
    let onLaunch: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void

    private var wiggle: IconWiggle.Motion {
        IconWiggle.motion(seed: wiggleSeed)
    }

    /// Timeline-driven wobble; 0° whenever edit mode is off.
    private func jiggleAngle(_ date: Date) -> Double {
        isEditing ? IconWiggle.angle(at: date, motion: wiggle) : 0
    }

    private func jiggleBounce(_ date: Date) -> CGFloat {
        isEditing ? IconWiggle.offset(at: date, motion: wiggle) : 0
    }

    var body: some View {
        VStack(spacing: max(6, iconSize * 0.17)) {
            TimelineView(
                .animation(
                    minimumInterval: 1.0 / IconWiggle.framesPerSecond,
                    paused: !isEditing
                )
            ) { context in
                AppIconImage(item: item, size: iconSize, artworkScale: artworkScale)
                    .frame(width: iconSize, height: iconSize)
                    .rotationEffect(.degrees(jiggleAngle(context.date)), anchor: wiggle.anchor)
                    .offset(y: jiggleBounce(context.date))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onLaunch)
            .simultaneousGesture(
                DragGesture(
                    minimumDistance: 5,
                    coordinateSpace: .named(LaunchpadCanvas.space)
                )
                .onChanged { onDragChanged($0.location) }
                .onEnded { onDragEnded($0.location) }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onLaunch() }

            Text(item.name)
                .font(.system(size: labelFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: .black.opacity(0.55), radius: 2.5, y: 1)
                .frame(width: labelWidth, height: metricsLabelHeight)
                .accessibilityHidden(true)
        }
        // The tile is represented by the floating drag preview: the whole cell,
        // name included, disappears so the live gap is completely empty.
        .opacity(isDragging ? 0 : 1)
    }

    private var metricsLabelHeight: CGFloat {
        max(14, labelFontSize * 1.3)
    }
}
