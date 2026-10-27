import SwiftUI

/// Root SwiftUI view hosted by every overlay window. The interactive window
/// drives input, frame reporting, and sheets; mirrors only render.
struct LaunchpadRootView: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    let isInteractive: Bool
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
                .onChange(of: proxy.size) { newSize in
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

        return ZStack(alignment: .topLeading) {
            LaunchpadBackgroundView(viewModel: viewModel)

            mainContent(size: size, metrics: metrics)
                .scaleEffect(scaleForShow)
                .opacity(viewModel.isVisible ? 1 : 0)
                .blur(radius: blurForShow)
                .blur(radius: folderOpen ? 12 * metrics.scale : 0)
                .opacity(folderOpen ? 0.55 : 1)
                .animation(showContentAnimation, value: viewModel.isVisible)
                .animation(folderAnimation, value: folderOpen)

            if folderOpen {
                Color.black.opacity(0.12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.closeFolder()
                    }
                    .transition(.opacity)

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
                .opacity(viewModel.isVisible ? 1 : 0)
                .animation(visibilityAnimation, value: viewModel.isVisible)
            }

            if showsNoResults {
                Text("No Results", comment: "Empty search results label")
                    .font(.system(size: 22 * metrics.scale, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .position(x: size.width / 2, y: size.height / 2)
                    .opacity(viewModel.isVisible ? 1 : 0)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    private var scaleForShow: CGFloat {
        if viewModel.reduceMotion { return 1 }
        return viewModel.isVisible ? 1 : 1.12
    }

    private var blurForShow: CGFloat {
        if viewModel.reduceMotion { return 0 }
        return viewModel.isVisible ? 0 : 10
    }

    private var showContentAnimation: Animation? {
        if viewModel.reduceMotion { return Metrics.Motion.reduced }
        if viewModel.isVisible {
            return Metrics.Motion.showZoom
        }
        return .easeIn(duration: Metrics.Durations.hideBackground)
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
            DragPreview(
                entry: session.entry,
                iconSize: metrics.iconSize,
                scale: metrics.scale,
                location: session.location
            )
        } else if let session = viewModel.folderDragSession {
            DragPreview(
                entry: .app(session.app),
                iconSize: metrics.iconSize,
                scale: metrics.scale,
                location: session.location
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
        return ((current - 1)...(current + 1)).filter { (0..<count).contains($0) }
    }

    private func centeredFrame(for size: CGSize, in container: CGSize) -> CGRect {
        CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private var folderAnimation: Animation? {
        viewModel.reduceMotion ? Metrics.Motion.reduced : .easeInOut(duration: 0.25)
    }

    private var searchAnimation: Animation? {
        viewModel.reduceMotion ? Metrics.Motion.reduced : .easeInOut(duration: Metrics.Durations.searchCrossFade)
    }

    private var visibilityAnimation: Animation? {
        viewModel.reduceMotion ? Metrics.Motion.reduced : .easeInOut(duration: 0.2)
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
