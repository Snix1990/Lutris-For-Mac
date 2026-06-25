import XCTest
@testable import LutrisForMacCore

final class ConsoleSettingsIndexLogicTests: XCTestCase {

    typealias SUT = ConsoleSettingsIndexLogic

    // MARK: - Basic defaults (all collapsed)

    func test_index0_isToggle0() {
        XCTAssertEqual(SUT.actionForIndex(0, toggleCount: 4, controllerCount: 1, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0), .toggle(0))
    }

    func test_index3_isToggle3() {
        XCTAssertEqual(SUT.actionForIndex(3, toggleCount: 4, controllerCount: 1, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0), .toggle(3))
    }

    func test_index4_isControllerInfo() {
        XCTAssertEqual(SUT.actionForIndex(4, toggleCount: 4, controllerCount: 2, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0), .controllerInfo(0))
    }

    func test_noController_stillShowsControllerInfo() {
        XCTAssertEqual(SUT.actionForIndex(4, toggleCount: 4, controllerCount: 0, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0), .controllerInfo(0))
    }

    func test_afterControllerInfo_isUiNavHeader() {
        let idx = 4 + 1 // toggle(0-3) + controllerInfo(0) = 5 items when controllerCount==1
        let result = SUT.actionForIndex(idx, toggleCount: 4, controllerCount: 1, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0)
        XCTAssertEqual(result, .uiNavHeader)
    }

    func test_afterControllerInfo_thenUiNavHeader_thenHidRunnerHeader_thenRemappingHeader_thenAbout_thenDesktopExit_isLast() {
        let toggleCount = 4
        let controllerCount = 1
        // cursor sequence: 4 toggles + 1 controller + 1 uiNavHeader + 1 hidRunnerHeader + 1 remappingHeader + 1 about + 1 desktopExit
        let total = toggleCount + 1 + 1 + 1 + 1 + 1 + 1
        XCTAssertEqual(total, 10)
        let result = SUT.actionForIndex(total - 1, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0)
        XCTAssertEqual(result, .desktopExit)
    }

    func test_pastEnd_returnsNil() {
        let result = SUT.actionForIndex(100, toggleCount: 4, controllerCount: 1, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0)
        XCTAssertNil(result)
    }

    // MARK: - UiNavExpanded

    func test_uiNavExpanded_withoutCustomMapping() {
        let toggleCount = 4
        let controllerCount = 2
        let ctrlCount = max(controllerCount, 1)
        // 0-3: toggles, 4-5: controllers, 6: uiNavHeader, 7: autoDetection
        let autoIdx = toggleCount + ctrlCount + 1
        let result = SUT.actionForIndex(autoIdx, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: true, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0)
        XCTAssertEqual(result, .uiNavAutoDetection)
    }

    func test_uiNavExpanded_withControllerLayoutPicker() {
        let toggleCount = 4
        let controllerCount = 2
        let ctrlCount = max(controllerCount, 1)
        let layoutIdx = toggleCount + ctrlCount + 1 + 1 // +1 autoDetect
        let result = SUT.actionForIndex(layoutIdx, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: true, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0)
        XCTAssertEqual(result, .uiNavControllerLayout(0))
    }

    func test_uiNavExpanded_withCustomHeader() {
        let toggleCount = 4
        let controllerCount = 2
        let ctrlCount = max(controllerCount, 1)
        let customHeaderIdx = toggleCount + ctrlCount + 1 + 1 + controllerCount // toggles + controllers + uiNavHeader + autoDetect + layoutPick
        let result = SUT.actionForIndex(customHeaderIdx, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: true, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0)
        XCTAssertEqual(result, .uiNavCustomHeader)
    }

    // MARK: - CustomMapping Expanded

    func test_customMappingExpanded_withAddAndReset() {
        let toggleCount = 4
        let controllerCount = 1
        let ctrlCount = max(controllerCount, 1)
        let customMappingCount = 2

        // cursor = toggles(4) + controllers(1) + uiNavHeader(1) + autoDetect(1) + layoutPick(1) + customHeader(1) = 9
        let cursor = toggleCount + ctrlCount + 1 + 1 + controllerCount + 1
        XCTAssertEqual(cursor, 9)

        // 9 → customMapping(0)
        XCTAssertEqual(SUT.actionForIndex(cursor, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: true, uiCustomExpanded: true, customMappingCount: customMappingCount, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0), .uiNavCustomMapping(0))

        // 10 → customMapping(1)
        XCTAssertEqual(SUT.actionForIndex(cursor + 1, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: true, uiCustomExpanded: true, customMappingCount: customMappingCount, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0), .uiNavCustomMapping(1))

        // 11 → customAdd
        XCTAssertEqual(SUT.actionForIndex(cursor + customMappingCount, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: true, uiCustomExpanded: true, customMappingCount: customMappingCount, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0), .uiNavCustomAdd)

        // 12 → customReset (since customMappingCount > 0)
        XCTAssertEqual(SUT.actionForIndex(cursor + customMappingCount + 1, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: true, uiCustomExpanded: true, customMappingCount: customMappingCount, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0), .uiNavCustomReset)
    }

