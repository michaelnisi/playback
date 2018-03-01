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

/// Playing back audio-visual media of enclosures found in FeedKit entries.
public protocol Playing {
  
  /// Starts playing `entry` and updates now playing info.
  @discardableResult func play(_ entry: Entry?) -> Bool
  
  /// Pauses the currently playing item.
  @discardableResult func pause() -> Bool
  
  /// The currently playing entry.
  var currentEntry: Entry? { get }

  /// Resumes playing the current item if we there is one.
  func resume()
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
