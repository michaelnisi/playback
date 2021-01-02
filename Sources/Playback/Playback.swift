//
//  Playback.swift
//  Playback
//
//  Created by Michael on 6/14/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import AVFoundation
import AVKit
import Foundation
import os.log

/// State of a media asset.
public struct AssetState {
  
  public enum Medium: UInt {
    case none, audio, video
    
    var isVideo: Bool {
      self == .video
    }
  }

  public let url: URL
  public let rate: Float
  public let duration: CMTime
  public let time: CMTime
  
  public init(
    url: URL,
    rate: Float,
    duration: CMTime,
    time: CMTime
  ) {
    self.url = url
    self.rate = rate
    self.duration = duration
    self.time = time
  }
  
  public var isPlaying: Bool {
    rate != .zero
  }
}

/// `PlaybackItem` requests playback and represents a currently playing or paused item.
public struct PlaybackItem: Identifiable, Equatable {
    
  public typealias ID = String
  
  public let id: ID
  public let url: String
  public let title: String
  public let subtitle: String
  public let imageURLs: ImageURLs
  public let proclaimedMediaType: AssetState.Medium
  
  public let nowPlaying: AssetState?
  
  public init(
    id: ID,
    url: String,
    title: String,
    subtitle: String,
    imageURLs: ImageURLs,
    proclaimedMediaType: AssetState.Medium
  ) {
    self.init(
      id: id,
      url: url,
      title: title,
      subtitle: subtitle,
      imageURLs: imageURLs,
      proclaimedMediaType: proclaimedMediaType,
      nowPlaying: nil
    )
  }
  
  internal init(
    id: ID,
    url: String,
    title: String,
    subtitle: String,
    imageURLs: ImageURLs,
    proclaimedMediaType: AssetState.Medium,
    nowPlaying: AssetState?
  ) {
    self.id = id
    self.url = url
    self.title = title
    self.subtitle = subtitle
    self.imageURLs = imageURLs
    self.proclaimedMediaType = proclaimedMediaType
    self.nowPlaying = nowPlaying
  }
  
  public static func == (lhs: PlaybackItem, rhs: PlaybackItem) -> Bool {
    lhs.id == rhs.id
  }
}

/// Enumerates playback errors.
public enum PlaybackError: Error {
  case unknown
  case failed
  case log
  case media
  case session
  case surprising(Error)
  case unreachable
}

extension PlaybackError: Equatable {
  
  public static func == (lhs: PlaybackError, rhs: PlaybackError) -> Bool {
    switch (lhs, rhs) {
    case (.unknown, .unknown),
         (.failed, .failed),
         (.log, .log),
         (.media, .media),
         (.session, .session),
         (.surprising, .surprising),
         (.unreachable, .unreachable):
      return true
    case (.unknown, _),
         (.failed, _),
         (.log, _),
         (.media, _),
         (.session, _),
         (.surprising, _),
         (.unreachable, _):
      return false
    }
  }
}

/// Stores playback timestamps.
public protocol Times {  
  
  /// Return the matching timestamp for `uid`.
  func time(uid: String) -> CMTime
  
  /// Sets the `time` for `uid`. 
  ///
  /// Use `CMTime.indefinite` to tag the matching item as finished, meaning it
  /// has been played all the way to the end. An invalid `time` removes the 
  /// matching timestamp from the store.
  func set(_ time: CMTime, for uid: String)
  
  /// Removes the matching timestamp.
  func removeTime(for uid: String)
  
  /// Returns `true` if the matching item  has not been played.
  func isUnplayed(uid: String) -> Bool
}

/// Playable with this API.
public protocol Playable: Equatable {
  func makePlaybackItem() -> PlaybackItem
}
