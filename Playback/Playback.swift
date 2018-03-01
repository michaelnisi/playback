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

// MARK: API

public protocol Intermediating {
  func activate() throws
  func deactivate() throws
}

public protocol Playing {
  @discardableResult func play(_ entry: Entry?) -> Bool
  @discardableResult func pause() -> Bool
  
  var currentEntry: Entry? { get }

  func resume()
}

/// The main conglomerate API of this module.
public protocol Playback: Intermediating, Playing, NSObjectProtocol {
  var delegate: PlaybackDelegate? { get set }
}

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

// TODO: Require more detailed, see MPRemoteCommandHandlerStatus, return values

public protocol PlaybackDelegate {
  func playback(session: Playback, didChange state: PlaybackState)
  func playback(session: Playback, error: PlaybackError)
  func nextTrack() -> Bool
  func previousTrack() -> Bool
}


