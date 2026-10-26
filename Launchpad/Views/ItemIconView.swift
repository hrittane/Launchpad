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
        TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !jiggleActive)) { context in
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
        .simultaneousGesture(pressGesture)
        .simultaneousGesture(longPressGesture)
        .onTapGesture {
            guard !isDraggingGestureActive else { return }
            onTap()
        }
        .modifier(FolderDoubleTap(enabled: isFolder, action: { onDoubleTap?() }))
        .gesture(dragGesture)
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
            ZStack(alignment: .topLeading) {
                if isMergeTarget {
                    RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * scale, style: .continuous)
                        .fill(Color.white.opacity(0.24))
                        .frame(width: iconSize, height: iconSize)
                        .scaleEffect(1.18)
                        .transition(.opacity)
                }

                iconContent
                    .frame(width: iconSize, height: iconSize)
                    .background(frameReporter)
                    .scaleEffect(tileScale)
                    .brightness(isPressed ? Metrics.iconPressedBrightness : 0)
                    .shadow(
                        color: .black.opacity(isPressed ? 0.25 : Metrics.iconShadowOpacity),
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
                            RoundedRectangle(cornerRadius: Metrics.focusRingCornerRadius * scale, style: .continuous)
                                .stroke(
                                    Color.white.opacity(Metrics.focusRingOpacity),
                                    lineWidth: Metrics.focusRingWidth * scale
                                )
                                .padding(-4 * scale)
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
        }
        .animation(isMergeTarget ? .easeInOut(duration: 0.3).repeatForever(autoreverses: true) : Metrics.Motion.hover, value: isMergeTarget)
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
        let hover: CGFloat = isHovered && !isEditing && !isMergeTarget ? Metrics.iconHoverScale : 1
        let pressed: CGFloat = isPressed ? Metrics.iconPressedScale : 1
        let merge: CGFloat = isMergeTarget ? 1.15 : 1
        return hover * pressed * merge
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("launchpad"))
            .onChanged { value in
                if !isDraggingGestureActive {
                    isDraggingGestureActive = true
                    onDragBegan()
                }
                onDragChanged(value.location)
            }
            .onEnded { _ in
                guard isDraggingGestureActive else { return }
                isDraggingGestureActive = false
                onDragEnded()
            }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("launchpad"))
            .onChanged { _ in isPressed = true }
            .onEnded { _ in isPressed = false }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: Metrics.Durations.longPress)
            .onEnded { _ in
                guard !isDraggingGestureActive else { return }
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

/// Attaches a double-click recognizer only to folder tiles. Keeping it off app
/// tiles avoids delaying their single-click launch while SwiftUI waits for a
/// possible second click.
private struct FolderDoubleTap: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture(count: 2, perform: action)
        } else {
            content
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
