import AppKit
import CoreImage
import ImageIO
import NivloDomain
import SwiftUI
import UniformTypeIdentifiers

struct AssetEditorView: View {
  let asset: ImageAsset
  let language: NivloLanguage

  @Environment(\.dismiss) private var dismiss
  @State private var quarterTurns = 0
  @State private var isFlippedHorizontally = false
  @State private var exportMessage: String?
  @State private var isExporting = false

  private var canEdit: Bool {
    UTType(asset.contentType)?.conforms(to: .image) == true
  }

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      ZStack {
        Color(nsColor: .windowBackgroundColor)
        if canEdit {
          AssetImageView(
            asset: asset,
            enrichment: nil,
            maxPixelSize: 1_600,
            contentMode: .fit
          )
          .rotationEffect(.degrees(Double(quarterTurns * 90)))
          .scaleEffect(x: isFlippedHorizontally ? -1 : 1, y: 1)
          .padding(32)
          .animation(.snappy, value: quarterTurns)
          .animation(.snappy, value: isFlippedHorizontally)
        } else {
          ContentUnavailableView(
            "Preview unavailable",
            systemImage: "photo.badge.exclamationmark"
          )
        }
      }
      if let exportMessage {
        Text(exportMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.vertical, 8)
      }
    }
    .frame(minWidth: 900, minHeight: 680)
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(language.editorTitle)
          .font(.headline)
        Text(asset.filename)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        quarterTurns = normalizedQuarterTurns(quarterTurns - 1)
      } label: {
        Label(language.rotateLeft, systemImage: "rotate.left")
      }
      Button {
        quarterTurns = normalizedQuarterTurns(quarterTurns + 1)
      } label: {
        Label(language.rotateRight, systemImage: "rotate.right")
      }
      Button {
        isFlippedHorizontally.toggle()
      } label: {
        Label(
          language.flipHorizontal,
          systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
      }
      Button(language.reset) {
        quarterTurns = 0
        isFlippedHorizontally = false
      }
      .disabled(quarterTurns == 0 && !isFlippedHorizontally)
      Button {
        exportEditedCopy()
      } label: {
        Label(language.saveEditedCopy, systemImage: "square.and.arrow.up")
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canEdit || isExporting)
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
      }
      .keyboardShortcut(.cancelAction)
      .help(language.close)
    }
    .buttonStyle(.bordered)
    .padding(16)
  }

  private func exportEditedCopy() {
    let panel = NSSavePanel()
    panel.title = language.saveEditedCopy
    panel.nameFieldStringValue =
      "\(asset.url.deletingPathExtension().lastPathComponent)-edited.png"
    panel.allowedContentTypes = [.png]
    guard panel.runModal() == .OK, let outputURL = panel.url else {
      return
    }
    guard outputURL.standardizedFileURL != asset.url.standardizedFileURL else {
      exportMessage = language.originalFileProtected
      return
    }

    isExporting = true
    exportMessage = nil
    let sourceURL = asset.url
    let turns = quarterTurns
    let flipped = isFlippedHorizontally
    Task {
      do {
        try await Task.detached(priority: .userInitiated) {
          try EditedImageExporter.exportPNG(
            sourceURL: sourceURL,
            outputURL: outputURL,
            quarterTurns: turns,
            flippedHorizontally: flipped
          )
        }.value
        exportMessage = language.editorExported
      } catch {
        exportMessage = "\(language.editorExportFailed): \(error.localizedDescription)"
      }
      isExporting = false
    }
  }

  private func normalizedQuarterTurns(_ value: Int) -> Int {
    (value % 4 + 4) % 4
  }
}

private enum EditedImageExporter {
  static func exportPNG(
    sourceURL: URL,
    outputURL: URL,
    quarterTurns: Int,
    flippedHorizontally: Bool
  ) throws {
    guard var image = CIImage(contentsOf: sourceURL) else {
      throw AssetEditorError.unreadableImage
    }

    let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
    var transform = CGAffineTransform(translationX: center.x, y: center.y)
    if flippedHorizontally {
      transform = transform.scaledBy(x: -1, y: 1)
    }
    transform = transform.rotated(by: CGFloat(quarterTurns) * .pi / 2)
    transform = transform.translatedBy(x: -center.x, y: -center.y)
    image = image.transformed(by: transform)

    let extent = image.extent.integral
    image = image.transformed(
      by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
    )
    let outputExtent = image.extent.integral
    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let cgImage = context.createCGImage(image, from: outputExtent) else {
      throw AssetEditorError.renderFailed
    }
    guard
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw AssetEditorError.destinationUnavailable
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw AssetEditorError.writeFailed
    }
  }
}

private enum AssetEditorError: Error, LocalizedError {
  case unreadableImage
  case renderFailed
  case destinationUnavailable
  case writeFailed

  var errorDescription: String? {
    switch self {
    case .unreadableImage:
      "The image could not be read."
    case .renderFailed:
      "The edited image could not be rendered."
    case .destinationUnavailable:
      "The export destination could not be created."
    case .writeFailed:
      "The edited image could not be written."
    }
  }
}
