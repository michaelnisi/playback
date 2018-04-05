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
  
  /// Conveniently initializes paused state including playback error, for all
  /// states transfer to `.paused(Entry, PlaybackError)` after an error event.
  ///
  /// - Parameters:
  ///   - entry: The entry being paused as a result of an error.
  ///   - error: The error that caused the problem.
  init(paused entry: Entry, error: Error) {
    let playbackError: PlaybackError = {
      switch error {
      case let avError as NSError:
        switch avError.code {
        case AVError.fileFormatNotRecognized.rawValue,
             AVError.failedToLoadMediaData.rawValue,
             AVError.undecodableMediaData.rawValue:
          return .media
        default:
          return .surprising(error)
        }
      }
    }()
    self = .paused(entry, playbackError)
  }
  
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
  case change(Entry?)
  case end
  case error(PlaybackError)
  case paused
  case resume
  case pause
  case toggle
  case playing
  case ready
  case video
}

extension PlaybackEvent: CustomStringConvertible {
  
  var description: String {
    switch self {
    case .change(let entry):
      return "PlaybackEvent: change: \(String(describing: entry))"
    case .resume:
      return "PlaybackEvent: resume"
    case .pause:
      return "PlaybackEvent: pause"
    case .end:
      return "PlaybackEvent: end"
    case .error(let error):
      return "PlaybackEvent: error: \(error)"
    case .paused:
      return "PlaybackEvent: paused"
    case .toggle:
      return "PlaybackEvent: toggle"
    case .playing:
      return "PlaybackEvent: playing"
    case .ready:
      return "PlaybackEvent: ready"
    case .video:
      return "PlaybackEvent: video"
    }
  }
  
}
