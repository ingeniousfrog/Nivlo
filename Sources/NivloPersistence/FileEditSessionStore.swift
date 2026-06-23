import Foundation
import NivloDomain

public actor FileEditSessionStore {
  private let baseDirectory: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(baseDirectory: URL) {
    self.baseDirectory = baseDirectory
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    decoder = JSONDecoder()
  }

  public func imageSession(for assetID: AssetID) throws -> ImageEditSnapshot? {
    try decodeIfPresent(
      ImageEditSnapshot.self,
      from: sessionURL(kind: "images", assetID: assetID)
    )
  }

  public func saveImageSession(
    _ snapshot: ImageEditSnapshot,
    for assetID: AssetID
  ) throws {
    try encode(snapshot, to: sessionURL(kind: "images", assetID: assetID))
  }

  public func removeImageSession(for assetID: AssetID) throws {
    try removeIfPresent(sessionURL(kind: "images", assetID: assetID))
  }

  public func videoSession(for assetID: AssetID) throws -> VideoEditSession? {
    try decodeIfPresent(
      VideoEditSession.self,
      from: sessionURL(kind: "videos", assetID: assetID)
    )
  }

  public func saveVideoSession(
    _ session: VideoEditSession,
    for assetID: AssetID
  ) throws {
    try encode(session, to: sessionURL(kind: "videos", assetID: assetID))
  }

  public func removeVideoSession(for assetID: AssetID) throws {
    try removeIfPresent(sessionURL(kind: "videos", assetID: assetID))
  }

  public func adjustmentPresets() throws -> [ImageAdjustmentPreset] {
    try decodeIfPresent(
      [ImageAdjustmentPreset].self,
      from: baseDirectory.appending(path: "adjustment-presets.json")
    ) ?? []
  }

  public func saveAdjustmentPresets(
    _ presets: [ImageAdjustmentPreset]
  ) throws {
    try encode(
      presets,
      to: baseDirectory.appending(path: "adjustment-presets.json")
    )
  }

  private func sessionURL(kind: String, assetID: AssetID) -> URL {
    baseDirectory
      .appending(path: kind, directoryHint: .isDirectory)
      .appending(path: "\(assetKey(assetID)).json")
  }

  private func assetKey(_ assetID: AssetID) -> String {
    Data(
      "\(assetID.volumeIdentifier)\u{0}\(assetID.fileIdentifier)".utf8
    )
    .base64EncodedString()
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "+", with: "-")
  }

  private func encode<Value: Encodable>(_ value: Value, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try encoder.encode(value).write(to: url, options: .atomic)
  }

  private func decodeIfPresent<Value: Decodable>(
    _ type: Value.Type,
    from url: URL
  ) throws -> Value? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    return try decoder.decode(type, from: Data(contentsOf: url))
  }

  private func removeIfPresent(_ url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }
}
