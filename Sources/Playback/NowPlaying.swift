//
//  NowPlaying.swift
//  Playback
//
//  Created by Michael Nisi on 03.03.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

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
  ///    - entry: The entry to display in playing info.
  ///    - player: The current player to probe for information.
  public static func set(entry: PlaybackItem, player: AVPlayer? = nil) {
    var info: [String : Any] = [
      MPMediaItemPropertyAlbumTitle: entry.subtitle,
      MPMediaItemPropertyMediaType: 1,
      MPMediaItemPropertyTitle: entry.title
    ]
    
    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
      boundsSize: CGSize(width: 600, height: 600)) { size in
      return ImageRepository.shared.cachedImage(representing: entry.imageURLs, at: size) ?? #imageLiteral(resourceName: "Oval")
    }
    
    info[MPNowPlayingInfoPropertyExternalContentIdentifier] = entry.id
    info[MPNowPlayingInfoPropertyMediaType] = 1
    
    if let assetURLString = entry.nowPlaying?.url, let url = URL(string: assetURLString) {
      info[MPNowPlayingInfoPropertyAssetURL] = url
    }
    
    if let p = player {
      let rate = p.rate
      let duration = p.currentItem!.duration.seconds
      let time = min(p.currentTime().seconds, duration) 

      info[MPNowPlayingInfoPropertyPlaybackRate] = rate
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time 
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    
    os_log("setting now playing: %@", log: log, type: .info, info)

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
}
