import Foundation

// Optional personal-use integration: credentials stay in memory and go only to OpenAI.
enum ArtGenerator {
    static func request(prompt: String, apiKey: String) throws -> URLRequest {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw StudioError("Enter an OpenAI API key in this window first.") }
        guard !prompt.isEmpty, prompt.count <= 500 else { throw StudioError("Describe your icon in 1–500 characters.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-image-2", "size": "1024x1024", "quality": "low", "n": 1,
            "prompt": "Create a single original pixel art icon for a child's audio player. Subject: \(prompt). Draw on an exact 16 by 16 logical pixel grid enlarged to 1024 by 1024 using uniform 64px square pixels. Pure black background. Center one bold recognizable silhouette with a one-pixel empty border. Use at most six bright flat colors. No text, no letters, no watermark, no gradients, no shadows, no tiny details, no grid lines. Make it legible when reduced to 16 by 16 pixels."
        ])
        return request
    }
    static func pixels(data: Data, status: Int) throws -> [UInt32] {
        guard (200..<300).contains(status) else {
            switch status {
            case 401: throw StudioError("OpenAI rejected the API key. Check the key and try again.")
            case 403: throw StudioError("Your OpenAI project does not have access to this image model.")
            case 429: throw StudioError("OpenAI reported a usage or rate limit. Check your API billing and limits before retrying.")
            default: throw StudioError("Image generation failed (HTTP \(status)). You can retry or choose a library icon.")
            }
        }
        guard let result = try JSONSerialization.jsonObject(with: data) as? JSON,
              let images = result["data"] as? [JSON], let encoded = images.first?["b64_json"] as? String,
              let image = Data(base64Encoded: encoded) else { throw StudioError("OpenAI returned no usable image. Your track artwork has not changed.") }
        return try PixelArt.importImageData(image)
    }
    static func generate(prompt: String, apiKey: String) async throws -> [UInt32] {
        let request = try request(prompt: prompt, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw StudioError("No response from the image service.") }
        return try pixels(data: data, status: response.statusCode)
    }
}
