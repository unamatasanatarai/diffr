import AppKit

/// Keeps both panes visually locked together, vertically and horizontally.
///
/// Syncs by on-screen document position rather than raw clip origin, so a find bar
/// (which pushes one pane's content down) does not knock the panes out of alignment.
public final class DiffScrollCoordinator: NSObject {
    private weak var leftEditor: DiffEditorView?
    private weak var rightEditor: DiffEditorView?
    private var isSynchronizing = false

    public func attach(left: DiffEditorView, right: DiffEditorView) {
        self.leftEditor = left
        self.rightEditor = right

        for editor in [left, right] {
            let clip = editor.scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            clip.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clip
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: clip
            )
        }
    }

    @objc private func clipViewDidChange(_ notification: Notification) {
        guard !isSynchronizing,
              let clipView = notification.object as? NSClipView,
              let left = leftEditor,
              let right = rightEditor else { return }

        let isLeft = (clipView == left.scrollView.contentView)
        let source = isLeft ? left : right
        let target = isLeft ? right : left
        let targetClip = target.scrollView.contentView

        let newOrigin = NSPoint(
            x: clipView.bounds.origin.x,
            y: targetClip.bounds.origin.y + (source.documentOffsetY - target.documentOffsetY)
        )
        guard newOrigin != targetClip.bounds.origin else { return }

        isSynchronizing = true
        defer { isSynchronizing = false }
        targetClip.scroll(to: newOrigin)
        target.scrollView.reflectScrolledClipView(targetClip)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
