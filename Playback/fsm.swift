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

/// Returns the new playback state after processing event `e` appropriately
/// to the current state. The event handler of the state machine, where the
/// shit hits the fan. **Don’t lock** yourself by trying to synchronously
/// trigger the next event. Event handling is serial.
///
/// The playback state machine has five states: inactive, paused, preparing,
/// listening, and viewing; where listening and viewing are incorporated.
/// Unlisted events for a specific state aren’t handled and result in a
/// **fatal error**.
///
/// # inactive
///
/// - `.inactive(Error?, Resuming)`
///
/// A Playback session starts **inactive** with an unconfigured, inactive
/// `AVAudioSession`, waiting for `.change(Entry?)` to start, trapping all
/// all other events, except `.resume`, which turns on `Resuming`, so the
/// next `.change(Entry?)` will start playing.
///
/// Being **inactive** may be unintended, so this state optionally stores an
/// error, the cause of inactivity.
///
/// ## change
///
/// The `.change(Entry?)` event with an entry activates the session and
/// transits to the **paused** state, while `.change` without entry
/// deactivates the session remaining in **inactive** state.
///
/// # paused
///
/// - `.paused(Entry, Error?)`
///
/// In **paused** we have an item and finished a setup cycle, leaving us
/// either ready to play or with an error.
///
/// ## change
///
/// In **paused** state the current entry can be changed or set to `nil`
/// deactivating the session—leaving us in **paused** or transfering to
/// **inactive**.
///
/// ## toggle/resume
///
/// Plays the current item, eventually, after transfering to **preparing**,
/// which will trigger `ready` or `error` events.
///
/// ## playing
///
/// Tansfers to `.listening(Entry)` or `viewing(Entry, AVPlayer`). If our
/// internal player is not in the required state, this will trap.
///
/// ## ready
///
/// After `ready` in **paused** state, we seek the player to the previous
/// play time of this item and pause, leaving us in **paused**, but seeked to
/// the correct position, ready to play.
///
/// ### Ignored Events
///
/// While in **paused**, `.paused`, `.video`, and `.pause` events are ignored.
///
/// ## error
///
/// If an `error` occures during **paused**, it will be added to the
/// **paused** state, in which we remain.
///
/// # preparing
///
/// ...
///
/// # listening/viewing
///
/// ...
///
///
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
