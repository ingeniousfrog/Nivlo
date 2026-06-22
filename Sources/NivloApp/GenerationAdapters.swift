import Foundation
import NivloDomain
import Security

enum APIKeyStore {
  private static let service = "dev.nivlo.generation-api-key"

  static func load(providerID: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: providerID,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
      let data = item as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return value
  }

  static func save(providerID: String, apiKey: String) throws {
    let data = Data(apiKey.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: providerID,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
    ]
    let status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let updateStatus = SecItemUpdate(
        query as CFDictionary,
        attributes as CFDictionary
      )
      guard updateStatus == errSecSuccess else {
        throw GenerationError.providerUnavailable("Could not update API key.")
      }
    } else if status != errSecSuccess {
      throw GenerationError.providerUnavailable("Could not store API key.")
    }
  }
}

struct OpenAIGenerationAdapter: GenerationAdapter {
  let id = "openai-images"
  let displayName = "OpenAI Images"
  let capabilities: Set<GenerationCapability> = [.textToImage, .imageToImage]

  func generate(_ request: GenerationRequest) async throws -> GenerationResult {
    guard capabilities.contains(request.capability) else {
      throw GenerationError.unsupportedCapability(request.capability)
    }
    guard let apiKey = APIKeyStore.load(providerID: id), !apiKey.isEmpty else {
      throw GenerationError.missingAPIKey
    }

    let endpoint = URL(string: "https://api.openai.com/v1/images/generations")!
    var body: [String: Any] = [
      "model": "gpt-image-1",
      "prompt": request.prompt,
      "size": "1024x1024",
    ]
    if request.capability == .imageToImage, let sourceURL = request.sourceImageURL {
      let imageData = try Data(contentsOf: sourceURL)
      body["image"] = imageData.base64EncodedString()
    }

    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let detail = String(data: data, encoding: .utf8) ?? "Request failed."
      throw GenerationError.providerUnavailable(detail)
    }

    guard
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let items = json["data"] as? [[String: Any]],
      let first = items.first,
      let base64 = first["b64_json"] as? String,
      let imageData = Data(base64Encoded: base64)
    else {
      throw GenerationError.invalidResponse
    }

    try imageData.write(to: request.outputURL, options: .atomic)
    return GenerationResult(
      outputURL: request.outputURL,
      providerID: id,
      model: "gpt-image-1",
      parameters: [
        "prompt": request.prompt,
        "capability": request.capability.rawValue,
      ]
    )
  }
}

struct LocalGenerationAdapter: GenerationAdapter {
  let id = "local-model"
  let displayName = "Local Model"
  let capabilities: Set<GenerationCapability> = Set(GenerationCapability.allCases)

  func generate(_ request: GenerationRequest) async throws -> GenerationResult {
    throw GenerationError.providerUnavailable(
      "Local model adapter is not configured yet. Add a model path in a future release."
    )
  }
}

enum GenerationAdapterRegistry {
  static let all: [any GenerationAdapter] = [
    OpenAIGenerationAdapter(),
    LocalGenerationAdapter(),
  ]
}
