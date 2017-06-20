//
//  now.swift
//  Podest
//
//  Created by Michael on 5/26/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import MediaPlayer
import AVKit
import FeedKit

public struct NowPlaying {

  /// Resets the current now playing info.
  public static func reset() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  /// Sets system now-playing information.
  ///
  /// - Parameters:
  ///    - entry: The entry to display in playing info.
  ///    - player: The current player to probe for information.
  public static func set(entry: Entry, player: AVPlayer) {
    var info: [String : Any] = [
      MPMediaItemPropertyAlbumTitle: entry.feedTitle!,
      MPMediaItemPropertyMediaType: 1,
      MPMediaItemPropertyTitle: entry.title
    ]

    if #available(iOS 10.0, *) {
      let boundsSize = CGSize(width: 600, height: 600)
      let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { size in
        guard let img = ImageRepository.shared.image(for: entry, in: size) else {
          
          // TODO: Return correct image of correct size
          
          // Perplexing that, through the workspace apparently, app assets are
          // accessible from here.
          
          return #imageLiteral(resourceName: "img100")
        }
        return img
      }

      info[MPMediaItemPropertyArtwork] = artwork
      info[MPNowPlayingInfoPropertyExternalContentIdentifier] = entry.guid
      info[MPNowPlayingInfoPropertyMediaType] = 1
    } else {
      // TODO: Fallback on earlier versions
    }

    if #available(iOS 10.3, *) {
      info[MPNowPlayingInfoPropertyAssetURL] = entry.enclosure!.url
    }
    
    let rate = player.rate
    let time = player.currentTime().seconds
    let duration = player.currentItem!.duration.seconds
    
    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
    info[MPNowPlayingInfoPropertyPlaybackRate] = rate
    
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
}
