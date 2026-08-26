import AVFoundation
import Foundation

guard CommandLine.arguments.count == 2 else {
    exit(64)
}

let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let duration = try await asset.load(.duration)
let tracks = try await asset.loadTracks(withMediaType: .video)
guard let track = tracks.first else {
    exit(1)
}

let naturalSize = try await track.load(.naturalSize)
let transform = try await track.load(.preferredTransform)
let presentedSize = naturalSize.applying(transform)
let seconds = CMTimeGetSeconds(duration)

guard seconds.isFinite, seconds > 0,
      abs(presentedSize.width) >= 1,
      abs(presentedSize.height) >= 1 else {
    exit(1)
}

let imageGenerator = AVAssetImageGenerator(asset: asset)
imageGenerator.appliesPreferredTrackTransform = true
let (decodedFrame, _) = try await imageGenerator.image(at: .zero)
guard decodedFrame.width >= 1, decodedFrame.height >= 1 else {
    exit(1)
}

print(
    String(
        format: "%.3f\t%d\t%d",
        seconds,
        Int(abs(presentedSize.width)),
        Int(abs(presentedSize.height))
    )
)
