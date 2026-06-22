import Foundation

public enum GenerationCapability: String, Codable, Sendable, CaseIterable {
  case textToImage
  case imageToImage
  case inpaint
  case outpaint
  case backgroundRemoval
  case superResolution
  case styleVariant
}

public struct GenerationRequest: Sendable, Equatable {
  public let capability: GenerationCapability
  public let prompt: String
  public let negativePrompt: String
  public let sourceImageURL: URL?
  public let maskImageURL: URL?
  public let strength: Double
  public let steps: Int
  public let seed: Int?
  public let outputURL: URL

  public init(
    capability: GenerationCapability,
    prompt: String,
    negativePrompt: String = "",
    sourceImageURL: URL? = nil,
    maskImageURL: URL? = nil,
    strength: Double = 0.75,
    steps: Int = 30,
    seed: Int? = nil,
    outputURL: URL
  ) {
    self.capability = capability
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.sourceImageURL = sourceImageURL
    self.maskImageURL = maskImageURL
    self.strength = strength
    self.steps = steps
    self.seed = seed
    self.outputURL = outputURL
  }
}

public struct GenerationResult: Sendable, Equatable {
  public let outputURL: URL
  public let providerID: String
  public let model: String
  public let parameters: [String: String]

  public init(
    outputURL: URL,
    providerID: String,
    model: String,
    parameters: [String: String]
  ) {
    self.outputURL = outputURL
    self.providerID = providerID
    self.model = model
    self.parameters = parameters
  }
}

public protocol GenerationAdapter: Sendable {
  var id: String { get }
  var displayName: String { get }
  var capabilities: Set<GenerationCapability> { get }
  func generate(_ request: GenerationRequest) async throws -> GenerationResult
}

public enum GenerationError: Error, LocalizedError, Sendable {
  case missingAPIKey
  case unsupportedCapability(GenerationCapability)
  case providerUnavailable(String)
  case invalidResponse

  public var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      "An API key is required for this provider."
    case .unsupportedCapability(let capability):
      "This provider does not support \(capability.rawValue)."
    case .providerUnavailable(let detail):
      detail
    case .invalidResponse:
      "The provider returned an invalid response."
    }
  }
}
