import XCTest
@testable import Pomodorino

final class PopoverPinningStateTests: XCTestCase {
    func testHoverPinInternalStartKeepsFrameUntilOutsideClick() {
        let hoverFrame = CGRect(x: 100, y: 400, width: 320, height: 420)
        let statusItemFrame = CGRect(x: 220, y: 940, width: 90, height: 24)
        var state = PopoverPinningState()

        state.openForHover()
        state.recordPresentedFrame(hoverFrame)

        // Clicking the status item upgrades the existing hover-open popover;
        // it must not request a new presentation or move its frame.
        XCTAssertFalse(state.pin(using: hoverFrame))
        XCTAssertEqual(state.phase, .pinned)
        XCTAssertEqual(state.pinnedFrame, hoverFrame)

        // A full-screen host can hide its menu bar after the pointer leaves
        // it. AppKit then attempts to move the anchored popover upward. The
        // pinned presentation must restore the frame it had at click time.
        let frameAfterMenuBarRetracts = hoverFrame.offsetBy(dx: 0, dy: 26)
        XCTAssertEqual(
            state.frameToRestore(afterAutomaticMoveTo: frameAfterMenuBarRetracts),
            hoverFrame
        )

        // A pinned popover remains stable even after the pointer is no longer
        // in the menu bar. A subsequent Start click is still internal.
        let pointerAwayFromMenuBar = CGPoint(x: 260, y: 650)
        XCTAssertTrue(
            state.containsInternalClick(
                at: pointerAwayFromMenuBar,
                popoverFrame: hoverFrame,
                statusItemFrame: statusItemFrame
            )
        )
        XCTAssertEqual(state.phase, .pinned)

        let startButtonPoint = CGPoint(x: 260, y: 450)
        XCTAssertTrue(
            state.containsInternalClick(
                at: startButtonPoint,
                popoverFrame: hoverFrame,
                statusItemFrame: statusItemFrame
            )
        )
        XCTAssertEqual(state.phase, .pinned)
        XCTAssertEqual(state.pinnedFrame, hoverFrame)

        let outsidePoint = CGPoint(x: 700, y: 300)
        XCTAssertFalse(
            state.containsInternalClick(
                at: outsidePoint,
                popoverFrame: hoverFrame,
                statusItemFrame: statusItemFrame
            )
        )
        state.dismissFromOutsideClick()

        XCTAssertEqual(state.phase, .hidden)
        XCTAssertNil(state.pinnedFrame)
    }
}
