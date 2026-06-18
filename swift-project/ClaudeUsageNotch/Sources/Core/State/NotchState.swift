import Foundation

/// Notch presentation state machine.
public enum NotchState: Hashable {
    case hidden          // disabled or no device notch
    case compactIdle     // small pill visible, no interaction
    case compactHover    // mouse over pill, animating toward expansion
    case expandedPinned  // user clicked; stays open until dismissed
    case expandedHover   // hover-expanded; collapses when mouse leaves
}
