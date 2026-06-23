import AVFoundation
import AppKit
import CoreVideo
import NivloDomain
import SwiftUI

struct EditorSmokeView: View {
  @State private var fixtures: EditorSmokeFixtures?
  @State private var errorMessage: String?
  @State private var selectedEditor =
    CommandLine.arguments.contains("--ui-smoke-video") ? 1 : 0

  var body: some View {
    Group {
      if let fixtures {
        VStack(spacing: 0) {
          Picker("Editor", selection: $selectedEditor) {
            Text("Image Editor").tag(0)
            Text("Video Editor").tag(1)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 210)
          .padding(12)
          Divider()
          if selectedEditor == 0 {
            AssetEditorView(
              asset: fixtures.image,
              language: .english,
              toolsReady: false,
              onExport: { _, _ in }
            )
          } else {
            VideoEditorView(
              asset: fixtures.video,
              language: .english,
              toolsReady: false,
              onExport: { _, _ in }
            )
          }
        }
      } else if let errorMessage {
        ContentUnavailableView(
          "Smoke fixture failed",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage)
        )
      } else {
        ProgressView("Preparing real image and video fixtures…")
      }
    }
    .navigationTitle("Nivlo Editor Smoke")
    .frame(minWidth: 1_280, minHeight: 860)
    .task {
      do {
        fixtures = try await Task.detached(priority: .userInitiated) {
          try EditorSmokeFixtures.make()
        }.value
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}

private struct EditorSmokeFixtures: Sendable {
  let image: ImageAsset
  let video: ImageAsset

  static func make() throws -> EditorSmokeFixtures {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "NivloEditorSmoke", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let imageURL = directory.appending(path: "smoke-image.png")
    let videoURL = directory.appending(path: "smoke-video.mov")
    try writeImage(to: imageURL)
    try writeVideo(to: videoURL)
    return EditorSmokeFixtures(
      image: ImageAsset(
        id: AssetID(volumeIdentifier: "smoke", fileIdentifier: "image"),
        url: imageURL,
        filename: imageURL.lastPathComponent,
        contentType: "public.png",
        fileSize: fileSize(imageURL),
        createdAt: nil,
        modifiedAt: Date(),
        pixelWidth: 1_200,
        pixelHeight: 800
      ),
      video: ImageAsset(
        id: AssetID(volumeIdentifier: "smoke", fileIdentifier: "video"),
        url: videoURL,
        filename: videoURL.lastPathComponent,
        contentType: "com.apple.quicktime-movie",
        fileSize: fileSize(videoURL),
        createdAt: nil,
        modifiedAt: Date(),
        pixelWidth: 640,
        pixelHeight: 360
      )
    )
  }

  private static func writeImage(to url: URL) throws {
    let image = NSImage(size: NSSize(width: 1_200, height: 800))
    image.lockFocus()
    NSGradient(
      colors: [.systemBlue, .systemPurple, .systemOrange]
    )?.draw(in: NSRect(x: 0, y: 0, width: 1_200, height: 800), angle: 15)
    "Nivlo Smoke"
      .draw(
        at: NSPoint(x: 60, y: 60),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 72, weight: .bold),
          .foregroundColor: NSColor.white,
        ]
      )
    image.unlockFocus()
    guard
      let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let data = representation.representation(
        using: .png,
        properties: [:]
      )
    else {
      throw EditorSmokeError.fixtureCreationFailed
    }
    try data.write(to: url, options: .atomic)
  }

  private static func writeVideo(to url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 640,
        AVVideoHeightKey: 360,
      ]
    )
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String:
          kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 640,
        kCVPixelBufferHeightKey as String: 360,
      ]
    )
    guard writer.canAdd(input) else {
      throw EditorSmokeError.fixtureCreationFailed
    }
    writer.add(input)
    guard writer.startWriting() else {
      throw writer.error ?? EditorSmokeError.fixtureCreationFailed
    }
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<48 {
      while !input.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.001)
      }
      guard let pool = adaptor.pixelBufferPool else {
        throw EditorSmokeError.fixtureCreationFailed
      }
      var pixelBuffer: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
      guard let pixelBuffer else {
        throw EditorSmokeError.fixtureCreationFailed
      }
      CVPixelBufferLockBaseAddress(pixelBuffer, [])
      let bytes = CVPixelBufferGetBaseAddress(pixelBuffer)!
        .assumingMemoryBound(to: UInt8.self)
      let byteCount = CVPixelBufferGetDataSize(pixelBuffer)
      for offset in stride(from: 0, to: byteCount, by: 4) {
        bytes[offset] = UInt8((frame * 5 + 40) % 255)
        bytes[offset + 1] = UInt8((frame * 3 + 80) % 255)
        bytes[offset + 2] = UInt8((frame * 7 + 120) % 255)
        bytes[offset + 3] = 255
      }
      CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
      adaptor.append(
        pixelBuffer,
        withPresentationTime: CMTime(value: Int64(frame), timescale: 24)
      )
    }
    input.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
      semaphore.signal()
    }
    semaphore.wait()
    guard writer.status == .completed else {
      throw writer.error ?? EditorSmokeError.fixtureCreationFailed
    }
  }

  private static func fileSize(_ url: URL) -> Int64 {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
      .int64Value ?? 0
  }
}

private enum EditorSmokeError: Error, LocalizedError {
  case fixtureCreationFailed

  var errorDescription: String? {
    "Nivlo could not create the editor smoke fixtures."
  }
}
