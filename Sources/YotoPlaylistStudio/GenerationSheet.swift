import SwiftUI

struct GenerationSheet: View {
    var row: TrackRow
    var onAccept: ([UInt32]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var key = ""
    @State private var pixels: [UInt32]?
    @State private var working = false
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create new pixel art").font(.title2.bold())
            Text(row.title).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            TextField("Describe the subject and colors", text: $prompt).textFieldStyle(.roundedBorder).disabled(working)
            SecureField("OpenAI API key (kept only while this window is open)", text: $key).textFieldStyle(.roundedBorder).disabled(working)
            Link("Get an OpenAI API key ↗", destination: URL(string: "https://platform.openai.com/api-keys")!).font(.caption)
            Text("Generate sends this description to OpenAI using your key. API charges apply separately from ChatGPT. Nothing is sent to Yoto until you accept the preview and apply your reviewed changes.").font(.caption).foregroundStyle(.secondary)
            if working { HStack { ProgressView().controlSize(.small); Text("Creating your icon…").font(.callout) } }
            if let pixels {
                HStack(spacing: 18) {
                    Image(nsImage: PixelArt.image(pixels)).interpolation(.none).resizable().frame(width: 128, height: 128).padding(12).background(.black).cornerRadius(12)
                    Text("Actual 16 × 16 preview\nCheck the subject before accepting. You can generate another version or edit accepted art in the pixel editor.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: 230)
                }
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button(working ? "Cancel generation" : "Close") { task?.cancel(); dismiss() }
                Spacer()
                Button(pixels == nil ? "Generate" : "Generate another") { generate() }.disabled(working || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt.count > 500)
                Button("Accept art") {
                    if let pixels { onAccept(pixels); dismiss() }
                }.buttonStyle(.borderedProminent).disabled(working || pixels == nil)
            }
        }.padding(28).frame(width: 520)
        .onAppear {
            let tokens = IconSuggestions.words(row.title)
            prompt = tokens.contains("polar") && tokens.contains("bear") ? "A friendly white polar bear face with round ears, dark eyes and a black nose" : row.title
        }
        .onChange(of: prompt) { _ in if !working { pixels = nil } }
        .onDisappear { task?.cancel(); key = "" }
    }
    private func generate() {
        failure = nil; pixels = nil; working = true
        let description = prompt, credential = key
        task = Task { @MainActor in
            defer { working = false }
            do {
                let result = try await ArtGenerator.generate(prompt: description, apiKey: credential)
                guard !Task.isCancelled else { return }
                pixels = result
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
        }
    }
}
