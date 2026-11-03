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
    /// Any item currently under the pointer during a drag. Shows a folder
    /// preview containing this tile's apps so the user can see what the drop
    /// would land on.
    let isMergeTarget: Bool
    /// The hovered target after the dwell delay. Turns the tile into the
    /// folder-creation affordance (folder preview / folder glass).
    var isMergeArmed: Bool = false
    /// The apps to draw in the hovered folder preview. The dragged app floats
    /// above the grid already, so this only holds apps already in the target.
    var mergePreviewApps: [AppItem]? = nil
    /// Only the current page animates its wiggle. Driving this from the page
    /// instead of `isEditing` keeps off-screen pages static.
    var jiggleActive: Bool = false
    /// Shared wiggle half-cycle toggled by the page. A tile inserted while edit
    /// mode is already running (an app dropped out of a folder) can inherit a
    /// stale `@State` and a dead repeating animation from a previous placement,
    /// so the swing has to be driven by a value the tile does not own.
    var jigglePhase: Bool = false
    /// The tile currently being dragged. Its content is replaced by an empty
    /// placeholder rather than faded with opacity: the Liquid Glass layer draws
    /// in its own compositing pass that ignores an ancestor's opacity, so a
    /// faded folder still left a second ghost sliding around the grid.
    var isDragSource: Bool = false
    let reduceMotion: Bool
    let showDeleteBadge: Bool
    /// Whether the tile draws a drop shadow. Off gives a completely flat icon
    /// for wallpapers where the default shadow looks muddy.
    var showIconShadow: Bool = true
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

    @State private var isPressed = false

    private var isFolder: Bool { entry.isFolder }

    var body: some View {
        jiggleAnimatedContent
            .rotationEffect(.degrees(jiggleActive ? (swing ? Metrics.jiggleAngle : -Metrics.jiggleAngle) : 0))
            .offset(y: jiggleActive ? (swing ? Metrics.jiggleTranslation : -Metrics.jiggleTranslation) : 0)
            .animation(.easeInOut(duration: jiggleHalfPeriod), value: swing)
            .animation(.easeOut(duration: Metrics.Durations.jiggleReturn), value: jiggleActive)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(pointerGesture)
            .contextMenu { contextMenu }
            .onDisappear {
                longPressTask?.cancel()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.displayName)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Open", comment: "Accessibility action")) { onTap() }
    }

    /// Split the grid into two groups that swing in opposite directions, so the
    /// page does not wiggle in lockstep. The value is derived from the shared
    /// page phase, never stored locally.
    private var swing: Bool {
        jigglePhase != (abs(entry.id.hashValue) % 2 == 0)
    }

    /// A small per-tile duration variation keeps the two groups from settling
    /// into an exact mirror rhythm.
    private var jiggleHalfPeriod: Double {
        let seed = Double(abs(entry.id.hashValue % 100)) / 100
        return Metrics.Durations.jiggle + seed * 0.02
    }

    /// Rasterizes an app tile into a single texture before the wiggle rotates
    /// it. Without this, every tile re-blurred its icon shadow and re-rendered
    /// its label text on every frame, which is what made edit mode stutter.
    ///
    /// Folder tiles stay live: Liquid Glass samples the desktop behind the tile
    /// and cannot be flattened into a static texture.
    @ViewBuilder
    private var jiggleAnimatedContent: some View {
        // The merge preview draws a folder with a material inside it. Nesting
        // that in `drawingGroup` forces an offscreen pass over a live material
        // every wiggle frame, which stalled the main thread exactly when the
        // folder appeared under the cursor. Those tiles render live instead.
        let rasterizable = jiggleActive
            && !isFolder
            && !reduceMotion
            && !isMergeTarget
            && !isMergeArmed
        if rasterizable {
            content
                .padding(rasterPadding)
                .drawingGroup()
                .padding(-rasterPadding)
        } else {
            content
        }
    }

    /// Transparent margin baked into the rasterized tile. The delete badge and
    /// the icon shadow extend past the tile frame, so rasterizing without it
    /// clipped the badge in edit mode.
    private var rasterPadding: CGFloat {
        (Metrics.deleteBadgeOffset + Metrics.iconShadowRadius + 4) * scale
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
                iconContent
                    .frame(width: iconSize, height: iconSize)
                    .background(frameReporter)
                    .scaleEffect(tileScale)
                    .brightness(isPressed ? Metrics.iconPressedBrightness : 0)
                    .shadow(
                        color: showIconShadow
                            ? .black.opacity(isPressed ? 0.25 : Metrics.iconShadowOpacity)
                            : .clear,
                        radius: showIconShadow ? Metrics.iconShadowRadius * scale : 0,
                        x: 0,
                        y: showIconShadow ? Metrics.iconShadowY * scale : 0
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
                .opacity(isMergeArmed && !isFolder ? 0 : 1)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isMergeTarget)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isMergeArmed)
        .animation(Metrics.Motion.pressed, value: isPressed)
    }

    @ViewBuilder
    private var iconContent: some View {
        if isDragSource {
            // The glass layer draws in its own compositing pass and ignores an
            // ancestor's opacity, so the source tile must not build the folder
            // view at all. Only this leaf is swapped; the gesture lives on the
            // enclosing view, so the drag keeps running.
            Color.clear
        } else if let mergePreviewApps, isMergeTarget || isMergeArmed {
            // Morph the app into the folder the drop would create. Only the
            // target's own apps are drawn here; the app being dragged is
            // already floating above the grid under the cursor.
            FolderIconContent(
                apps: mergePreviewApps,
                iconSize: iconSize,
                scale: scale,
                isJiggling: jiggleActive,
                usesPlainSurface: true
            )
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        } else if let folder = entry.folder {
            FolderIconContent(
                folder: folder,
                iconSize: iconSize,
                scale: scale,
                isJiggling: jiggleActive
            )
        } else if let app = entry.app {
            AppIconImage(path: app.filePath, size: iconSize, fallbackName: app.name)
        }
    }

    private var tileScale: CGFloat {
        if isMergeArmed {
            return 1.08
        }
        if isMergeTarget {
            // The folder preview is already a clear acknowledgement; a small
            // lift keeps it feeling attached to the cursor.
            return 1.04
        }
        let pressed: CGFloat = isPressed ? Metrics.iconPressedScale : 1
        return pressed
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
    @State private var longPressTask: Task<Void, Never>?
    @State private var pendingFolderClick: DispatchWorkItem?
    @State private var lastPointerEventTime = Date.distantPast

    /// A single pointer gesture handles press feedback, long-press intent,
    /// dragging, and clicks.
    ///
    /// Competing gesture recognizers are the classic reason a macOS SwiftUI
    /// tile "ignores" clicks: a `DragGesture(minimumDistance: 0)` attached for
    /// pressed-state feedback wins the arbitration and the tap never fires. One
    /// gesture that measures travel itself cannot lose that race.
    ///
    /// Long press is folded into the same gesture instead of using a separate
    /// `LongPressGesture`. Two recognizers on one tile could fight mid-drag:
    /// once the press timer elapsed SwiftUI re-arbitrated the gestures and the
    /// in-flight drag silently stopped receiving pointer updates, which left
    /// the floating icon frozen under the cursor.
    private var pointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("launchpad"))
            .onChanged { value in
                // A cancelled drag can end without ever calling `onEnded`,
                // which used to leave this flag stuck on and made the tile
                // ignore every later drag. If the view model no longer treats
                // this tile as the source and the pointer was quiet for a
                // moment, this is a fresh press: recover.
                if isDraggingGestureActive,
                   !isDragSource,
                   value.time.timeIntervalSince(lastPointerEventTime) > 0.25 {
                    isDraggingGestureActive = false
                }
                lastPointerEventTime = value.time
                if !isPressed {
                    isPressed = true
                    beginLongPressCountdown()
                }

                if !isDraggingGestureActive {
                    let distance = hypot(value.translation.width, value.translation.height)
                    guard distance >= Metrics.itemDragThreshold else { return }
                    cancelLongPressCountdown()
                    isDraggingGestureActive = true
                    onDragBegan()
                }
                onDragChanged(value.location)
            }
            .onEnded { value in
                isPressed = false
                cancelLongPressCountdown()
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

    private func beginLongPressCountdown() {
        didLongPress = false
        longPressTask?.cancel()
        longPressTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Metrics.Durations.longPress))
            guard !Task.isCancelled, isPressed, !isDraggingGestureActive else { return }
            didLongPress = true
            onLongPress()
        }
    }

    private func cancelLongPressCountdown() {
        longPressTask?.cancel()
        longPressTask = nil
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

/// The 3 × 3 miniature preview drawn inside a folder tile. Styled after the
/// frosted glass square macOS uses for Launchpad folders.
struct FolderIconContent: View {
    let apps: [AppItem]
    let iconSize: CGFloat
    let scale: CGFloat
    /// Uses a still material instead of live Liquid Glass while the tile is
    /// rotating in edit mode. Live glass cannot rotate smoothly.
    var isJiggling: Bool = false
    /// Draws the folder with plain shapes only. Used for the transient merge
    /// preview: inserting a material/glass-backed view under an in-flight drag
    /// cancels the gesture, so the preview must not create one.
    var usesPlainSurface: Bool = false

    init(folder: FolderItem, iconSize: CGFloat, scale: CGFloat, isJiggling: Bool = false) {
        self.init(apps: folder.apps, iconSize: iconSize, scale: scale, isJiggling: isJiggling)
    }

    init(
        apps: [AppItem],
        iconSize: CGFloat,
        scale: CGFloat,
        isJiggling: Bool = false,
        usesPlainSurface: Bool = false
    ) {
        self.apps = apps
        self.iconSize = iconSize
        self.scale = scale
        self.isJiggling = isJiggling
        self.usesPlainSurface = usesPlainSurface
    }

    private var cornerRadius: CGFloat { Metrics.iconCornerRadius * scale }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tint = Metrics.glassTintSoft.color(for: colorScheme)
        let base = ZStack {
            Color.clear
            preview
                .padding(Metrics.folderPreviewPadding * scale)
        }
        .frame(width: iconSize, height: iconSize)

        surface(base, shape: shape, tint: tint)
            .animation(Metrics.Motion.folder, value: apps.count)
    }

    @ViewBuilder
    private func surface<S: Shape>(_ base: some View, shape: S, tint: Color) -> some View {
        if usesPlainSurface {
            base.plainGlass(tint: tint, in: shape)
        } else if isJiggling {
            base.stillGlass(tint: tint, in: shape)
        } else {
            base.liquidGlass(.regular.tint(tint), in: shape)
        }
    }

    private var preview: some View {
        let padding = Metrics.folderPreviewPadding * scale
        let available = max(1, iconSize - padding * 2)
        let gap = max(1, 2.5 * scale)
        let mini = max(6, (available - gap * 2) / 3)
        let miniRadius = mini * 0.22
        let visibleApps = Array(apps.prefix(9))

        return VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        if visibleApps.indices.contains(index) {
                            AppIconImage(
                                path: visibleApps[index].filePath,
                                size: mini,
                                fallbackName: visibleApps[index].name
                            )
                            .id(visibleApps[index].id)
                            .frame(width: mini, height: mini)
                            .clipShape(RoundedRectangle(cornerRadius: miniRadius, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 0.6 * scale, y: 0.5 * scale)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
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
