import Foundation
import Testing

@testable import Launchpad

@MainActor
struct AppModelTests {
    @Test
    func startsOnFirstPage() {
        let model = AppModel()
        #expect(model.currentPage == 0)
    }

    @Test
    func stepPageClampsToAvailablePages() {
        let model = AppModel()
        model.pageCount = 3

        model.stepPage(by: 1)
        #expect(model.currentPage == 1)

        model.stepPage(by: 5)
        #expect(model.currentPage == 2)

        model.stepPage(by: -10)
        #expect(model.currentPage == 0)
    }

    @Test
    func singlePageCannotBeLeft() {
        let model = AppModel()
        model.pageCount = 1

        model.stepPage(by: 1)
        #expect(model.currentPage == 0)

        model.goToPage(4)
        #expect(model.currentPage == 0)
    }

    @Test
    func shrinkingCatalogPullsCurrentPageBackInRange() {
        let model = AppModel()
        model.pageCount = 4
        model.goToPage(3)
        #expect(model.currentPage == 3)

        model.pageCount = 2
        model.clampCurrentPage()
        #expect(model.currentPage == 1)
    }

    @Test
    func pageCapacityMatchesDefaultGrid() {
        let model = AppModel()
        #expect(model.pageCapacity == 35)
    }

    @Test
    func fingerSwipeTranslatesLiveThenCommitsOnRelease() {
        let model = AppModel()
        model.pageCount = 3
        model.beginPageGesture()

        model.updatePageGesture(deltaX: -120, pageWidth: 1000)
        #expect(model.pageDragOffset == -120)
        #expect(model.currentPage == 0)

        model.updatePageGesture(deltaX: -80, pageWidth: 1000)
        #expect(model.pageDragOffset == -200)

        model.endPageGesture(pageWidth: 1000)
        #expect(model.currentPage == 1)
        #expect(model.pageDragOffset == 0)
        #expect(!model.isPaging)
    }

    @Test
    func shortSwipeSpringsBack() {
        let model = AppModel()
        model.pageCount = 3
        model.goToPage(1)

        model.beginPageGesture()
        model.updatePageGesture(deltaX: -100, pageWidth: 1000)
        model.endPageGesture(pageWidth: 1000)

        #expect(model.currentPage == 1)
        #expect(model.pageDragOffset == 0)
    }

    @Test
    func swipePastFirstPageRubberBands() {
        let model = AppModel()
        model.pageCount = 3
        model.beginPageGesture()

        model.updatePageGesture(deltaX: 500, pageWidth: 1000)
        #expect(model.pageDragOffset == 160)

        model.endPageGesture(pageWidth: 1000)
        #expect(model.currentPage == 0)
        #expect(model.pageDragOffset == 0)
    }

    @Test
    func swipeOffsetIsCappedAtOnePage() {
        let model = AppModel()
        model.pageCount = 3
        model.beginPageGesture()

        model.updatePageGesture(deltaX: -5000, pageWidth: 1000)
        #expect(model.pageDragOffset == -1000)

        model.endPageGesture(pageWidth: 1000)
        #expect(model.currentPage == 1)
    }

    @Test
    func cancelDropsLiveSwipe() {
        let model = AppModel()
        model.pageCount = 3
        model.beginPageGesture()
        model.updatePageGesture(deltaX: -400, pageWidth: 1000)

        model.cancelPageGesture()

        #expect(!model.isPaging)
        #expect(model.pageDragOffset == 0)
        #expect(model.currentPage == 0)
    }

    @Test
    func fastShortFlickStillTurnsThePage() {
        let model = AppModel()
        model.pageCount = 3
        model.beginPageGesture()
        model.updatePageGesture(deltaX: -60, pageWidth: 1000)

        model.endPageGesture(pageWidth: 1000, velocityX: -2500)

        #expect(model.currentPage == 1)
        #expect(model.pageDragOffset == 0)
    }

    @Test
    func slowShortSwipeStillSpringsBack() {
        let model = AppModel()
        model.pageCount = 3
        model.beginPageGesture()
        model.updatePageGesture(deltaX: -60, pageWidth: 1000)

        model.endPageGesture(pageWidth: 1000, velocityX: -300)

        #expect(model.currentPage == 0)
    }

    @Test
    func flickInTheOppositeDirectionDoesNotTurnThePage() {
        let model = AppModel()
        model.pageCount = 3
        model.beginPageGesture()
        model.updatePageGesture(deltaX: -150, pageWidth: 1000)

        // The fingers reversed just before lifting: the release velocity must
        // not carry the page the other way, and the distance alone is short.
        model.endPageGesture(pageWidth: 1000, velocityX: 3000)

        #expect(model.currentPage == 0)
    }
}
