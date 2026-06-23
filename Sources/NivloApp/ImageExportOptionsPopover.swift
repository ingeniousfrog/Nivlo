import NivloDomain
import SwiftUI

struct ExportOptionsPopover: View {
  let language: NivloLanguage
  @Binding var outputFormat: PicxOutputFormat
  @Binding var quality: Double
  @Binding var preset: PicxPreset
  @Binding var maxWidth: String
  @Binding var maxHeight: String
  @Binding var targetSizeKB: String
  let isExporting: Bool
  let onChooseLocation: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(language.tabExport)
        .font(.headline)

      Picker(language.exportFormat, selection: $outputFormat) {
        ForEach(PicxOutputFormat.allCases, id: \.self) { format in
          Text(format.rawValue.uppercased()).tag(format)
        }
      }
      Picker(language.exportPreset, selection: $preset) {
        ForEach(PicxPreset.allCases, id: \.self) { item in
          Text(item.rawValue).tag(item)
        }
      }
      Slider(value: $quality, in: 1...100, step: 1) {
        Text("\(language.exportQuality): \(Int(quality))")
      }
      TextField(language.maxWidth, text: $maxWidth)
      TextField(language.maxHeight, text: $maxHeight)
      TextField(language.targetSizeKB, text: $targetSizeKB)

      Button {
        onChooseLocation()
      } label: {
        Label(language.chooseExportLocation, systemImage: "folder")
      }
      .buttonStyle(.borderedProminent)
      .disabled(isExporting)
    }
  }
}
