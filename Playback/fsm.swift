//
//  fsm.swift
//  Playback
//
//  Created by Michael Nisi on 02.03.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import FeedKit
import AVKit

// MARK: - PlaybackState

/// Enumerates states of the Playback FSM.
public enum PlaybackState {
  
  /// The session is inactive.
  case inactive(PlaybackError?)
  
  /// The current item has been paused.
  case paused(Entry, PlaybackError?)
  
  /// Preparing a new item for playback.
  case preparing(Entry)
  
  /// Playing an audible item.
  case listening(Entry)
  
  /// Playing a visual item.
  case viewing(Entry, AVPlayer)
  
}

extension PlaybackState: Equatable {
  
  public static func ==(lhs: PlaybackState, rhs: PlaybackState) -> Bool {
    switch (lhs, rhs) {
    case (.inactive(let a), .inactive(let b)):
      return a == b
    case (.paused(let a, let aa), .paused(let b, let bb)):
      return a == b && aa == bb
    case (.listening(let a), .listening(let b)):
      return a == b
    case (.preparing(let a), .preparing(let b)):
      return a == b
    case (.viewing(let a, _), .viewing(let b, _)):
      return a == b
    case (.inactive, _),
         (.paused, _),
         (.listening, _),
         (.preparing, _),
         (.viewing, _):
      return false
    }
  }
  
}

extension PlaybackState: CustomStringConvertible {
  
  public var description: String {
    switch self {
    case .inactive(let error):
      return "PlaybackState: inactive: \(String(describing: error))"
    case .listening(let entry):
      return "PlaybackState: listening: \(String(describing: entry))"
    case .paused(let entry):
      return "PlaybackState: paused: \(String(describing: entry))"
    case .preparing(let entry):
      return "PlaybackState: preparing: \(String(describing: entry))"
    case .viewing(let entry, _):
      return "PlaybackState: viewing: \(String(describing: entry))"
    }
  }
  
}

// MARK: - PlaybackEvent

/// Enumerates events of the playback FSM.
enum PlaybackEvent {
  
  /// The change event occures after the current entry has changed to a
  /// different entry or to `nil`.
  case change(Entry?)
  
  case end
  case error(PlaybackError)
  case paused
  
  /// Plays the current entry. If the enclosed entry is not the current entry,
  /// this event get ignored.
  case play(Entry)
  
  case playing
  case ready
  case video
  
}

extension PlaybackEvent: CustomStringConvertible {
  
  var description: String {
    switch self {
    case .change(let entry):
      return "PlaybackEvent: change: \(String(describing: entry))"
    case .end:
      return "PlaybackEvent: end"
    case .error(let error):
      return "PlaybackEvent: error: \(error)"
    case .paused:
      return "PlaybackEvent: paused"
    case .play:
      return "PlaybackEvent: play"
    case .playing:
      return "PlaybackEvent: playing"
    case .ready:
      return "PlaybackEvent: ready"
    case .video:
      return "PlaybackEvent: video"
    }
  }
  
}
