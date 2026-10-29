import AppKit
import SwiftUI

enum ItemContextAction {
    case open
    case showInFinder
    case removeFolder(UUID)
    case getInfo
    case renameFolder(UUID)
}

/// A single app or folder tile used by both the main grid and the folder panel.
struct ItemIconView: View {
    let entry: LaunchpadEntry
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    let labelMaxWidth: CGFloat
    let scale: CGFloat
    let isEditing: Bool
    let isFocused: Bool
    let isMergeTarget: Bool
    let reduceMotion: Bool
    let showDeleteBadge: Bool
    let recordsFrame: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onLongPress: () -> Void
    let onDragBegan: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void
    let onContextAction: (ItemContextAction) -> Void
    /// Optional second-click action, used by folder tiles to open the panel and
    /// immediately focus the folder title for renaming.
    var onDoubleTap: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var phase = Double.random(in: 0..<(2 * .pi))

    private var isFolder: Bool { entry.isFolder }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !jiggleActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let period = 0.26
            let angle = jiggleActive ? sin(time * 2 * .pi / period + phase) * Metrics.jiggleAngle : 0
            let vertical = jiggleActive ? sin(time * 2 * .pi / period + phase) * Metrics.jiggleTranslation : 0

            content
                .rotationEffect(.degrees(angle))
                .offset(y: vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .gesture(pointerGesture)
        .simultaneousGesture(longPressGesture)
        .contextMenu { contextMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.displayName)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open", comment: "Accessibility action")) { onTap() }
    }

    private var jiggleActive: Bool {
        isEditing && !reduceMotion
    }

    private var accessibilityHint: String {
        if isFolder {
            return String(localized: "Opens the folder", comment: "Accessibility hint")
        }
        return String(localized: "Opens the application", comment: "Accessibility hint")
    }

    private var content: some View {
        VStack(spacing: Metrics.labelSpacing * scale) {
            ZStack(alignment: .center) {
                if isMergeTarget {
                    if isFolder {
                        RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * scale, style: .continuous)
                            .stroke(Color.white.opacity(0.7), lineWidth: 2.5 * scale)
                            .frame(width: iconSize * 1.08, height: iconSize * 1.08)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * scale, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * scale, style: .continuous)
                                .fill(Color.white.opacity(0.24))
                            RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * scale, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        }
                        .frame(width: iconSize, height: iconSize)
                        .shadow(color: .black.opacity(0.35), radius: 8 * scale, y: 4 * scale)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }

                iconContent
                    .frame(width: iconSize, height: iconSize)
                    .background(frameReporter)
                    .scaleEffect(tileScale)
                    .brightness(isPressed ? Metrics.iconPressedBrightness : 0)
                    .shadow(
                        color: .black.opacity(isPressed ? 0.25 : (isMergeTarget && !isFolder ? 0 : Metrics.iconShadowOpacity)),
                        radius: Metrics.iconShadowRadius * scale,
                        x: 0,
                        y: Metrics.iconShadowY * scale
                    )
                    .overlay(alignment: .topLeading) {
                        if isEditing && showDeleteBadge {
                            deleteBadge
                                .offset(
                                    x: -Metrics.deleteBadgeOffset * scale,
                                    y: -Metrics.deleteBadgeOffset * scale
                                )
                        }
                    }
                    .overlay {
                        if isFocused {
                            // Focus ring only shown for keyboard navigation
                        }
                    }
            }

