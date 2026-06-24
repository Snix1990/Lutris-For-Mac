import SwiftUI

struct ScrollController: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ScrollControllerView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class ScrollControllerView: NSView {
    weak var scrollView: NSScrollView?
    private var observation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // Walk up the responder chain to find the enclosing scroll view
            var next = superview
            while next != nil {
                if let sv = next as? NSScrollView {
                    scrollView = sv
                    break
                }
                next = next?.superview
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScroll),
                name: .consoleScroll,
                object: nil
            )
        } else {
            NotificationCenter.default.removeObserver(self, name: .consoleScroll, object: nil)
            scrollView = nil
        }
    }

    @objc func handleScroll(_ note: Notification) {
        guard let dy = note.userInfo?["dy"] as? CGFloat else { return }
        let speed: CGFloat = 40
        let delta = -dy * speed

        guard let sv = scrollView else {
            // Lazy-find: retry once when the scroll notification fires but view is not yet connected
            var next = superview
            while next != nil {
                if let sv = next as? NSScrollView {
                    self.scrollView = sv
                    break
                }
                next = next?.superview
            }
            return
        }
        let clip = sv.contentView
        var origin = clip.bounds.origin
        origin.y += delta
        origin.y = max(0, origin.y)
        clip.scroll(to: origin)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
