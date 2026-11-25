import CoreHaptics
import SwiftUI
import UIKit
import WebKit

/// Shows the bundled Anatomia web app. All files (HTML, images, 3D models, translations) ship inside the
/// app bundle in the "Web" folder and are served through a custom URL scheme, so the app
/// works completely offline and XHR/fetch requests for the 3D models behave like on a web server.
/// The page talks to the app through two message handlers: "haptic" (vibration patterns, HapticBridge)
/// and "share" (the progress backup as a file in the share sheet, ShareBridge). Its alert() and
/// confirm() dialogs are shown as native alerts (Coordinator) - a WKWebView shows none on its own.
struct WebAppView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(HapticBridge(), name: HapticBridge.name)
        config.userContentController.add(ShareBridge(), name: ShareBridge.name)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.957, green: 0.965, blue: 0.984, alpha: 1)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) {
            // lets Safari's Web Inspector attach while debugging
            webView.isInspectable = true
        }
        webView.load(URLRequest(url: URL(string: "\(BundleSchemeHandler.scheme)://app/index.html")!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    /// Shows the page's alert(), confirm() and prompt() as native alerts.
    final class Coordinator: NSObject, WKUIDelegate {
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            if !show(alert, over: webView) { completionHandler() }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Self.cancelTitle, style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            if !show(alert, over: webView) { completionHandler(false) }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { field in field.text = defaultText }
            alert.addAction(UIAlertAction(title: Self.cancelTitle, style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                completionHandler(alert?.textFields?.first?.text)
            })
            if !show(alert, over: webView) { completionHandler(nil) }
        }

        private func show(_ alert: UIAlertController, over webView: WKWebView) -> Bool {
            guard let top = topViewController(webView.window?.rootViewController) else { return false }
            top.present(alert, animated: true)
            return true
        }

        static var cancelTitle: String {
            let lang = String((Locale.preferredLanguages.first ?? "").prefix(2))
            switch lang {
            case "de": return "Abbrechen"
            case "es": return "Cancelar"
            case "sv", "nb", "no", "nn": return "Avbryt"
            default: return "Cancel"
            }
        }
    }
}

/// The view controller on top, to show alerts and the share sheet from.
func topViewController(_ root: UIViewController?) -> UIViewController? {
    var top = root
    while let presented = top?.presentedViewController {
        top = presented
    }
    return top
}

/// Plays the app's vibration patterns. The page posts one pattern as a list of steps
/// [kind, delay in ms, strength 0...1, length in s]: a tap ("light", "medium", "heavy", "soft", "rigid"),
/// the system's patterns ("success", "warning", "error"), the lightest tick ("select") or a longer
/// vibration ("buzz", with Core Haptics).
final class HapticBridge: NSObject, WKScriptMessageHandler {
    static let name = "haptic"

    private let taps: [String: UIImpactFeedbackGenerator] = [
        "light": UIImpactFeedbackGenerator(style: .light),
        "medium": UIImpactFeedbackGenerator(style: .medium),
        "heavy": UIImpactFeedbackGenerator(style: .heavy),
        "soft": UIImpactFeedbackGenerator(style: .soft),
        "rigid": UIImpactFeedbackGenerator(style: .rigid),
    ]
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    private lazy var engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine() else { return nil }
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak engine] in
            _ = try? engine?.start()
        }
        return engine
    }()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let steps = message.body as? [Any] else { return }
        taps.values.forEach { $0.prepare() }
        notification.prepare()
        for case let step as [Any] in steps {
            guard let kind = step.first as? String else { continue }
            let delay = Self.number(step, 1) ?? 0
            let strength = Self.number(step, 2)
            let length = Self.number(step, 3)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay / 1000) { [weak self] in
                self?.play(kind, strength: strength, length: length)
            }
        }
    }

    private static func number(_ step: [Any], _ index: Int) -> Double? {
        step.count > index ? (step[index] as? NSNumber)?.doubleValue : nil
    }

    private func play(_ kind: String, strength: Double?, length: Double?) {
        switch kind {
        case "success": notification.notificationOccurred(.success)
        case "warning": notification.notificationOccurred(.warning)
        case "error": notification.notificationOccurred(.error)
        case "select": selection.selectionChanged()
        case "buzz": buzz(strength: strength ?? 0.8, length: length ?? 0.3)
        default:
            guard let tap = taps[kind] else { return }
            if let strength = strength {
                tap.impactOccurred(intensity: CGFloat(min(max(strength, 0), 1)))
            } else {
                tap.impactOccurred()
            }
        }
    }

    /// A longer vibration with Core Haptics; a heavy tap where the device has none.
    private func buzz(strength: Double, length: Double) {
        guard let engine = engine else {
            taps["heavy"]?.impactOccurred()
            return
        }
        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(min(max(strength, 0), 1))),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35),
                ],
                relativeTime: 0,
                duration: length
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.start()
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            taps["heavy"]?.impactOccurred()
        }
    }
}

/// Shares a text as a file through the share sheet (save to Files, AirDrop ...): the progress backup.
/// The page posts { name: "anatomia-fortschritt-2026-11-19.json", text: "..." }.
final class ShareBridge: NSObject, WKScriptMessageHandler {
    static let name = "share"

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let text = body["text"] as? String,
              let view = message.webView else { return }
        let given = (body["name"] as? String) ?? ""
        let fileName = given.isEmpty ? "anatomia.json" : (given as NSString).lastPathComponent
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return
        }
        guard let top = topViewController(view.window?.rootViewController) else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        top.present(sheet, animated: true)
    }
}

/// Serves files from the bundled "Web" folder for URLs like anatomia://app/index.html.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "anatomia"

    private let root: URL = {
        let url = Bundle.main.resourceURL!.appendingPathComponent("Web", isDirectory: true)
        return url.standardizedFileURL
    }()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL

        guard file.path.hasPrefix(root.path), let data = try? Data(contentsOf: file) else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain"])!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(Data("Not found".utf8))
            urlSchemeTask.didFinish()
            return
        }

        let headers = [
            "Content-Type": Self.mimeType(for: file.pathExtension),
            "Content-Length": String(data.count),
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache",
        ]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // responses are delivered synchronously in start(), nothing to cancel
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "webmanifest": return "application/manifest+json"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        case "glb": return "model/gltf-binary"
        case "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
