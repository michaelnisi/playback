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
import FeedKit

/// Enumerates playback errors.
public enum PlaybackError: Error {
  case unknown
  case failed
  case log
}

/// A callback interface implemented by playback users to receive information
/// about the playback session state.
public protocol PlaybackDelegate {
  
  /// Returns a local or remote URL for `url`. One might return `nil` to signal
  /// that the URL is not reachable.
  func proxy(url: URL) -> URL?
  
  /// Called when this session’s playback `state` changed.
  func playback(session: Playback, didChange state: PlaybackState)
  
  /// Playback errors are forwarded to this callback.
  func playback(session: Playback, error: PlaybackError)
  
  /// Returns the next item.
  func nextItem() -> Entry?
  
  /// Returns the previous item.
  func previousItem() -> Entry?
  
  /// Dismisses the video player.
  func dismissVideo()
  
}

/// Playing back audio-visual media enclosed by `FeedKit.Entry`, forwarding
/// information to `MediaPlayer` default now playing info center.
/// Additionally, implementors should persist play times across devices.
public protocol Playing {
  
  /// The currently playing item. Changing this sets up a new player item and
  /// pauses it. Use `resume` to actually start playing.
  var currentEntry: Entry? { get set }
  
  /// Resumes playing the current item from its previous position.
  @discardableResult
  func resume() -> Bool
  
  /// Pauses playback of the current item.
  @discardableResult
  func pause() -> Bool
  
  /// Sets current to the next item from the delegate.
  @discardableResult
  func forward() -> Bool
  
  /// Sets current to previous item from the delegate.
  @discardableResult
  func backward() -> Bool
  
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


