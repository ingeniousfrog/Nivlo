import AVFoundation
import AVKit
import NivloDomain
import SwiftUI

struct AssetVideoPlayerView: View {
  let asset: ImageAsset

  @State private var player: AVPlayer?

  var body: some View {
    Group {
      if let player {
        VideoPlayer(player: player)
      } else {
        ZStack {
          Color.black
          ProgressView()
            .controlSize(.large)
        }
      }
    }
    .task(id: asset.url.standardizedFileURL.path) {
      player = AVPlayer(url: asset.url)
    }
    .onDisappear {
      player?.pause()
      player = nil
    }
  }
}
