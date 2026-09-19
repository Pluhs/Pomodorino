import Foundation

enum PopoverPinningPhase: Equatable {
    case hidden
    case hoverOpen
    case pinned
}

/// Owns the interaction contract for the status-item popover. Keeping this
/// state separate from AppKit makes the hover → pin → internal click → outside
/// click sequence deterministic and regression-testable.
struct PopoverPinningState {
    private(set) var phase: PopoverPinningPhase = .hidden
    private(set) var pinnedFrame: CGRect?

    mutating func openForHover() {
        guard phase == .hidden else { return }
        phase = .hoverOpen
    }

    /// Returns `true` only when a new popover must be shown. Pinning an
    /// existing hover-open popover deliberately returns `false`, so callers
    /// keep the same AppKit popover and its existing frame.
    mutating func pin(using frame: CGRect) -> Bool {
        switch phase {
        case .hidden:
            phase = .pinned
            pinnedFrame = frame
            return true
        case .hoverOpen:
            phase = .pinned
            pinnedFrame = frame
            return false
        case .pinned:
            return false
        }
    }

    mutating func recordPresentedFrame(_ frame: CGRect) {
        guard phase != .hidden else { return }
        if phase == .hoverOpen || pinnedFrame == .zero {
            pinnedFrame = frame
        }
    }

    mutating func pinExistingPopover() {
        guard phase == .hoverOpen else { return }
        phase = .pinned
    }

    /// When macOS hides a full-screen app's menu bar, AppKit may try to move
    /// the already-visible popover with its status-item anchor. A pinned
    /// popover deliberately keeps the frame it had when it was pinned.
    func frameToRestore(afterAutomaticMoveTo currentFrame: CGRect) -> CGRect? {
        guard phase == .pinned, let pinnedFrame, currentFrame != pinnedFrame else {
            return nil
        }
        return pinnedFrame
    }

    func containsInternalClick(
        at point: CGPoint,
        popoverFrame: CGRect,
        statusItemFrame: CGRect
    ) -> Bool {
        popoverFrame.contains(point) || statusItemFrame.contains(point)
    }

    mutating func dismissFromOutsideClick() {
        phase = .hidden
        pinnedFrame = nil
    }
}
