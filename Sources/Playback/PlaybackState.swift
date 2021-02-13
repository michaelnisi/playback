//
//  PlaybackState.swift
//  Playback
//
//  Created by Michael Nisi on 02.03.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import AVKit

// MARK: - PlaybackState

/// Enumerates playback states.
public enum PlaybackState<Item: Equatable>: Equatable {

  /// Decides if we should try to resume playback when leaving this state.
  public typealias Resuming = Bool
  
  /// The session is inactive, maybe due to an error.
  case inactive(PlaybackError?)

  /// The current item has been paused.
  case paused(Item, AssetState, PlaybackError?)
  
  /// Preparing a new item for playback.
  case preparing(Item, Resuming)
  
  /// Playing an audible item. Associated values are the Item and the momentary  state of the AV asset (at the time of change).
  case listening(Item, AssetState)
  
  /// Playing a visual item.
  case viewing(Item, AVPlayer)
  
  /// Conveniently initializes paused state including playback error, for all
  /// states transfer to `.paused(Item, PlaybackError)` after an error event.
  ///
  /// - Parameters:
  ///   - item: The item being paused as a result of an error.
  ///   - error: The error that caused the problem.
  init(paused item: Item, assetState: AssetState, error: Error) {
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
    
    self = .paused(item, assetState, playbackError)
  }
}

extension PlaybackState: CustomStringConvertible {
  
  public var description: String {
    switch self {
    case let .inactive(error):
      return "PlaybackState: inactive: \(String(describing: error))"
    case let .listening(item, assetState):
      return "PlaybackState: listening: \((item, assetState))"
    case let .paused(item, assetState, error):
        return "PlaybackState: paused: \((item, assetState, error))"
    case let .preparing(item, isResuming):
      return "PlaybackState: preparing: \(item), \(isResuming)"
    case let .viewing(item, player):
      return "PlaybackState: viewing: \(item), \(player)"
    }
  }
}

extension PlaybackState {
  
  var isOK: Bool {
    switch self {
    case .paused(_, _, let error):
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
  
  var item: Item? {
    switch self {
    case .preparing(let item, _),
         .listening(let item, _),
         .viewing(let item, _),
         .paused(let item, _, _):
      return item
    case .inactive:
      return nil
    }
  }
}

// MARK: - PlaybackEvent

/// Enumerates events of the playback FSM.
enum PlaybackEvent<Item: Equatable> {
  case change(Item?, Bool)
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
    case .change(let item, let resuming):
      return "PlaybackEvent: change: ( \(String(describing: item)),  \(resuming) )"
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
