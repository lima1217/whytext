import Foundation

/// Pure acceptance rules for selection auto-popup (no AppKit / AX).
public enum SelectionAutoPopupPolicy {
    public static let minimumTextLength = 2

    /// Whether an Accessibility selection may summon the bubble.
    ///
    /// - Prefer a near-mouse anchor when AX provides one.
    /// - On intentional gestures (drag / multi-click), accept AX text even if the
    ///   anchor is missing or untrustworthy — many apps expose wrong bounds.
    /// - Clipboard/Cmd+C fallback is handled by the coordinator after AX fails.
    public static func acceptsAXSelection(
        textLength: Int,
        hasAnchorRect: Bool,
        anchorNearMouse: Bool,
        allowMissingAnchor: Bool
    ) -> Bool {
        guard textLength >= minimumTextLength else { return false }
        if hasAnchorRect && anchorNearMouse {
            return true
        }
        return allowMissingAnchor
    }
}
