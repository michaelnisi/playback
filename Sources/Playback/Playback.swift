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

  public let url: String
  public let medium: Medium
  public let rate: Float
  public let duration: Double
  public let time: Double
  
  public init(
    url: String,
    medium: Medium,
    rate: Float,
    duration: Double,
    time: Double
  ) {
    self.url = url
    self.medium = medium
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
  
  init(
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

/// A callback interface implemented by playback users to receive information
/// about the playback session state.
public protocol PlaybackDelegate: class {

  /// Returns a local or remote URL for `url`. One might return `nil` to signal
  /// that the URL is not reachable, implying that the returned URL must be
  /// reachable on the current network, otherwise return `nil`.
  func proxy(url: URL) -> URL?
  
  /// Called when this session’s playback `state` changed.
  func playback(session: Playback, didChange state: PlaybackState)
  
  /// Returns the next item.
  func nextItem() -> Playable?
  
  /// Returns the previous item.
  func previousItem() -> Playable?
}

public protocol Playable {
  func makePlaybackItem() -> PlaybackItem
}

/// Playing back audio-visual media enclosed by `PlaybackItem`, forwarding
/// information to `MediaPlayer` default now playing info center.
/// Additionally, implementors should persist play times across devices.
public protocol Playing {
  
  /// The currently playing item.
  var currentEntry: PlaybackItem? { get }
  
  /// Resumes playing `entry` or the current item from its previous position or from `time`.
  @discardableResult
  func resume(entry: Playable?, from time: Double?) -> Bool
  
  /// Pauses playback of `entry` or the current item at `time`.
  @discardableResult
  func pause(entry: Playable?, at time: Double?) -> Bool
  
  /// Toggles between playing and pausing the current item.
  @discardableResult
  func toggle() -> Bool
  
  /// Sets current to the next item from the delegate.
  @discardableResult
  func forward() -> Bool
  
  /// Sets current to previous item from the delegate.
  @discardableResult
  func backward() -> Bool
  
  /// Returns `true` if the item matching `uid` has not been played before.
  func isUnplayed(uid: String) -> Bool
  
  /// Returns `true` if an item matching `guid` is currently playing.
  func isPlaying(guid: PlaybackItem.ID) -> Bool
}

/// The main conglomerate API of this module.
public protocol Playback: Playing, NSObjectProtocol {
  
  /// The playback delegate receives feedback about the playback state and is
  /// responsible to forward this information to the UI.
  var delegate: PlaybackDelegate? { get set }
  
  /// Reclaims remote command center. For example, after dismissing a presented
  /// `AVPlayerViewController`, which sets its own remote commands, overwriting
  /// our remote commands.
  func reclaim()
}