    // MARK: - HID Runner Expanded

    func test_hidRunnerExpanded() {
        let toggleCount = 4
        let controllerCount = 1
        let ctrlCount = max(controllerCount, 1)
        // cursor = toggles(4) + controllers(1) + uiNavHeader(1) = 6
        let hidHeaderIdx = toggleCount + ctrlCount + 1
        let result = SUT.actionForIndex(hidHeaderIdx, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 3, remappingExpanded: false, remappingCount: 0)
        XCTAssertEqual(result, .hidRunnerHeader)
    }

    func test_hidRunnerExpanded_withItems() {
        let toggleCount = 4
        let controllerCount = 1
        let ctrlCount = max(controllerCount, 1)
        var cursor = toggleCount + ctrlCount + 1 // hidRunnerHeader
        cursor += 1 // skip header
        let result = SUT.actionForIndex(cursor, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: true, runnerCount: 3, remappingExpanded: false, remappingCount: 0)
        XCTAssertEqual(result, .hidRunnerItem(0))
    }

    // MARK: - Remapping Expanded

    func test_remappingExpanded_withItemsAtCorrectIndex() {
        let toggleCount = 4
        let controllerCount = 1
        let ctrlCount = max(controllerCount, 1)
        let cursor = toggleCount + ctrlCount + 1 + 1 // +uiNavHeader +hidRunnerHeader
        // cursor = 7 = remappingHeader
        XCTAssertEqual(SUT.actionForIndex(cursor, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: true, remappingCount: 2), .remappingHeader)
        // 8 → remappingItem(0), 9 → remappingItem(1)
        XCTAssertEqual(SUT.actionForIndex(cursor + 1, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: true, remappingCount: 2), .remappingItem(0))
        XCTAssertEqual(SUT.actionForIndex(cursor + 2, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: true, remappingCount: 2), .remappingItem(1))
        // 10 → remappingAdd
        XCTAssertEqual(SUT.actionForIndex(cursor + 3, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: true, remappingCount: 2), .remappingAdd)
        // 11 → about, 12 → desktopExit
        XCTAssertEqual(SUT.actionForIndex(cursor + 4, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: true, remappingCount: 2), .about)
        XCTAssertEqual(SUT.actionForIndex(cursor + 5, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: true, remappingCount: 2), .desktopExit)
    }

    func test_remappingExpanded_pastItems_isAdd() {
        let toggleCount = 4
        let controllerCount = 1
        let ctrlCount = max(controllerCount, 1)
        var cursor = toggleCount + ctrlCount + 1 + 1 + 1 // +uiNavHeader +hidRunnerHeader +remappingHeader
        cursor += 2 // skip 2 remapping items
        let result = SUT.actionForIndex(cursor, toggleCount: toggleCount, controllerCount: controllerCount, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: true, remappingCount: 2)
        XCTAssertEqual(result, .remappingAdd)
    }

    // MARK: - itemCount

    func test_itemCount_allCollapsed() {
        let count = SUT.itemCount(toggleCount: 4, controllerCount: 1, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0)
        XCTAssertEqual(count, 4 + 1 + 1 + 1 + 1 + 1 + 1) // toggles + controller + uiNav + hidRunner + remapping + about + desktopExit
    }

    func test_itemCount_uiNavExpanded() {
        let count = SUT.itemCount(toggleCount: 4, controllerCount: 1, uiNavExpanded: true, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0)
        // toggles(4) + controllers(1) + uiNavHeader(1) + autoDetect(1) + layoutPick(1) + customHeader(1)
        // + hidRunnerHeader(1) + remappingHeader(1) + about(1) + desktopExit(1) = 13
        XCTAssertEqual(count, 13)
    }

    func test_itemCount_everythingExpanded() {
        let count = SUT.itemCount(toggleCount: 4, controllerCount: 2, uiNavExpanded: true, uiCustomExpanded: true, customMappingCount: 3, hidRunnerExpanded: true, runnerCount: 5, remappingExpanded: true, remappingCount: 4)
        // toggles(4) + controllers(2) + uiNavHeader(1) + autoDetect(1) + layout(2) + customHeader(1) + customMapping(3) + add(1) + reset(1) + hidRunnerHeader(1) + hidRunnerItems(5) + remappingHeader(1) + remappingItems(4) + add(1) + about(1) + desktopExit(1)
        XCTAssertEqual(count, 4 + 2 + 1 + 1 + 2 + 1 + 3 + 1 + 1 + 1 + 5 + 1 + 4 + 1 + 1 + 1)
    }

