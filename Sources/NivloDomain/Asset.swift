import Foundation

public struct AssetID: Hashable, Codable, Sendable {
  public let volumeIdentifier: String
  public let fileIdentifier: String

  public init(volumeIdentifier: String, fileIdentifier: String) {
    self.volumeIdentifier = volumeIdentifier
    self.fileIdentifier = fileIdentifier
  }
}

public struct ImageAsset: Identifiable, Hashable, Codable, Sendable {
  public let id: AssetID
  public let url: URL
  public let filename: String
  public let contentType: String
  public let fileSize: Int64
  public let createdAt: Date?
  public let modifiedAt: Date?
  public let pixelWidth: Int?
  public let pixelHeight: Int?

  public init(
    id: AssetID,
    url: URL,
    filename: String,
    contentType: String,
    fileSize: Int64,
    createdAt: Date?,
    modifiedAt: Date?,
    pixelWidth: Int?,
    pixelHeight: Int?
  ) {
    self.id = id
    self.url = url
    self.filename = filename
    self.contentType = contentType
    self.fileSize = fileSize
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }
}
