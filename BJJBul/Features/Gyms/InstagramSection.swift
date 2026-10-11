import SwiftUI
import WebKit

/// Instagram card (opens the profile) plus an optional admin-set embed (no scraping).
struct InstagramSection: View {
    let gym: Gym

    private var embedURL: URL? {
        guard let url = gym.instagramEmbedURL,
              url.scheme == "https",
              let host = url.host, host.hasSuffix("instagram.com") else { return nil }
        return url
    }

    var body: some View {
        if let handle = gym.instagram, let profileURL = Links.instagram(handle) {
            Section("instagram.title") {
                Link(destination: profileURL) {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(
                                LinearGradient(colors: [Color.purple, Color.pink, Color.orange],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: displayHandle(handle))
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            Text("instagram.open")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
                if let embedURL {
                    InstagramEmbedView(url: embedURL)
                        .frame(height: 520)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
    }

    private func displayHandle(_ handle: String) -> String {
        if let url = URL(string: handle), url.host?.contains("instagram.com") == true {
            let name = url.pathComponents.filter { $0 != "/" }.first ?? handle
            return "@\(name)"
        }
        return handle.hasPrefix("@") ? handle : "@\(handle)"
    }
}

/// Loads an official Instagram embed URL (e.g. https://www.instagram.com/p/<code>/embed). Taps open externally.
struct InstagramEmbedView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(initialURL: url)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let initialURL: URL

        init(initialURL: URL) {
            self.initialURL = initialURL
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let target = navigationAction.request.url {
                UIApplication.shared.open(target)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
