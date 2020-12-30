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
import FeedKit // 🗑

public enum MediaType: UInt {
  case none, audio, video
}

public struct NowPlayingInfo {
  
  public let assetURL: String
  public let mediaType: MediaType
  public let rate: Float
  public let duration: Double
  public let time: Double
  
  public init(
    assetURL: String,
    mediaType: MediaType,
    rate: Float,
    duration: Double,
    time: Double
  ) {
    self.assetURL = assetURL
    self.mediaType = mediaType
    self.rate = rate
    self.duration = duration
    self.time = time
  }
  
  public var isPlaying: Bool {
    rate != .zero
  }
}

public struct ImageURLs {
  
  public let guid: PlaybackItem.Identifier
  public let small: String
  public let medium: String
  public let large: String
  
  public init(
    guid: PlaybackItem.Identifier,
    small: String,
    medium: String,
    large: String
  ) {
    self.guid = guid
    self.small = small
    self.medium = medium
    self.large = large
  }
}

public struct PlaybackItem: Identifiable {

  public typealias Identifier = String
  
  public init(
    id: Identifier,
    url: String,
    title: String,
    subtitle: String,
    imageURLs: ImageURLs,
    nowPlaying: NowPlayingInfo? = nil
  ) {
    self.id = id
    self.url = url
    self.title = title
    self.subtitle = subtitle
    self.imageURLs = imageURLs
    self.nowPlaying = nowPlaying
  }
  
  public let id: Identifier
  public let url: String
  public let title: String
  public let subtitle: String
  public let imageURLs: ImageURLs
  public let nowPlaying: NowPlayingInfo?
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
  func nextItem() -> Entry?
  
  /// Returns the previous item.
  func previousItem() -> Entry?
}

/// Playing back audio-visual media enclosed by `FeedKit.Entry`, forwarding
/// information to `MediaPlayer` default now playing info center.
/// Additionally, implementors should persist play times across devices.
public protocol Playing {
  
  /// The currently playing item.
  var currentEntry: Entry? { get }
  
  /// Resumes playing `entry` or the current item from its previous position.
  @discardableResult
  func resume(entry: Entry?) -> Bool
  
  /// Pauses playback of `entry` or the current item.
  @discardableResult
  func pause(entry: Entry?) -> Bool
  
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
  func isPlaying(guid: EntryGUID) -> Bool
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


