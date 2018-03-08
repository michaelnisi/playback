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
import FeedKit
import os.log

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
  public static func set(entry: Entry, player: AVPlayer? = nil) {
    os_log("setting now playing", log: log, type: .debug)
    var info: [String : Any] = [
      MPMediaItemPropertyAlbumTitle: entry.feedTitle!,
      MPMediaItemPropertyMediaType: 1,
      MPMediaItemPropertyTitle: entry.title
    ]
    
    let boundsSize = CGSize(width: 600, height: 600)
    let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { size in
      guard let img = ImageRepository.shared.image(for: entry, in: size) else {
        
        // TODO: Return correct image of correct size
        return #imageLiteral(resourceName: "img100")
      }
      return img
    }
    
    info[MPMediaItemPropertyArtwork] = artwork
    info[MPNowPlayingInfoPropertyExternalContentIdentifier] = entry.guid
    info[MPNowPlayingInfoPropertyMediaType] = 1
    
    if let enclosure = entry.enclosure,
      let url = URL(string: enclosure.url) {
      info[MPNowPlayingInfoPropertyAssetURL] = url
    }
    
    if let p = player {
      let rate = p.rate
      let time = p.currentTime().seconds
      let duration = p.currentItem!.duration.seconds

      info[MPNowPlayingInfoPropertyPlaybackRate] = rate
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
}
