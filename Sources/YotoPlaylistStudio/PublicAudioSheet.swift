import SwiftUI
import WebKit

@MainActor
final class PublicAudioBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var collection: PublicAudioCollection?
    @Published var selected = Set<String>()
    @Published var busy = false
    @Published var error: String?
    @Published var shareLink = ""
    private var task: Task<Void, Never>?
    override init() {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.load(URLRequest(url: PublicAudio.catalogURL))
    }
    func loadShare(_ input: String) {
        task?.cancel(); busy = true; error = nil; collection = nil; selected = []
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await PublicAudio.loadCollection(input)
                try Task.checkCancellation()
                collection = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func close() { task?.cancel(); webView.stopLoading(); webView.navigationDelegate = nil; webView.uiDelegate = nil }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if (try? PublicAudio.shareURL(url.absoluteString)) != nil {
            decisionHandler(.cancel); shareLink = url.absoluteString; loadShare(url.absoluteString); return
        }
        if url.scheme == "https", ["yoto.space", "www.yoto.space"].contains(url.host?.lowercased() ?? "") {
            if action.targetFrame == nil { decisionHandler(.cancel); webView.load(action.request) }
            else { decisionHandler(.allow) }
        } else if action.targetFrame?.isMainFrame == false && url.scheme == "https" { decisionHandler(.allow) }
        else { decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { self.error = "The catalog could not load. Try Reload, or paste a Yoto share link below." }
    }
}

private struct PublicAudioWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct PublicAudioSheet: View {
    let onSelected: ([PublicAudioTrack]) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = PublicAudioBrowser()
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Public-domain audio").font(.title2.bold()); Spacer()
                Button("Catalog") { browser.collection = nil; browser.webView.load(URLRequest(url: PublicAudio.catalogURL)) }
                Button("Reload") { browser.webView.reload() }
                Button("Close") { dismiss() }
            }
            Text("Browse Yoto Space and click Add to your library to preview its tracks here. Choose chapters, then prepare local MP3s before uploading to your selected playlist.").font(.callout).foregroundStyle(.secondary)
            if let collection = browser.collection {
                HStack {
                    Text(collection.title).font(.headline); Spacer()
                    Button("All") { browser.selected = Set(collection.tracks.map(\.id)) }
                    Button("None") { browser.selected = [] }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(collection.tracks) { track in
                            Toggle(isOn: Binding(get: { browser.selected.contains(track.id) }, set: { on in if on { browser.selected.insert(track.id) } else { browser.selected.remove(track.id) } })) {
                                HStack {
                                    if let url = track.artworkURL { AsyncImage(url: url) { image in image.resizable().interpolation(.none).scaledToFit() } placeholder: { Image(systemName: "music.note") }.frame(width: 28, height: 28) }
                                    Text(track.title).font(.callout)
                                }
                            }.toggleStyle(.checkbox)
                        }
                    }.padding(12)
                }.frame(height: 360)
                Button("Prepare \(browser.selected.count) selected track(s)…") {
                    onSelected(collection.tracks.filter { browser.selected.contains($0.id) }); dismiss()
                }.buttonStyle(.borderedProminent).disabled(browser.selected.isEmpty)
            } else {
                HStack {
                    TextField("Find a book on this page", text: $search).textFieldStyle(.roundedBorder)
                    Button("Find") { browser.webView.find(search, configuration: WKFindConfiguration()) { _ in } }.disabled(search.isEmpty)
                }
                PublicAudioWebView(webView: browser.webView).frame(height: 390).cornerRadius(8)
            }
            HStack {
                TextField("Or paste a share.yoto.co/s/… link", text: $browser.shareLink).textFieldStyle(.roundedBorder).disabled(browser.busy)
                Button("Load tracks") { browser.loadShare(browser.shareLink) }.disabled(browser.busy || browser.shareLink.isEmpty)
            }
            if browser.busy { HStack { ProgressView().controlSize(.small); Text("Loading shared tracks…").font(.caption) } }
            if let error = browser.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Text("Browsing uses Yoto Space. No Yoto account credentials are sent to it. Source audio and available artwork are copied only for the tracks you choose. Large books may take time to prepare.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 900)
        .onDisappear { browser.close() }
    }
}
