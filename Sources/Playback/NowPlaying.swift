//===----------------------------------------------------------------------===//
//
// This source file is part of the Playback open source project
//
// Copyright (c) 2021 Michael Nisi and collaborators
// Licensed under MIT License
//
// See https://github.com/michaelnisi/playback/blob/main/LICENSE for license information
//
//===----------------------------------------------------------------------===//

import Foundation
import MediaPlayer
import AVKit
import os.log

/// Proxies now playing info center.
public struct NowPlaying {

  /// Resets the current now playing info.
  public static func reset() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }
  
  /// Sets system now playing info.
  ///
  /// - Parameters:
  ///    - playbackItem: The playbackItem to display in playing info.
  public static func set(_ playbackItem: PlaybackItem) {
    var info: [String : Any] = [
      MPMediaItemPropertyAlbumTitle: playbackItem.subtitle,
      MPMediaItemPropertyMediaType: 1,
      MPMediaItemPropertyTitle: playbackItem.title
    ]
    
    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
      boundsSize: CGSize(width: 600, height: 600)) { size in
      return ImageRepository.shared.cachedImage(representing: playbackItem.imageURLs, at: size) ?? #imageLiteral(resourceName: "Oval")
    }
    
    info[MPNowPlayingInfoPropertyExternalContentIdentifier] = playbackItem.id
    info[MPNowPlayingInfoPropertyMediaType] = 1
    
    if let url = playbackItem.nowPlaying?.url {
      info[MPNowPlayingInfoPropertyAssetURL] = url
    }
    
    if let nowPlaying = playbackItem.nowPlaying {
      info[MPNowPlayingInfoPropertyPlaybackRate] = nowPlaying.rate
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = nowPlaying.time
      info[MPMediaItemPropertyPlaybackDuration] = nowPlaying.duration
    }
    
    os_log("setting now playing: %@", log: log, type: .info, info)

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
}