    func test_itemCount_noController() {
        let count = SUT.itemCount(toggleCount: 4, controllerCount: 0, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0)
        XCTAssertEqual(count, 4 + 1 + 1 + 1 + 1 + 1 + 1) // toggles(4) + "Kein Controller"(1) + uiNav(1) + hidRunner(1) + remapping(1) + about(1) + desktopExit(1)
    }

    // MARK: - computeBoundaries

    func test_boundaries_allCollapsed() {
        let b = SUT.computeBoundaries(toggleCount: 4, controllerCount: 1, uiNavExpanded: false, uiCustomExpanded: false, customMappingCount: 0, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0)
        // toggles(4) + controllers(1) = 5
        XCTAssertEqual(b.uiNavigationStart, 5)
        // + uiNavHeader(1) = 6
        XCTAssertEqual(b.virtualHIDStart, 6)
        // + hidRunnerHeader(1) = 7
        XCTAssertEqual(b.remappingStart, 7)
        // + remappingHeader(1) = 8
        XCTAssertEqual(b.aboutStart, 8)
        // + about(1) + desktopExit(1) = 10
        XCTAssertEqual(b.totalCount, 10)
    }

    func test_boundaries_uiNavExpanded_withCustom() {
        let b = SUT.computeBoundaries(toggleCount: 4, controllerCount: 2, uiNavExpanded: true, uiCustomExpanded: true, customMappingCount: 3, hidRunnerExpanded: false, runnerCount: 0, remappingExpanded: false, remappingCount: 0)
        // toggles(4) + controllers(2) = 6
        XCTAssertEqual(b.uiNavigationStart, 6)
        // + uiNavHeader(1) + autoDetect(1) + layouts(2) + customHeader(1) + items(3) + add(1) + reset(1) = 16
        XCTAssertEqual(b.virtualHIDStart, 16)
        // + hidRunnerHeader(1) = 17
        XCTAssertEqual(b.remappingStart, 17)
        // + remappingHeader(1) = 18
        XCTAssertEqual(b.aboutStart, 18)
        // + about(1) + desktopExit(1) = 20
        XCTAssertEqual(b.totalCount, 20)
    }

    func test_boundaries_everythingExpanded() {
        let b = SUT.computeBoundaries(toggleCount: 4, controllerCount: 2, uiNavExpanded: true, uiCustomExpanded: true, customMappingCount: 3, hidRunnerExpanded: true, runnerCount: 5, remappingExpanded: true, remappingCount: 4)
        // toggles(4) + controllers(2) = 6
        XCTAssertEqual(b.uiNavigationStart, 6)
        // + uiNavHeader(1) + autoDetect(1) + layouts(2) + customHeader(1) + items(3) + add(1) + reset(1) = 16
        XCTAssertEqual(b.virtualHIDStart, 16)
        // + hidRunnerHeader(1) + runnerItems(5) = 22
        XCTAssertEqual(b.remappingStart, 22)
        // + remappingHeader(1) + remapItems(4) + add(1) = 28
        XCTAssertEqual(b.aboutStart, 28)
        // + about(1) + desktopExit(1) = 30
        XCTAssertEqual(b.totalCount, 30)
    }

    func test_boundaries_itemCountMatchesTotal() {
        let params: [(toggleCount: Int, controllerCount: Int, uiNavExpanded: Bool, uiCustomExpanded: Bool, customMappingCount: Int, hidRunnerExpanded: Bool, runnerCount: Int, remappingExpanded: Bool, remappingCount: Int)] = [
            (4, 0, false, false, 0, false, 0, false, 0),
            (4, 1, false, false, 0, false, 0, false, 0),
            (4, 2, true, false, 0, false, 0, false, 0),
            (4, 1, true, true, 2, false, 0, false, 0),
            (4, 2, true, true, 3, true, 5, true, 4),
            (6, 3, false, false, 0, true, 2, false, 0),
            (6, 3, false, false, 0, false, 0, true, 1),
        ]
        for p in params {
            let b = SUT.computeBoundaries(toggleCount: p.toggleCount, controllerCount: p.controllerCount, uiNavExpanded: p.uiNavExpanded, uiCustomExpanded: p.uiCustomExpanded, customMappingCount: p.customMappingCount, hidRunnerExpanded: p.hidRunnerExpanded, runnerCount: p.runnerCount, remappingExpanded: p.remappingExpanded, remappingCount: p.remappingCount)
            let count = SUT.itemCount(toggleCount: p.toggleCount, controllerCount: p.controllerCount, uiNavExpanded: p.uiNavExpanded, uiCustomExpanded: p.uiCustomExpanded, customMappingCount: p.customMappingCount, hidRunnerExpanded: p.hidRunnerExpanded, runnerCount: p.runnerCount, remappingExpanded: p.remappingExpanded, remappingCount: p.remappingCount)
            XCTAssertEqual(b.totalCount, count, "Mismatch for params \(p)")
        }
    }
}
