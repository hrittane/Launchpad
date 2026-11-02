import SwiftUI

/// Root SwiftUI view hosted by every overlay window. The interactive window
/// drives input, frame reporting, and sheets; mirrors only render.
struct LaunchpadRootView: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    let isInteractive: Bool
    @ObservedObject var screenContext: OverlayScreenContext
    @Namespace private var pageRotorNamespace

    var body: some View {
        GeometryReader { proxy in
            content(size: proxy.size)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .coordinateSpace(name: "launchpad")
                .onAppear {
                    if isInteractive {
                        viewModel.setScreenSize(proxy.size)
                    }
                }
                .onChange(of: proxy.size) { _, newSize in
                    if isInteractive {
                        viewModel.setScreenSize(newSize)
                    }
                }
                .onPreferenceChange(IconFramePreferenceKey.self) { frames in
                    if isInteractive {
                        viewModel.recordIconFrames(frames)
                    }
                }
                .modifier(InteractivePresentations(viewModel: viewModel, isInteractive: isInteractive))
        }
        .ignoresSafeArea()
    }

    private func content(size: CGSize) -> some View {
        let metrics = LayoutMetrics(screenSize: size, settings: viewModel.settings)
        let folderOpen = viewModel.openFolderID != nil

        // The backdrop stays outside the glass container so its window material
        // keeps sampling the desktop directly. The main grid's controls share
        // one container, which lets the system batch them in a single pass.
        return ZStack(alignment: .topLeading) {
            LaunchpadBackgroundView(
                viewModel: viewModel,
                screen: screenContext.screen,
                viewport: screenContext.viewport
            )

            GlassEffectContainer(spacing: 8) {
                mainContent(size: size, metrics: metrics)
            }

            // The folder panel is deliberately outside the glass container.
            // The container renders glass shapes in its own pass, so a child
            // transform does not scale the glass with the tiles. Keeping the
            // panel standalone lets the zoom be a cheap layer transform.
            if folderOpen {
                // The scrim fades with the panel instead of popping. It also
                // fades out while an app is dragged out of the folder so the
                // grid underneath is legible.
                Color.black.opacity(viewModel.folderIsPresented ? 0.16 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Commits a pending rename before closing, matching a
                        // click outside the folder.
                        viewModel.handleBackgroundTap()
                    }
                    .allowsHitTesting(viewModel.folderIsPresented)
                    .animation(folderAnimation, value: viewModel.folderIsPresented)

                if let folder = viewModel.activeFolder {
                    let folderMetrics = FolderMetrics(screenSize: size, settings: viewModel.settings)
                    FolderPanelView(
                        viewModel: viewModel,
                        folder: folder,
                        metrics: folderMetrics,
                        panelFrame: centeredFrame(for: folderMetrics.panelSize, in: size),
                        anchor: viewModel.folderAnchor,
                        isPresented: viewModel.folderIsPresented
                    )
                    // A new folder must insert a fresh panel so its `onAppear`
                    // can request the zoom, even if the previous panel was
                    // still in the view tree.
                    .id(folder.id)
                }
            }

            dragLayer(metrics: metrics)
        }
    }

    private func mainContent(size: CGSize, metrics: LayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.handleBackgroundTap()
                }
                .gesture(pageSwipeGesture)

            pageContainer(size: size, metrics: metrics)
                // Only the grid blurs. Blurring the whole main content
                // (including the glass search field) produced dark smears
                // because the glass and the transparent blur layer composited
                // over each other.
                .blur(radius: backgroundBlurRadius(metrics))
                .animation(folderAnimation, value: viewModel.folderIsPresented)

            SearchBar(viewModel: viewModel, scale: metrics.scale)
                .position(
                    x: size.width / 2,
                    y: metrics.searchTopOffset + metrics.searchSize.height / 2
                )

            if !viewModel.isSearchMode && viewModel.displayedPageCount > 1 {
                PageDots(
                    pageCount: viewModel.displayedPageCount,
                    currentPage: viewModel.currentDisplayedPage,
                    diameter: Metrics.pageDotDiameter * metrics.scale,
                    spacing: Metrics.pageDotSpacing * metrics.scale,
                    onSelect: { page in
                        viewModel.goToPage(page)
                    }
                )
                .position(x: size.width / 2, y: metrics.pageDotCenterY)
                .blur(radius: backgroundBlurRadius(metrics))
                .animation(folderAnimation, value: viewModel.folderIsPresented)
            }

            if showsNoResults {
                Text("No Results", comment: "Empty search results label")
                    .font(.system(size: 22 * metrics.scale, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .position(x: size.width / 2, y: size.height / 2)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    private func pageContainer(size: CGSize, metrics: LayoutMetrics) -> some View {
        let pages = viewModel.displayedPages
        let current = viewModel.currentDisplayedPage
        let indices = visiblePageIndices(current: current, count: pages.count)

        return ZStack(alignment: .topLeading) {
            ForEach(indices, id: \.self) { index in
                PageView(
                    viewModel: viewModel,
                    pageIndex: index,
                    entries: pages[index],
                    metrics: metrics,
                    isInteractive: isInteractive,
                    recordsFrames: isInteractive
                )
                .frame(width: size.width, height: size.height)
                .offset(
                    x: CGFloat(index - current) * size.width
                )
                .accessibilityRotorEntry(id: index, in: pageRotorNamespace)
            }
        }
        .frame(width: size.width, height: size.height)
        .modifier(PageDragOffsetModifier(state: viewModel.pageDrag))
        .clipped()
        .id(viewModel.isSearchMode)
        .transition(.opacity)
        .animation(searchAnimation, value: viewModel.isSearchMode)
        .accessibilityRotor(Text("Pages", comment: "Accessibility rotor for grid pages")) {
            ForEach(0..<viewModel.displayedPageCount, id: \.self) { index in
                AccessibilityRotorEntry(
                    Text(
                        "Page \(index + 1) of \(viewModel.displayedPageCount)",
                        comment: "Accessibility rotor page entry"
                    ),
                    id: index,
                    in: pageRotorNamespace
                )
            }
        }
    }

    @ViewBuilder
    private func dragLayer(metrics: LayoutMetrics) -> some View {
        if let session = viewModel.dragSession {
            // Observes only the isolated cursor position, so moving the pointer
            // does not re-render the grid behind the floating icon.
            ItemDragPreviewLayer(
                dragState: viewModel.itemDrag,
                entry: session.entry,
                iconSize: metrics.iconSize,
                scale: metrics.scale
            )
        } else if let session = viewModel.folderDragSession {
            // Observes only the isolated cursor position, so dragging an app
            // out of a folder does not re-render the grid or the panel.
            FolderDragPreviewLayer(
                dragState: viewModel.folderItemDrag,
                entry: .app(session.app),
                iconSize: metrics.iconSize,
                scale: metrics.scale
            )
        }
    }

    private var showsNoResults: Bool {
        viewModel.isSearchMode
            && viewModel.searchResults.isEmpty
            && !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .named("launchpad"))
            .onChanged { value in
                viewModel.updatePageSwipe(translation: value.translation.width)
            }
            .onEnded { value in
                viewModel.endPageSwipe(
                    translation: value.translation.width,
                    predictedTranslation: value.predictedEndTranslation.width
                )
            }
    }

    private func visiblePageIndices(current: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var indices = Set(((current - 1)...(current + 1)).filter { (0..<count).contains($0) })
        // The dragged item's view must stay alive for the whole gesture. Keep
        // its source page instantiated even after the user flips away from it.
        if let session = viewModel.dragSession {
            let source = session.sourcePage
            indices.formUnion(((source - 1)...(source + 1)).filter { (0..<count).contains($0) })
        }
        return indices.sorted()
    }

    private func centeredFrame(for size: CGSize, in container: CGSize) -> CGRect {
        CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private var searchAnimation: Animation? {
        viewModel.reduceMotion ? Metrics.Motion.reduced : .easeInOut(duration: Metrics.Durations.searchCrossFade)
    }

    private func backgroundBlurRadius(_ metrics: LayoutMetrics) -> CGFloat {
        viewModel.folderIsPresented ? Metrics.folderBackgroundBlur * metrics.scale : 0
    }

    private var folderAnimation: Animation? {
        if viewModel.reduceMotion { return Metrics.Motion.reduced }
        // The scrim must use the same curve as the panel. Mixing the bouncy
        // open spring with the critically damped close spring left the dark
        // scrim visible for a few frames after the panel had already landed,
        // which made the close feel ragged.
        return viewModel.folderIsPresented ? Metrics.Motion.folder : Metrics.Motion.folderClose
    }
}

/// Floating icon for a grid drag. Reads the drag position from its own
/// observable so only this small view updates as the cursor moves.
private struct ItemDragPreviewLayer: View {
    @ObservedObject var dragState: ItemDragState
    let entry: LaunchpadEntry
    let iconSize: CGFloat
    let scale: CGFloat

    var body: some View {
        DragPreview(
            entry: entry,
            iconSize: iconSize,
            scale: scale,
            location: dragState.location
        )
    }
}

/// Floating icon for an app dragged out of an opened folder. Reads the cursor
/// from the isolated folder-drag observable so the panel and grid stay static
/// while the pointer moves.
private struct FolderDragPreviewLayer: View {
    @ObservedObject var dragState: FolderDragState
    let entry: LaunchpadEntry
    let iconSize: CGFloat
    let scale: CGFloat

    var body: some View {
        DragPreview(
            entry: entry,
            iconSize: iconSize,
            scale: scale,
            location: dragState.location
        )
    }
}

/// Sheets and alerts are attached only to the interactive window so mirrored
/// displays cannot present duplicate copies.
private struct InteractivePresentations: ViewModifier {
    @ObservedObject var viewModel: LaunchpadViewModel
    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isInteractive {
            content
                .sheet(item: $viewModel.infoApp) { app in
                    InfoSheet(app: app, viewModel: viewModel)
                }
                .alert(
                    Text(
                        "Remove \(viewModel.pendingDelete?.name ?? "Application")?",
                        comment: "Delete confirmation title"
                    ),
                    isPresented: deleteBinding
                ) {
                    Button(role: .destructive) {
                        viewModel.confirmDelete()
                    } label: {
                        Text("Move to Trash", comment: "Delete confirmation button")
                    }
                    Button(role: .cancel) {
                        viewModel.cancelDelete()
                    } label: {
                        Text("Cancel", comment: "Cancel button")
                    }
                } message: {
                    Text(
                        "The application will be moved to the Trash. App files are not deleted immediately.",
                        comment: "Delete confirmation message"
                    )
                }
        } else {
            content
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDelete != nil },
            set: { isPresented in
                if !isPresented { viewModel.cancelDelete() }
            }
        )
    }
}
