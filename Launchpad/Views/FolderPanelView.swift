import AppKit
import SwiftUI

/// The opened-folder panel. It expands from the folder tile's frame, blurs the
/// grid behind it (handled by the root), and supports reordering, paging, and
/// dragging an app back out onto the main grid.
struct FolderPanelView: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    let folder: FolderItem
    let metrics: FolderMetrics
    let panelFrame: CGRect
    let anchor: CGRect
    let isPresented: Bool

    @FocusState private var titleIsFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var startScale: CGFloat {
        guard anchor.width > 1 else { return 0.35 }
        return max(0.05, anchor.width / max(1, panelFrame.width))
    }

    private var startPoint: CGPoint {
        if anchor == .zero {
            return CGPoint(x: panelFrame.midX, y: panelFrame.midY)
        }
        return CGPoint(x: anchor.midX, y: anchor.midY)
    }

    private var endPoint: CGPoint {
        CGPoint(x: panelFrame.midX, y: panelFrame.midY)
    }

    private var panelCornerRadius: CGFloat {
        Metrics.folderPanelCornerRadius * metrics.scale
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
    }

    var body: some View {
        panelContent
            .frame(width: panelFrame.width, height: panelFrame.height)
            .background {
                // The clear interaction layer sits behind the panel content, so
                // swiping empty space pages the folder without stealing drags
                // from icons or the title field.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(folderSwipeGesture)
            }
            .liquidGlass(
                .regular.tint(Metrics.glassTintPanel.color(for: colorScheme)),
                in: panelShape
            )
            .scaleEffect(isPresented ? 1 : startScale)
            .position(isPresented ? endPoint : startPoint)
            .animation(panelAnimation, value: isPresented)
            .onAppear {
                // Present on the next run-loop turn, after this collapsed frame
                // has been committed. Presenting earlier made the panel appear
                // at full size with no zoom.
                DispatchQueue.main.async {
                    viewModel.presentFolder()
                }
            }
            .onChange(of: viewModel.folderFocusToken) { _, _ in
                guard viewModel.folderTitleEditing else { return }
                focusAndSelectTitle()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(folder.name)
    }

    private var panelAnimation: Animation {
        viewModel.reduceMotion ? Metrics.Motion.reduced : Metrics.Motion.folder
    }

    private var panelContent: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}

            title
                .frame(width: panelFrame.width - 100 * metrics.scale, height: 38 * metrics.scale)
                .position(x: panelFrame.width / 2, y: 38 * metrics.scale)

            folderPages

            if viewModel.folderPageCount > 1 && isPresented {
                PageDots(
                    pageCount: viewModel.folderPageCount,
                    currentPage: viewModel.currentFolderPage,
                    diameter: Metrics.folderPageDotDiameter * metrics.scale,
                    spacing: 10 * metrics.scale,
                    onSelect: { page in
                        viewModel.goToFolderPage(page)
                    }
                )
                .position(
                    x: panelFrame.width / 2,
                    y: panelFrame.height - 22 * metrics.scale
                )
            }
        }
        .frame(width: panelFrame.width, height: panelFrame.height, alignment: .topLeading)
    }

    @ViewBuilder
    private var title: some View {
        if viewModel.folderTitleEditing {
            TextField("", text: $viewModel.folderTitleDraft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: Metrics.folderTitleFontSize * metrics.scale, weight: .regular))
                .foregroundStyle(.white)
                .padding(.horizontal, 16 * metrics.scale)
                .padding(.vertical, 4 * metrics.scale)
                .focused($titleIsFocused)
                .onSubmit {
                    viewModel.commitFolderRename()
                }
                .onExitCommand {
                    // Escape abandons the edit and restores the old name.
                    titleIsFocused = false
                    viewModel.cancelFolderRename()
                }
                .onChange(of: titleIsFocused) { _, focused in
                    // Clicking anywhere else commits, like Launchpad's folder
                    // title field. A focus loss during the opening zoom is
                    // transient, so wait a moment before committing.
                    guard !focused, viewModel.folderTitleEditing else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        guard viewModel.folderTitleEditing, !titleIsFocused else { return }
                        viewModel.commitFolderRename()
                    }
                }
                .accessibilityLabel(Text("Folder name", comment: "Folder title field accessibility label"))
        } else {
            Text(folder.name)
                .font(.system(size: Metrics.folderTitleFontSize * metrics.scale, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12 * metrics.scale)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.beginFolderRename()
                }
                .help(Text("Click to rename", comment: "Folder title tooltip"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    viewModel.beginFolderRename()
                }
        }
    }

    private var folderPages: some View {
        let pages = viewModel.folderPages
        let current = viewModel.currentFolderPage
        let visible = visiblePageIndices(current: current, count: pages.count)

        return ZStack(alignment: .topLeading) {
            ForEach(visible, id: \.self) { pageIndex in
                folderPageView(
                    entries: pages[pageIndex],
                    pageIndex: pageIndex,
                    isCurrent: pageIndex == current
                )
                .offset(
                    x: CGFloat(pageIndex - current) * panelFrame.width
                )
            }
        }
        .frame(width: panelFrame.width, height: panelFrame.height, alignment: .topLeading)
        .modifier(PageDragOffsetModifier(state: viewModel.folderDrag))
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private func folderPageView(entries: PageLayout, pageIndex: Int, isCurrent: Bool) -> some View {
        let preview = folderDragPreview(for: entries, isCurrent: isCurrent)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let slot = preview?.slots[entry.id] ?? index
                let cell = metrics.cellRect(at: slot)
                let isDragSource = viewModel.folderDragSession?.app.id == entry.app?.id

                ItemIconView(
                    entry: entry,
                    iconSize: metrics.iconSize,
                    labelFontSize: metrics.labelFontSize,
                    labelMaxWidth: max(1, metrics.cellRect(at: 0).width - 6 * metrics.scale),
                    scale: metrics.scale,
                    isEditing: false,
                    isFocused: viewModel.focusedEntryID == entry.id,
                    isMergeTarget: false,
                    isMergeArmed: false,
                    reduceMotion: viewModel.reduceMotion,
                    showDeleteBadge: false,
                    recordsFrame: false,
                    onTap: {
                        if let app = entry.app { viewModel.launch(app) }
                    },
                    onDelete: {
                        if let app = entry.app { viewModel.requestDelete(app) }
                    },
                    onLongPress: {},
                    onDragBegan: {
                        guard let app = entry.app else { return }
                        let absoluteIndex = viewModel.currentFolderPage * viewModel.folderPageCapacity + index
                        viewModel.beginFolderDrag(
                            app: app,
                            folderID: folder.id,
                            sourceIndex: absoluteIndex
                        )
                    },
                    onDragChanged: { location in
                        viewModel.updateFolderDrag(location: location)
                    },
                    onDragEnded: {
                        viewModel.endFolderDrag()
                    },
                    onContextAction: { action in
                        handle(action, for: entry)
                    }
                )
                .frame(width: metrics.cellRect(at: 0).width, height: metrics.cellRect(at: 0).height)
                .position(x: cell.midX, y: cell.midY)
                .opacity(isDragSource ? 0 : 1)
                .animation(
                    viewModel.reduceMotion ? Metrics.Motion.reduced : Metrics.Motion.reorder,
                    value: slot
                )
            }

            if let preview = preview, let insertion = preview.insertionSlot {
                let frame = metrics.iconFrame(at: min(insertion, metrics.capacity - 1))
                RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * metrics.scale, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * metrics.scale, style: .continuous)
                            .stroke(
                                Color.white.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                            )
                    }
                    .frame(width: metrics.iconSize, height: metrics.iconSize)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: panelFrame.width, height: panelFrame.height, alignment: .topLeading)
    }

    private struct DragPreviewLayout {
        var slots: [String: Int]
        var insertionSlot: Int?
    }

    private func folderDragPreview(for entries: PageLayout, isCurrent: Bool) -> DragPreviewLayout? {
        guard isCurrent,
              let session = viewModel.folderDragSession,
              session.isOutside == false,
              let hoverSlot = session.hoverSlot else { return nil }

        let remaining = entries.filter { $0.app?.id != session.app.id }
        guard remaining.count < metrics.capacity else { return nil }
        let insertion = min(max(hoverSlot, 0), remaining.count)
        var slots: [String: Int] = [:]
        for (index, entry) in remaining.enumerated() {
            slots[entry.id] = index < insertion ? index : index + 1
        }
        return DragPreviewLayout(slots: slots, insertionSlot: insertion)
    }

    private var folderSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 15, coordinateSpace: .named("launchpad"))
            .onChanged { value in
                guard viewModel.folderDragSession == nil else { return }
                viewModel.updateFolderSwipe(translation: value.translation.width)
            }
            .onEnded { value in
                guard viewModel.folderDragSession == nil else { return }
                viewModel.endFolderSwipe(
                    translation: value.translation.width,
                    predictedTranslation: value.predictedEndTranslation.width
                )
            }
    }

    private func visiblePageIndices(current: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return ((current - 1)...(current + 1)).filter { (0..<count).contains($0) }
    }

    /// Focus the title field and select the whole current name, so a new folder
    /// can be renamed by simply typing and an old name replaced in one keystroke.
    /// Focus can land a beat after the zoom starts, so retry once against the
    /// field editor rather than relying on a single `selectAll` broadcast.
    private func focusAndSelectTitle() {
        titleIsFocused = true
        DispatchQueue.main.async {
            selectAllInTitleField(retries: 2)
        }
    }

    private func selectAllInTitleField(retries: Int) {
        guard viewModel.folderTitleEditing else { return }
        if let editor = (NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder as? NSTextView {
            editor.selectAll(nil)
            return
        }
        // The field may have been inserted in the same update as the token;
        // ask for focus again before the final retry.
        titleIsFocused = true
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            selectAllInTitleField(retries: retries - 1)
        }
    }

    private func handle(_ action: ItemContextAction, for entry: LaunchpadEntry) {
        switch action {
        case .open:
            if let app = entry.app { viewModel.launch(app) }
        case .showInFinder:
            if let app = entry.app { viewModel.showInFinder(app) }
        case .getInfo:
            if let app = entry.app { viewModel.showInfo(app) }
        case .removeFolder(let id):
            viewModel.removeFolder(folderID: id)
        case .renameFolder:
            viewModel.beginFolderRename()
        }
    }
}
