import Foundation

/// Whether the notch panel is collapsed, hover-expanded or pinned open, and
/// where the pointer was at the last hover poll.
public enum NotchPhase: Hashable {
    case collapsed
    /// Collapsed by a click or Escape with the pointer still over the cutout.
    /// It must leave before hovering can expand the panel again.
    case collapsedUnderPointer
    case hoverExpanded
    case pinned(pointerInside: Bool)

    public enum Event: Hashable {
        case pointer(inside: Bool)
        case tapped
        case escapePressed
        case clickedOutside
        case pinRequested
    }

    public var isExpanded: Bool {
        switch self {
        case .collapsed, .collapsedUnderPointer: return false
        case .hoverExpanded, .pinned:            return true
        }
    }

    public var isPinned: Bool {
        if case .pinned = self { return true }
        return false
    }

    private var pointerInside: Bool {
        switch self {
        case .collapsed:                 return false
        case .collapsedUnderPointer:     return true
        case .hoverExpanded:             return true
        case .pinned(let pointerInside): return pointerInside
        }
    }

    private var collapsedKeepingPointer: NotchPhase {
        pointerInside ? .collapsedUnderPointer : .collapsed
    }

    public mutating func reduce(_ event: Event) {
        switch (self, event) {
        case (.collapsed, .pointer(inside: true)):
            self = .hoverExpanded
        case (.collapsedUnderPointer, .pointer(inside: false)),
             (.hoverExpanded, .pointer(inside: false)):
            self = .collapsed
        case (.pinned, .pointer(let inside)):
            self = .pinned(pointerInside: inside)
        case (_, .pointer):
            break

        case (.pinned, .tapped), (_, .escapePressed), (.pinned, .clickedOutside):
            self = collapsedKeepingPointer
        case (_, .tapped), (_, .pinRequested):
            self = .pinned(pointerInside: pointerInside)
        case (_, .clickedOutside):
            break
        }
    }
}
