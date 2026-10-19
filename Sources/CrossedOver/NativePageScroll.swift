import AppKit
import SwiftUI

/// Fixed pages use an AppKit document whose height changes only with content or
/// viewport width. Scrolling never feeds intrinsic-size constraints back into
/// the outer SwiftUI layout. Libraries retain SwiftUI's lazy virtualization.
struct NativePageScroll<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content

    struct Document: View {
        let content: Content
        var body: some View {
            content.environment(\.colorScheme, .dark).fixedSize(horizontal: false, vertical: true)
        }
    }
    final class Coordinator {
        var controller: NSHostingController<Document>?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class PageScrollView: NSScrollView {
        var measure: ((CGFloat) -> CGFloat)?
        var contentChanged = true
        private var measuredWidth: CGFloat = -1
        private var measuredHeight: CGFloat = 0
        override func layout() {
            super.layout()
            guard let documentView else { return }
            let width = contentSize.width
            guard width > 0 else { return }
            if contentChanged || width != measuredWidth {
                contentChanged = false; measuredWidth = width
                measuredHeight = ceil(measure?(width) ?? 0)
            }
            let size = NSSize(width: width, height: max(contentSize.height, measuredHeight))
            if documentView.frame.size != size { documentView.setFrameSize(size) }
        }
    }

    func makeNSView(context: Context) -> PageScrollView {
        let scroll = PageScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.contentView.wantsLayer = true
        let controller = NSHostingController(rootView: Document(content: content()))
        controller.sizingOptions = []
        controller.safeAreaRegions = []
        context.coordinator.controller = controller
        controller.view.wantsLayer = true
        scroll.documentView = controller.view
        scroll.measure = { [weak controller] width in
            controller?.sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude)).height ?? 0
        }
        return scroll
    }

    func updateNSView(_ scroll: PageScrollView, context: Context) {
        context.coordinator.controller?.rootView = Document(content: content())
        scroll.contentChanged = true
        scroll.needsLayout = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PageScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 600)
    }
}
