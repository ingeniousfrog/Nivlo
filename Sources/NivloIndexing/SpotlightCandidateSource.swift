import Foundation

public struct SpotlightCandidateMetadata: Sendable {
  public let url: URL?
  public let displayName: String?
  public let contentType: String?
  public let fileSize: Int64?
  public let pixelWidth: Int?
  public let pixelHeight: Int?
  public let createdAt: Date?
  public let modifiedAt: Date?

  public init(
    url: URL?,
    displayName: String?,
    contentType: String?,
    fileSize: Int64?,
    pixelWidth: Int?,
    pixelHeight: Int?,
    createdAt: Date?,
    modifiedAt: Date?
  ) {
    self.url = url
    self.displayName = displayName
    self.contentType = contentType
    self.fileSize = fileSize
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
  }
}

public struct SpotlightCandidate: Identifiable, Equatable, Sendable {
  public let id: String
  public let url: URL
  public let displayName: String
  public let contentType: String?
  public let fileSize: Int64?
  public let pixelWidth: Int?
  public let pixelHeight: Int?
  public let createdAt: Date?
  public let modifiedAt: Date?

  public init?(metadata: SpotlightCandidateMetadata) {
    guard let url = metadata.url?.standardizedFileURL, url.isFileURL else {
      return nil
    }
    self.id = url.path
    self.url = url
    if let displayName = metadata.displayName, !displayName.isEmpty {
      self.displayName = displayName
    } else {
      self.displayName = url.lastPathComponent
    }
    self.contentType = metadata.contentType
    self.fileSize = metadata.fileSize
    self.pixelWidth = metadata.pixelWidth
    self.pixelHeight = metadata.pixelHeight
    self.createdAt = metadata.createdAt
    self.modifiedAt = metadata.modifiedAt
  }
}

public struct SpotlightQueryConfiguration: Equatable, Sendable {
  public let imageContentType: String
  public let scopes: [String]
  public let resultLimit: Int
  public let timeout: Duration

  public init(
    imageContentType: String,
    scopes: [String],
    resultLimit: Int,
    timeout: Duration
  ) {
    self.imageContentType = imageContentType
    self.scopes = scopes
    self.resultLimit = resultLimit
    self.timeout = timeout
  }

  public static func images(
    resultLimit: Int = 500,
    timeout: Duration = .seconds(15)
  ) -> SpotlightQueryConfiguration {
    SpotlightQueryConfiguration(
      imageContentType: "public.image",
      scopes: [NSMetadataQueryLocalComputerScope],
      resultLimit: resultLimit,
      timeout: timeout
    )
  }
}

public enum SpotlightCandidateSourceError: Error, LocalizedError, Sendable {
  case couldNotStart

  public var errorDescription: String? {
    switch self {
    case .couldNotStart:
      "Spotlight could not start an image metadata query."
    }
  }
}

@MainActor
public protocol SpotlightDiscovering {
  func discover() async throws -> [SpotlightCandidate]
}

@MainActor
public final class SpotlightCandidateSource: SpotlightDiscovering {
  private let configuration: SpotlightQueryConfiguration

  public init(configuration: SpotlightQueryConfiguration = .images()) {
    self.configuration = configuration
  }

  public func discover() async throws -> [SpotlightCandidate] {
    let query = NSMetadataQuery()
    query.searchScopes = configuration.scopes
    query.predicate = NSPredicate(
      format: "ANY %K == %@",
      NSMetadataItemContentTypeTreeKey,
      configuration.imageContentType
    )
    query.sortDescriptors = [
      NSSortDescriptor(
        key: NSMetadataItemFSContentChangeDateKey,
        ascending: false
      )
    ]
    query.notificationBatchingInterval = 0.2

    guard query.start() else {
      throw SpotlightCandidateSourceError.couldNotStart
    }
    defer {
      query.stop()
    }

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: configuration.timeout)
    while query.isGathering {
      if clock.now >= deadline {
        break
      }
      try await Task.sleep(for: .milliseconds(50))
    }

    let count = min(query.resultCount, configuration.resultLimit)
    return (0..<count).compactMap { index in
      guard let item = query.result(at: index) as? NSMetadataItem else {
        return nil
      }
      return SpotlightCandidate(metadata: metadata(from: item))
    }
  }

  private func metadata(from item: NSMetadataItem) -> SpotlightCandidateMetadata {
    SpotlightCandidateMetadata(
      url: item.value(forAttribute: NSMetadataItemURLKey) as? URL,
      displayName: item.value(forAttribute: NSMetadataItemFSNameKey) as? String,
      contentType: item.value(forAttribute: NSMetadataItemContentTypeKey) as? String,
      fileSize: integer64(
        item.value(forAttribute: NSMetadataItemFSSizeKey)
      ),
      pixelWidth: integer(
        item.value(forAttribute: NSMetadataItemPixelWidthKey)
      ),
      pixelHeight: integer(
        item.value(forAttribute: NSMetadataItemPixelHeightKey)
      ),
      createdAt: item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date,
      modifiedAt: item.value(
        forAttribute: NSMetadataItemFSContentChangeDateKey
      ) as? Date
    )
  }

  private func integer(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue
  }

  private func integer64(_ value: Any?) -> Int64? {
    (value as? NSNumber)?.int64Value
  }
}
