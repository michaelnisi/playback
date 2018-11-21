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

/// Enumerates playback states.
public enum PlaybackState: Equatable {

  /// Decides if we should try to resume playback when leaving this state.
  public typealias Resuming = Bool
  
  /// The session is inactive.
  case inactive(PlaybackError?, Resuming)

  // TODO: Consider putting AVPlayerItem in following (playing) states
  //
  // We have to separate player and item to support AirPlay for audio AND video.
  // I think, the key to accomplish this might be understanding the player as
  // ephemeral object, part of our actual state, though, is the item.

  /// The current item has been paused.
  case paused(Entry, PlaybackError?)
  
  /// Preparing a new item for playback.
  case preparing(Entry, Resuming)
  
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

extension PlaybackState: CustomStringConvertible {
  
  public var description: String {
    switch self {
    case .inactive(let s):
      return "PlaybackState: inactive: \(s)"
    case .listening(let s):
      return "PlaybackState: listening: \(s)"
    case .paused(let s):
      return "PlaybackState: paused: \(s)"
    case .preparing(let s):
      return "PlaybackState: preparing: \(s)"
    case .viewing(let s):
      return "PlaybackState: viewing: \(s)"
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
  case scrub(TimeInterval)
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
    case .scrub(let position):
      return "PlaybackEvent: scrub: \(position)"
    }
  }
  
}
