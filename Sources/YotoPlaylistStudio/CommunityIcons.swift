import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct CommunitySelection: Identifiable {
    let id = UUID()
    let trackIDs: Set<String>
    let title: String
    let query: String
}

enum CommunitySource: String, CaseIterable, Identifiable {
    case yotoIcons = "Yoto Icons"
    case everything = "Yoto Everything"
    var id: String { rawValue }
    var host: String { self == .yotoIcons ? "www.yotoicons.com" : "www.yotoeverything.com" }
    func url(query: String) -> URL {
        var url = URLComponents(string: "https://\(host)/icons")!
        if self == .yotoIcons && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            url.queryItems = [URLQueryItem(name: "tag", value: query), URLQueryItem(name: "sort", value: "popular"), URLQueryItem(name: "type", value: "singles")]
        }
        return url.url!
    }
    static func suggestedQuery(_ title: String) -> String {
        let words = IconSuggestions.words(title)
        if words.contains("polar") && words.contains("bear") { return "polar bear" }
        return String(title.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: ".mp4", with: "").prefix(100))
    }
    static func isImage(_ url: URL) -> Bool { ["png", "gif", "jpg", "jpeg", "webp"].contains(url.pathExtension.lowercased()) }
    static func allowedPage(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return ["yotoicons.com", "www.yotoicons.com", "yotoeverything.com", "www.yotoeverything.com"].contains(host)
    }
}

@MainActor
final class CommunityBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    @Published var source = CommunitySource.yotoIcons
    @Published var query: String
    @Published var message = "Choose an icon, then click its Download button to preview it here."
    @Published var pixels: [UInt32]?
    @Published var importedSource = ""
    @Published var loading = false
    let webView: WKWebView
    private var destinations: [ObjectIdentifier: URL] = [:]
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var stopped = false
    init(query: String) {
        self.query = query
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        open()
    }
    func open() {
        pixels = nil
        webView.load(URLRequest(url: source.url(query: query)))
    }
    func search() {
        if source == .everything && webView.url?.host == source.host { findOnPage() }
        else { open() }
    }
    private func findOnPage() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        webView.find(query, configuration: WKFindConfiguration()) { [weak self] result in
            self?.message = result.matchFound ? "Matching text found. Use the ↓ download button beside the icon to preview it." : "No text match on this page. Browse the categories or try a shorter subject."
        }
    }
    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .gif, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        receive(url, source: "Imported file")
    }
    private func receive(_ url: URL, source: String) {
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 8 * 1024 * 1024 else { throw StudioError("Choose an icon image smaller than 8 MB.") }
            pixels = try PixelArt.importImage(url)
            importedSource = source
            message = "Icon ready. Inspect the actual 16×16 preview, then accept or choose another. GIFs are imported as a still image."
        } catch { message = "Could not import that download. \(error.localizedDescription)" }
    }
    func close() {
        stopped = true
        webView.stopLoading()
        for download in downloads.values { download.cancel { _ in } }
        downloads = [:]
        for url in destinations.values { try? FileManager.default.removeItem(at: url) }
        destinations = [:]
        webView.navigationDelegate = nil; webView.uiDelegate = nil
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        if source == .everything { findOnPage() }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        loading = false
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        message = "This site could not load. Try Reload or another source. You can also import a downloaded icon file."
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.shouldPerformDownload || (CommunitySource.allowedPage(url) && CommunitySource.isImage(url)) {
            pixels = nil
            message = "Downloading icon for preview…"
            decisionHandler(.download)
        } else if CommunitySource.allowedPage(url) {
            decisionHandler(.allow)
        } else {
            // Browsing is confined to the two libraries. No sign-in or upload actions leave this pane.
            message = "Use the site's image download button. External links and account connections are not opened in this browser."
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame && (navigationResponse.response.mimeType?.hasPrefix("image/") == true || !navigationResponse.canShowMIMEType) {
            guard navigationResponse.response.expectedContentLength <= 8 * 1024 * 1024 else {
                message = "Choose an individual icon smaller than 8 MB."; decisionHandler(.cancel); return
            }
            pixels = nil
            decisionHandler(.download)
        } else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { attach(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { attach(download) }
    private func attach(_ download: WKDownload) {
        downloads[ObjectIdentifier(download)] = download
        download.delegate = self
        loading = false
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard !stopped else { completionHandler(nil); return }
        let ext = URL(fileURLWithPath: suggestedFilename).pathExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-community-\(UUID().uuidString)").appendingPathExtension(ext)
        destinations[ObjectIdentifier(download)] = url
        completionHandler(url)
    }
    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        defer { downloads[id] = nil }
        guard let url = destinations.removeValue(forKey: id) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        guard !stopped else { return }
        receive(url, source: download.originalRequest?.url?.host ?? source.rawValue)
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let id = ObjectIdentifier(download)
        downloads[id] = nil
        if let url = destinations.removeValue(forKey: id) { try? FileManager.default.removeItem(at: url) }
        if !stopped { message = "Download failed. Try another icon or import the file after downloading it in your usual browser." }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

struct CommunityWebView: NSViewRepresentable {
    let browser: CommunityBrowser
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct CommunitySheet: View {
    let selection: CommunitySelection
    let onAccept: ([UInt32], String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser: CommunityBrowser
    init(selection: CommunitySelection, onAccept: @escaping ([UInt32], String) -> Void) {
        self.selection = selection; self.onAccept = onAccept
        _browser = StateObject(wrappedValue: CommunityBrowser(query: selection.query))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Community icons").font(.title2.bold())
                    Text(selection.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            HStack {
                Picker("Source", selection: $browser.source) { ForEach(CommunitySource.allCases) { source in Text(source.rawValue).tag(source) } }.frame(width: 270)
                TextField("Search subject, e.g. polar bear", text: $browser.query).textFieldStyle(.roundedBorder).onSubmit { browser.search() }
                Button(browser.source == .yotoIcons ? "Search" : "Find on page") { browser.search() }
                Button("Reload") { browser.webView.reload() }
                if browser.loading { ProgressView().controlSize(.small) }
            }
            Text(browser.source == .yotoIcons ? "Choose an icon, then Download. It will appear in the preview below." : "Use ↓ to download an icon into the preview. The Yoto ↗ buttons belong to the website; save to Yoto through Playlist Studio's review instead.").font(.caption).foregroundStyle(.secondary)
            CommunityWebView(browser: browser).frame(minHeight: 350).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 16) {
                if let pixels = browser.pixels {
                    Image(nsImage: PixelArt.image(pixels)).interpolation(.none).resizable().frame(width: 64, height: 64).padding(8).background(.black).cornerRadius(8)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(browser.message).font(.caption)
                    if browser.pixels != nil { Text("Source: \(browser.importedSource) · 16 × 16 still image").font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                Button("Import downloaded file…") { browser.importFile() }
                Button("Accept icon") {
                    if let pixels = browser.pixels { onAccept(pixels, browser.importedSource); dismiss() }
                }.buttonStyle(.borderedProminent).disabled(browser.pixels == nil)
            }
            Text("Browsing contacts the selected site. No Yoto credentials or playlist audio are shared. Accepted art is staged for \(selection.trackIDs.count) track(s); use Review changes to save.").font(.caption2).foregroundStyle(.secondary)
        }.padding(20).frame(width: 960, height: 730)
        .onChange(of: browser.source) { _ in browser.open() }
        .onDisappear { browser.close() }
    }
}
