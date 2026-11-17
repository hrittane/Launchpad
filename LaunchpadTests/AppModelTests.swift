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
}
