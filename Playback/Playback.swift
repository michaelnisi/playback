//
//  Playback.swift
//  Playback
//
//  Created by Michael on 6/14/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import AVFoundation
import AVKit
import FeedKit
import Foundation
import os.log

// MARK: - Intermediating

/// Intermediates between this module and the system, including the remote
/// command center.
public protocol Intermediating {
  
  /// Activates the shared audio session.
  func activate() throws
  
  /// Deactivates the shared audio session.
  func deactivate() throws
}

// MARK: - Playing

public enum ResumePosition {
  case previous, beginning
}

/// Playing back audio-visual media of enclosures found in FeedKit entries.
public protocol Playing {
  
  /// Resumes playing of given `entry`. Without an entry, it assumes you want to
  /// resume playing the current episode, meaning the enclosure of the current
  /// entry. In this case, if no current entry exists, it is a NOP and returns
  /// `false`. The episode will be resumed from its previous play position if
  /// possible.
  ///
  /// - Parameter entry: The `entry` to play or `nil`.
  ///
  /// - Returns: `true` if it worked.
  @discardableResult func resume(
    entry: Entry?, from position: ResumePosition) -> Bool
  
  /// Resumes `entry` from previous position.
  @discardableResult func resume(entry: Entry) -> Bool
  
  /// Resumes current item from previous playing position.
  @discardableResult func resume() -> Bool
  
  /// Pauses the currently playing item.
  @discardableResult func pause() -> Bool
  
  /// The currently playing entry.
  var currentEntry: Entry? { get }
}

// MARK: - Playback

/// The main conglomerate API of this module.
public protocol Playback: Intermediating, Playing, NSObjectProtocol {
  var delegate: PlaybackDelegate? { get set }
}

// MARK: - PlaybackError

public enum PlaybackError: Error {
  case unknown, failed, log
}

extension PlaybackError: CustomStringConvertible {
  public var description: String {
    get {
      switch self {
      case .unknown: return "PlaybackError: unknown"
      case .failed: return "PlaybackError: failed"
      case .log: return "PlaybackError: log"
      }
    }
  }
}

// MARK: - PlaybackState

/// Enumerates states of the internal Playback FSM. It’s directly exposed to
/// the delegate, which I don't particularly like.
public enum PlaybackState {
  case paused
  case preparing(Entry)
  case listening(Entry)
  case viewing(Entry, AVPlayer)
}

extension PlaybackState: Equatable {
  public static func ==(lhs: PlaybackState, rhs: PlaybackState) -> Bool {
    switch (lhs, rhs) {
    case (.paused, .paused):
      return true
    case (.listening(let a), .listening(let b)):
      return a == b
    case (.preparing(let a), .preparing(let b)):
      return a == b
    case (.viewing(let a, _), .viewing(let b, _)):
      return a == b
    case (.paused, _),
         (.listening, _),
         (.preparing, _),
         (.viewing, _):
      return false
    }
  }
}

// MARK: - PlaybackDelegate

/// A callback interface implemented by playback users to receive information
/// about the playback session state.
public protocol PlaybackDelegate {
  
  /// Called when this session’s playback `state` changed.
  func playback(session: Playback, didChange state: PlaybackState)
  
  /// Playback errors are forwarded to this callback.
  func playback(session: Playback, error: PlaybackError)
  
  /// Asks the delegate to play the next track.
  func nextTrack() -> Bool
  
  /// Asks the delegate to initiate playback of the previous item.
  func previousTrack() -> Bool
  
}
