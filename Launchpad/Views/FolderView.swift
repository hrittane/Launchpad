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
    let onLaunch: (AppItem) -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
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
        onLaunch: @escaping (AppItem) -> Void,
        onClose: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
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
        self.onLaunch = onLaunch
        self.onClose = onClose
        self.onRename = onRename
        self.onAppDragChanged = onAppDragChanged
        self.onAppDragEnded = onAppDragEnded
        self.onPanelFrameChange = onPanelFrameChange
        _draftName = State(initialValue: folder.name)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
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
    }

    private var nameField: some View {
        TextField("Folder", text: $draftName)
            .textFieldStyle(.plain)
            .font(.system(size: metrics.folderNameFontSize, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .focused($isNameFocused)
            .onSubmit(commitName)
            .frame(width: metrics.folderPanelWidth * 0.5, height: 30)
            .accessibilityLabel(Text("Folder name"))
    }

    private var panel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.folderPanelCornerRadius, style: .continuous)
                .fill(.white.opacity(0.08))

            folderGrid
        }
        .frame(width: metrics.folderPanelWidth, height: metrics.folderPanelHeight)
        // Glass behind the panel's own content: the app grid stays crisp
        // instead of being sampled as backdrop by the glass layer.
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: metrics.folderPanelCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: metrics.folderPanelCornerRadius,
                style: .continuous
            )
            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
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
                        wigglePhase: Double(index % 3),
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
    let wigglePhase: Double
    let onLaunch: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void

    /// Timeline-driven wobble; 0° whenever edit mode is off.
    private func jiggleAngle(_ date: Date) -> Double {
        guard isEditing else { return 0 }
        let period = 0.3 + wigglePhase * 0.06
        let phase = date.timeIntervalSinceReferenceDate * 2 * .pi / period
        return sin(phase) * 1.2
    }

    var body: some View {
        VStack(spacing: max(6, iconSize * 0.17)) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isEditing)) { context in
                AppIconImage(item: item, size: iconSize, artworkScale: artworkScale)
                    .frame(width: iconSize, height: iconSize)
                    .rotationEffect(.degrees(jiggleAngle(context.date)), anchor: .center)
            }
            .opacity(isDragging ? 0.3 : 1)
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
    }

    private var metricsLabelHeight: CGFloat {
        max(14, labelFontSize * 1.3)
    }
}
