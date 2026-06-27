import XCTest
@testable import LutrisForMacCore

final class ConsoleSettingsIndexLogicTests: XCTestCase {

    typealias SUT = ConsoleSettingsIndexLogic

    // MARK: - Basic

    func test_index0_isToggle0() {
        XCTAssertEqual(SUT.actionForIndex(0, toggleCount: 4, controllerSettingsAvailable: false), .toggle(0))
    }

    func test_index3_isToggle3() {
        XCTAssertEqual(SUT.actionForIndex(3, toggleCount: 4, controllerSettingsAvailable: false), .toggle(3))
    }

    func test_afterToggles_isAbout() {
        let idx = 4
        let result = SUT.actionForIndex(idx, toggleCount: 4, controllerSettingsAvailable: false)
        XCTAssertEqual(result, .about)
    }

    func test_afterAbout_isDesktopExit() {
        let idx = 5
        let result = SUT.actionForIndex(idx, toggleCount: 4, controllerSettingsAvailable: false)
        XCTAssertEqual(result, .desktopExit)
    }

    func test_pastEnd_returnsNil() {
        let result = SUT.actionForIndex(100, toggleCount: 4, controllerSettingsAvailable: false)
        XCTAssertNil(result)
    }

    // MARK: - With Controller Settings

    func test_withControllerSettings_afterToggles_isControllerSettings() {
        let idx = 4
        let result = SUT.actionForIndex(idx, toggleCount: 4, controllerSettingsAvailable: true)
        XCTAssertEqual(result, .controllerSettings)
    }

    func test_withControllerSettings_afterControllerSettings_isAbout() {
        let idx = 5
        let result = SUT.actionForIndex(idx, toggleCount: 4, controllerSettingsAvailable: true)
        XCTAssertEqual(result, .about)
    }

    func test_withControllerSettings_afterAbout_isDesktopExit() {
        let idx = 6
        let result = SUT.actionForIndex(idx, toggleCount: 4, controllerSettingsAvailable: true)
        XCTAssertEqual(result, .desktopExit)
    }

    // MARK: - itemCount

    func test_itemCount_noControllerSettings() {
        let count = SUT.itemCount(toggleCount: 4, controllerSettingsAvailable: false)
        XCTAssertEqual(count, 4 + 1 + 1) // toggles + about + desktopExit
    }

    func test_itemCount_withControllerSettings() {
        let count = SUT.itemCount(toggleCount: 4, controllerSettingsAvailable: true)
        XCTAssertEqual(count, 4 + 1 + 1 + 1) // toggles + controllerSettings + about + desktopExit
    }
}