            Text(entry.displayName)
                .font(.system(size: labelFontSize, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(Metrics.labelMaxLines)
                .truncationMode(.tail)
                .shadow(
                    color: .black.opacity(Metrics.labelShadowOpacity),
                    radius: Metrics.labelShadowRadius,
                    x: 0,
                    y: Metrics.labelShadowY
                )
                .frame(maxWidth: labelMaxWidth, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(isMergeTarget && !isFolder ? 0 : 1)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isMergeTarget)
        .animation(Metrics.Motion.hover, value: isHovered)
        .animation(Metrics.Motion.pressed, value: isPressed)
    }

    @ViewBuilder
    private var iconContent: some View {
        if let folder = entry.folder {
            FolderIconContent(folder: folder, iconSize: iconSize, scale: scale)
        } else if let app = entry.app {
            AppIconImage(path: app.filePath, size: iconSize, fallbackName: app.name)
        }
    }

    private var tileScale: CGFloat {
        if isMergeTarget {
            if isFolder {
                return 1.08
            } else {
                return 0.40
            }
        }
        let hover: CGFloat = isHovered && !isEditing ? Metrics.iconHoverScale : 1
        let pressed: CGFloat = isPressed ? Metrics.iconPressedScale : 1
        return hover * pressed
    }

    private var deleteBadge: some View {
        Button(action: onDelete) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.9))
                Image(systemName: "xmark")
                    .font(.system(size: 10 * scale, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.8))
            }
            .frame(width: Metrics.deleteBadgeSize * scale, height: Metrics.deleteBadgeSize * scale)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Remove from Launchpad", comment: "Delete badge accessibility label"))
    }

    @ViewBuilder
    private var frameReporter: some View {
        if recordsFrame {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: IconFramePreferenceKey.self,
                    value: [entry.id: proxy.frame(in: .named("launchpad"))]
                )
            }
        } else {
            Color.clear
        }
    }

    @State private var isDraggingGestureActive = false
    @State private var didLongPress = false
    @State private var pendingFolderClick: DispatchWorkItem?

    /// A single pointer gesture handles press feedback, dragging, and clicks.
    ///
    /// Competing gesture recognizers are the classic reason a macOS SwiftUI
    /// tile "ignores" clicks: a `DragGesture(minimumDistance: 0)` attached for
    /// pressed-state feedback wins the arbitration and the tap never fires. One
    /// gesture that measures travel itself cannot lose that race.
    private var pointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("launchpad"))
            .onChanged { value in
                if !isPressed {
                    isPressed = true
                    didLongPress = false
                }

                if !isDraggingGestureActive {
                    let distance = hypot(value.translation.width, value.translation.height)
                    guard distance >= Metrics.itemDragThreshold else { return }
                    isDraggingGestureActive = true
                    onDragBegan()
                }
                onDragChanged(value.location)
            }
            .onEnded { value in
                isPressed = false
                if isDraggingGestureActive {
                    isDraggingGestureActive = false
                    onDragEnded()
                    return
                }
                if didLongPress {
                    didLongPress = false
                    return
                }
                let distance = hypot(value.translation.width, value.translation.height)
                guard distance < Metrics.itemDragThreshold else { return }
                handleClick()
            }
    }

    /// Folders open on a single click, but the first click is held for the
    /// double-click interval so a second click can edit the title instead.
    private func handleClick() {
        guard isFolder, let onDoubleTap else {
            onTap()
            return
        }

        if let pending = pendingFolderClick {
            pending.cancel()
            pendingFolderClick = nil
            onDoubleTap()
            return
        }

        let work = DispatchWorkItem {
            pendingFolderClick = nil
            onTap()
        }
        pendingFolderClick = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Metrics.Durations.folderDoubleClick,
            execute: work
        )
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: Metrics.Durations.longPress)
            .onEnded { _ in
                guard !isDraggingGestureActive else { return }
                didLongPress = true
                onLongPress()
            }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button {
            onContextAction(.open)
        } label: {
            Text("Open", comment: "Context menu")
        }

        if let app = entry.app {
            Button {
                onContextAction(.showInFinder)
            } label: {
                Text("Show in Finder", comment: "Context menu")
            }
            Button {
                onContextAction(.getInfo)
            } label: {
                Text("Get Info", comment: "Context menu")
            }
            if app.isDeletable {
                Divider()
                Button {
                    onDelete()
                } label: {
                    Text("Remove from Launchpad", comment: "Context menu")
                }
            }
        }

        if let folder = entry.folder {
            Button {
                onContextAction(.renameFolder(folder.id))
            } label: {
                Text("Rename Folder", comment: "Context menu")
            }
            Divider()
            Button(role: .destructive) {
                onContextAction(.removeFolder(folder.id))
            } label: {
                Text("Remove from Launchpad", comment: "Context menu")
            }
        }
    }
}

/// Aggregates icon frames reported from the grid. Only the interactive window
/// records frames, so mirrored displays cannot overwrite hit-testing data.
struct IconFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// The 3 × 3 miniature preview drawn inside a folder tile.
struct FolderIconContent: View {
    let folder: FolderItem
    let iconSize: CGFloat
    let scale: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * scale, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * scale, style: .continuous)
                .fill(Color.white.opacity(0.22))
            preview
                .padding(Metrics.folderPreviewPadding * scale)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * scale, style: .continuous))
    }

    private var preview: some View {
        let padding = Metrics.folderPreviewPadding * scale
        let available = max(1, iconSize - padding * 2)
        let gap = max(1, 3 * scale)
        let mini = max(6, (available - gap * 2) / 3)
        let apps = Array(folder.apps.prefix(9))

        return VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        if apps.indices.contains(index) {
                            AppIconImage(
                                path: apps[index].filePath,
                                size: mini,
                                fallbackName: apps[index].name
                            )
                            .frame(width: mini, height: mini)
                        } else {
                            Color.clear.frame(width: mini, height: mini)
                        }
                    }
                }
            }
        }
        .frame(width: available, height: available)
    }
}

/// Floating icon that follows the cursor while dragging.
struct DragPreview: View {
    let entry: LaunchpadEntry
    let iconSize: CGFloat
    let scale: CGFloat
    let location: CGPoint

    var body: some View {
        ZStack {
            if let folder = entry.folder {
                FolderIconContent(folder: folder, iconSize: iconSize, scale: scale)
            } else if let app = entry.app {
                AppIconImage(path: app.filePath, size: iconSize, fallbackName: app.name)
            }
        }
        .frame(width: iconSize, height: iconSize)
        .scaleEffect(1.12)
        .shadow(color: .black.opacity(0.45), radius: 14 * scale, x: 0, y: 8 * scale)
        .position(x: location.x, y: location.y)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
