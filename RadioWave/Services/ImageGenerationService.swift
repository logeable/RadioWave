import AppKit
import Combine
import Foundation
import Security

@MainActor
final class ImageGenerationService: ObservableObject {
    static let shared = ImageGenerationService()

    @Published var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Keys.baseURL) }
    }

    @Published var apiKey: String {
        didSet { APIKeychain.save(apiKey) }
    }

    @Published var selectedModel: String {
        didSet { defaults.set(selectedModel, forKey: Keys.selectedModel) }
    }

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            RadioWaveLog.info("Music background generation enabled=\(isEnabled)", category: "ImageGeneration")
        }
    }

    @Published var backgroundTransparency: Double {
        didSet { defaults.set(backgroundTransparency, forKey: Keys.backgroundTransparency) }
    }

    @Published var backgroundBlurRadius: Double {
        didSet { defaults.set(backgroundBlurRadius, forKey: Keys.backgroundBlurRadius) }
    }

    @Published private(set) var availableModels: [String] = []
    @Published private(set) var isLoadingModels = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusIsError = false

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedModel.isEmpty
    }

    private let defaults: UserDefaults
    private let session: URLSession

    private enum Keys {
        static let baseURL = "RadioWave.imageGeneration.baseURL"
        static let selectedModel = "RadioWave.imageGeneration.selectedModel"
        static let isEnabled = "RadioWave.imageGeneration.isEnabled"
        static let backgroundTransparency = "RadioWave.imageGeneration.backgroundTransparency"
        static let backgroundBlurRadius = "RadioWave.imageGeneration.backgroundBlurRadius"
    }

    private init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        baseURL = defaults.string(forKey: Keys.baseURL) ?? ""
        apiKey = APIKeychain.load()
        selectedModel = defaults.string(forKey: Keys.selectedModel) ?? ""
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        backgroundTransparency = defaults.object(forKey: Keys.backgroundTransparency) as? Double ?? 0.82
        backgroundBlurRadius = defaults.object(forKey: Keys.backgroundBlurRadius) as? Double ?? 20
    }

    func refreshModels() async {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        statusMessage = nil
        defer { isLoadingModels = false }

        let host = configuredHost
        RadioWaveLog.info("Requesting image model list from host=\(host)", category: "ImageGeneration")

        do {
            let url = try endpointURL("models")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            addAuthorization(to: &request)
            let (data, response) = try await session.data(for: request)
            try validate(response)

            let object = try JSONSerialization.jsonObject(with: data)
            let root = object as? [String: Any]
            let rows = root?["data"] as? [[String: Any]] ?? (object as? [[String: Any]]) ?? []
            let models = Array(Set(rows.compactMap { $0["id"] as? String })).sorted()
            guard !models.isEmpty else {
                throw ImageGenerationError.noModels
            }

            availableModels = models
            if selectedModel.isEmpty {
                selectedModel = models[0]
            }
            statusMessage = "已加载 \(models.count) 个模型"
            statusIsError = false
            RadioWaveLog.info(
                "Loaded \(models.count) image models from host=\(host), selected=\(selectedModel)",
                category: "ImageGeneration"
            )
        } catch {
            statusMessage = "获取模型失败：\(error.localizedDescription)"
            statusIsError = true
            RadioWaveLog.warning(
                "Image model list request failed for host=\(host): \(error.localizedDescription)",
                category: "ImageGeneration"
            )
        }
    }

    func generateBackground(for title: String) async -> NSImage? {
        guard isEnabled, isConfigured else { return nil }

        let startedAt = Date()
        let host = configuredHost
        let model = selectedModel
        RadioWaveLog.info(
            "Starting track background generation, model=\(model), host=\(host)",
            category: "ImageGeneration"
        )

        do {
            let url = try endpointURL("images/generations")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            addAuthorization(to: &request)
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": selectedModel,
                "prompt": "使用符合音乐抽象美学的画风绘画 关于 《\(title)》 音乐的背景，整体有质感适合作为唱片封面，符合对应音乐的调性",
                "size": "1024x1024",
                "n": 1
            ])

            let (data, response) = try await session.data(for: request)
            try validate(response)
            guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let firstImage = (payload["data"] as? [[String: Any]])?.first else {
                throw ImageGenerationError.invalidImageResponse
            }

            if let encodedImage = firstImage["b64_json"] as? String,
               let imageData = Data(base64Encoded: encodedImage),
               let image = NSImage(data: imageData) {
                logGenerationSuccess(model: model, host: host, delivery: "base64", bytes: imageData.count, startedAt: startedAt)
                return image
            }

            if let imageURLString = firstImage["url"] as? String,
               let imageURL = URL(string: imageURLString) {
                let (imageData, imageResponse) = try await session.data(from: imageURL)
                try validate(imageResponse)
                guard let image = NSImage(data: imageData) else {
                    throw ImageGenerationError.invalidImageResponse
                }
                logGenerationSuccess(model: model, host: host, delivery: "url", bytes: imageData.count, startedAt: startedAt)
                return image
            }

            throw ImageGenerationError.invalidImageResponse
        } catch {
            let nsError = error as NSError
            if error is CancellationError || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
                RadioWaveLog.debug(
                    "Track background generation cancelled, model=\(model), host=\(host)",
                    category: "ImageGeneration"
                )
            } else {
                RadioWaveLog.warning(
                    "Track background generation failed, model=\(model), host=\(host), elapsed_ms=\(elapsedMilliseconds(since: startedAt)): \(error.localizedDescription)",
                    category: "ImageGeneration"
                )
            }
            return nil
        }
    }

    private func endpointURL(_ endpoint: String) throws -> URL {
        let address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(),
              components.host != nil,
              scheme == "https" || scheme == "http" else {
            throw ImageGenerationError.invalidAddress
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpoint].filter { !$0.isEmpty }.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw ImageGenerationError.invalidAddress
        }
        return url
    }

    private func addAuthorization(to request: inout URLRequest) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }
    }

    private var configuredHost: String {
        URLComponents(string: baseURL)?.host ?? "invalid"
    }

    private func logGenerationSuccess(model: String, host: String, delivery: String, bytes: Int, startedAt: Date) {
        RadioWaveLog.info(
            "Track background generated, model=\(model), host=\(host), delivery=\(delivery), bytes=\(bytes), elapsed_ms=\(elapsedMilliseconds(since: startedAt))",
            category: "ImageGeneration"
        )
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1_000)
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImageGenerationError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ImageGenerationError.httpStatus(httpResponse.statusCode)
        }
    }
}

private enum ImageGenerationError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case invalidImageResponse
    case noModels
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "请输入有效的 HTTP 或 HTTPS API 地址"
        case .invalidResponse:
            "服务器返回了无效响应"
        case .invalidImageResponse:
            "响应中没有可用的图片"
        case .noModels:
            "/models 接口没有返回模型列表"
        case .httpStatus(let statusCode):
            "服务器返回 HTTP \(statusCode)"
        }
    }
}

private enum APIKeychain {
    private static let service = "com.logeable.RadioWave.image-generation"
    private static let account = "api-key"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func save(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let attributes = [kSecValueData as String: Data(trimmedValue.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertQuery = query
            insertQuery[kSecValueData as String] = Data(trimmedValue.utf8)
            SecItemAdd(insertQuery as CFDictionary, nil)
        }
    }
}
