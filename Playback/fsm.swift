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
  
  /// The session is inactive, maybe due to an error.
  case inactive(PlaybackError?)

  // We should separate player and item to support AirPlay for audio AND video.
  //
  // The key for accomplishing this might be to consider the player as ephemeral 
  // object, the item however is part of our actual state.
  //
  // TODO: Consider keeping AVPlayerItem in following states:

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
    case .inactive(let error):
      return "PlaybackState: inactive: \(String(describing: error))"
    case .listening(let entry):
      return "PlaybackState: listening: \(entry)"
    case .paused(let entry, let error):
        return "PlaybackState: paused: \(entry), \(String(describing: error))"
    case .preparing(let entry, let isResuming):
      return "PlaybackState: preparing: \(entry), \(isResuming)"
    case .viewing(let entry, let player):
      return "PlaybackState: viewing: \(entry), \(player)"
    }
  }
}

extension PlaybackState {
  
  var isOK: Bool {
    switch self {
    case .paused(_, let error):
      return error == nil
    case .preparing, .listening, .viewing:
      return true
    case .inactive:
      return false
    }
  }
  
  var shouldResume: Bool {
    switch self {
    case .paused, .inactive:
      return false
    case .listening, .viewing:
      return true
    case .preparing(_, let resuming):
      return resuming
    }
  }
  
  var entry: Entry? {
    switch self {
    case .preparing(let entry, _),
         .listening(let entry),
         .viewing(let entry, _),
         .paused(let entry, _):
      return entry
    case .inactive:
      return nil
    }
  }
}

// MARK: - PlaybackEvent

/// Enumerates events of the playback FSM.
enum PlaybackEvent {
  case change(Entry?, Bool)
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
    case .change(let entry, let resuming):
      return "PlaybackEvent: change: ( \(String(describing: entry)),  \(resuming) )"
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
