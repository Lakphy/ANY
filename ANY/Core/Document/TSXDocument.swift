import AppKit
import Observation
import SwiftUI
import WebKit

/// Renders a model-written TSX module with the bundled component kit, in a web view that can't
/// reach the network, open windows or navigate. One instance per document; its web view is reused
/// across SwiftUI updates so scrolling a list doesn't reload it.
@Observable
final class TSXDocument {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(stage: String, message: String)
    }

    private(set) var state = State.idle
    private(set) var height: CGFloat = 0
    /// The module's `export const text`, once it has rendered.
    private(set) var text: String?
    private(set) var source: String?

    @ObservationIgnored var onCopy: ((String) -> Void)?
    /// Text the user has selected in the page; the web view never takes focus, so ⌘C asks for it here.
    @ObservationIgnored private var selection = ""
    @ObservationIgnored private static weak var lastSelected: TSXDocument?

    /// The selection in the document the user most recently selected text in, while it's on screen.
    static var selectedText: String? {
        guard let document = lastSelected, document.webView.window != nil, !document.selection.isEmpty else { return nil }
        return document.selection
    }
    @ObservationIgnored private var isRevealed = false

    @ObservationIgnored private var pending: CheckedContinuation<Result<String?, TSXDocumentError>, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private lazy var bridge = TSXDocumentBridge(document: self)
    @ObservationIgnored private(set) lazy var webView: TSXDocumentWebView = makeWebView()

    /// The web view reaches this far into the card's padding, and the page pads its content by the
    /// same amount, so hover highlights can extend past the text like native rows without being clipped.
    static let bleed = EdgeInsets(top: Theme.Space.xs, leading: Theme.Space.s, bottom: Theme.Space.xs, trailing: Theme.Space.s)
    /// The width the content is laid out at before SwiftUI sizes the view.
    static let initialWidth: CGFloat = Theme.Metrics.panelWidth - 2 * (Theme.Metrics.listInset + Theme.Metrics.cardPadding) + bleed.leading + bleed.trailing
    private static let renderTimeout = Duration.seconds(5)

    /// Renders `source`, resolving to its `text` export or the first error.
    @discardableResult
    func load(_ source: String) async -> Result<String?, TSXDocumentError> {
        finish(.failure(.superseded))
        self.source = source
        state = .loading
        text = nil
        selection = ""
        isRevealed = false
        webView.loadHTMLString(Self.html(for: source), baseURL: nil)

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.renderTimeout)
            guard !Task.isCancelled else { return }
            self?.fail(stage: "render", message: "渲染超时")
        }
        return await withCheckedContinuation { pending = $0 }
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["t"] as? String else { return }
        switch type {
        case "ready":
            text = message["text"] as? String
            updateHeight(message["height"])
            state = .ready
            finish(.success(text))
        case "height":
            updateHeight(message["height"])
        case "error":
            fail(stage: message["stage"] as? String ?? "run", message: message["message"] as? String ?? "未知错误")
        case "copy":
            if let text = message["text"] as? String, !text.isEmpty { onCopy?(text) }
        case "selection":
            selection = message["text"] as? String ?? ""
            if !selection.isEmpty { Self.lastSelected = self }
        case "link":
            if let href = message["href"] as? String, let url = URL(string: href), ["http", "https"].contains(url.scheme) {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    /// Plays the document's entrance animation, once, when it first comes on screen.
    func reveal() {
        guard state == .ready, !isRevealed else { return }
        isRevealed = true
        webView.evaluateJavaScript("ANYKit.reveal()")
    }

    private func fail(stage: String, message: String) {
        // Errors after a successful render (say, in a click handler) are shown by the document itself.
        guard state != .ready else { return }
        state = .failed(stage: stage, message: message)
        finish(.failure(.failed(stage: stage, message: message)))
    }

    private func finish(_ result: Result<String?, TSXDocumentError>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pending?.resume(returning: result)
        pending = nil
    }

    private func updateHeight(_ value: Any?) {
        guard let value = value as? Double, value > 0 else { return }
        height = CGFloat(value)
    }

    private func makeWebView() -> TSXDocumentWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(bridge, name: "any")
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.runtime, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        configuration.suppressesIncrementalRendering = true

        let webView = TSXDocumentWebView(frame: CGRect(x: 0, y: 0, width: Self.initialWidth, height: 1), configuration: configuration)
        webView.navigationDelegate = bridge
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }

    // MARK: - Page

    private static let runtime: String = {
        guard let url = Bundle.main.url(forResource: "runtime", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return script
    }()

    /// The kit's component reference, written for the model.
    static let reference: String = {
        guard let url = Bundle.main.url(forResource: "kit-reference", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }()

    private static let contentSecurityPolicy = [
        "default-src 'none'",
        "script-src 'unsafe-inline' 'unsafe-eval'",
        "style-src 'unsafe-inline'",
        "img-src data:",
        "connect-src 'none'",
        "form-action 'none'",
        "base-uri 'none'",
    ].joined(separator: "; ")

    private static func html(for source: String) -> String {
        """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        </head>
        <body><div id="root"></div>
        <script type="application/json" id="any-source">\(scriptSafe(jsonString(source)))</script>
        </body>
        </html>
        """
    }

    private static func jsonString(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text], options: [.fragmentsAllowed]),
              let array = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    /// Keeps "</script>" inside the JSON from closing the tag; "<\/" means the same inside a JSON string.
    private static func scriptSafe(_ script: String) -> String {
        script.replacingOccurrences(of: "</", with: "<\\/")
    }
}

enum TSXDocumentError: Error, Equatable {
    case failed(stage: String, message: String)
    case superseded
}

/// Doesn't take keyboard focus from the launcher, and hands scrolling to the list it sits in.
final class TSXDocumentWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

/// Holds the document weakly so the web view's script handler doesn't keep it alive.
private final class TSXDocumentBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var document: TSXDocument?

    init(document: TSXDocument) {
        self.document = document
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        document?.receive(message.body)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        action.request.url?.absoluteString == "about:blank" ? .allow : .cancel
    }
}

/// Shows a document at its content height.
struct TSXDocumentView: View {
    let document: TSXDocument

    var body: some View {
        WebViewHost(webView: document.webView)
            .frame(height: max(document.height, 1))
            .padding(.horizontal, -TSXDocument.bleed.leading)
            .padding(.vertical, -TSXDocument.bleed.top)
            .onAppear { document.reveal() }
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: TSXDocumentWebView

    func makeNSView(context: Context) -> TSXDocumentWebView { webView }
    func updateNSView(_ view: TSXDocumentWebView, context: Context) {}
}
