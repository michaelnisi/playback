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
}

public protocol Playback: Intermediating, Playing, NSObjectProtocol {
  var delegate: PlaybackDelegate? { get set }
}

public enum PlaybackError: Error {
  case unknown, failed, log
}

public protocol PlayerHost {
  var player: AVPlayer? { get set }
}

public enum PlaybackState {
  case paused
  case preparing(Entry)
  case playing(Entry)
  case viewing(AVPlayer)
}

public protocol PlaybackDelegate {
  func playback(session: Playback, didChange state: PlaybackState)
  func playback(session: Playback, error: PlaybackError)
}

// MARK: - Internal

private enum PlaybackEvent {
  case end
  case error(PlaybackError)
  case pause
  case play(Entry)
  case ready
  case video
}

/// Convenience access to probe the player‘s state, summarizing properties.
struct PlayerState {
  
  let host: PlayerHost
  
  init(host: PlayerHost) {
    self.host = host
  }
  
  var isPlaying: Bool {
    get {
      guard
        let player = host.player,
        let item = player.currentItem,
        item.status == .readyToPlay,
        player.error == nil,
        player.rate != 0 else {
        return false
      }
      return true
    }
  }
  
  var isPaused: Bool { get { return !hasFailed && !isPlaying }}
  
  var isReadyToPlay: Bool {
    get {
      guard let item = host.player?.currentItem else {
        return false
      }
      return item.status == .readyToPlay
    }
  }
  
  var hasFailed: Bool {
    get {
      guard let item = host.player?.currentItem else {
        return false
      }
      return item.status == .failed
    }
  }
  
  var isUnknown: Bool {
    get {
      guard let item = host.player?.currentItem else {
        return false
      }
      return item.status == .unknown
    }
  }
  
}

// MARK: - Logging

@available(iOS 10.0, *)
fileprivate let log = OSLog(subsystem: "ink.codes.playback", category: "play")

// MARK: - PlaybackSession

public class PlaybackSession: NSObject, PlayerHost, Playback {
  
  public static var shared = PlaybackSession()
  
  public var delegate: PlaybackDelegate?
  
  fileprivate var entry: Entry? {
    didSet {
      guard
        oldValue != entry,
        let player = self.player,
        let tid = currentURL?.absoluteString else {
        return
      }
      TimeRepository.shared.set(player.currentTime(), for: tid)
    }
  }
  
  // This time property somehow bothers me. Why rely on state for this?
  fileprivate var time: CMTime?
  
  public var player: AVPlayer?
  
  var playerState: PlayerState!
  
  private var currentURL: URL? {
    get {
      guard let asset = player?.currentItem?.asset as? AVURLAsset else {
        return nil
      }
      return asset.url
    }
  }
  
  private func seekableTime(
    _ time: CMTime,
    within seekableTimeRanges: [NSValue]
    ) -> CMTime? {
    guard time.isValid else {
      return nil
    }
    
    for v in seekableTimeRanges {
      guard let tr = v as? CMTimeRange else {
        continue
      }
      if tr.containsTime(time) {
        return time
      }
    }
    
    return nil
  }
  
  private func startTime() -> CMTime? {
    guard
      let seekableTimeRanges = player?.currentItem?.seekableTimeRanges,
      let t = self.time else {
        return nil
    }
    return seekableTime(t, within: seekableTimeRanges)
  }
  
  // TODO: Pass time to seekAndPlay instead of relying on state
  
  private func seekAndPlay() {
    defer {
      self.time = nil
    }
    
    guard let player = self.player, let entry = self.entry else {
      return
    }
    
    guard let time = startTime() else {
      player.play()
      NowPlaying.set(entry: entry, player: player)
      return
    }
    
    player.currentItem?.cancelPendingSeeks()
    
    player.seek(to: time) { [weak self] ok in
      assert(ok, "seek failed")
      
      DispatchQueue.main.async { [weak self] in
        guard let entry = self?.entry, let player = self?.player else {
          return
        }
        player.play()
        NowPlaying.set(entry: entry, player: player)
      }
    }
  }
  
  private var playerItemContext = 0
  
  private func onTracksChange(_ change: [NSKeyValueChangeKey : Any]?) {
    guard let tracks = change?[.newKey] as? [AVPlayerItemTrack] else {
      fatalError("no tracks to play")
    }
    
    let containsVideo = tracks.contains {
      $0.assetTrack.mediaType == AVMediaTypeVideo
    }
    
    let type = entry?.enclosure?.type
    
    guard containsVideo, type!.isVideo else {
      return
    }
    
    event(.video)
  }
  
  private func onStatusChange(_ change: [NSKeyValueChangeKey : Any]?) {
    let status: AVPlayerItemStatus
    
    if let statusNumber = change?[.newKey] as? NSNumber {
      status = AVPlayerItemStatus(rawValue: statusNumber.intValue)!
    } else {
      status = .unknown
    }
    
    switch status {
    case .readyToPlay:
      event(.ready)
    case .failed:
      let error = PlaybackError.failed
      event(.error(error))
      break
    case .unknown:
      let error = PlaybackError.unknown
      event(.error(error))
      break
    }
  }
  
  // Although the UIKit documentation states that duration would be available
  // when status is readyToPlay, the duration property needs to be monitored
  // separately to aquire a valid value.
  //
  // Another concern, for some reason, it is called multiple times, hence the
  // guard.
  
  private func onDurationChange(_ change: [NSKeyValueChangeKey : Any]?) {
    guard change?[.newKey] as? CMTime != change?[.oldKey] as? CMTime else {
      if #available(iOS 10.0, *) {
        os_log(
          "observed redundant duration change",
          log: log,
          type: .error
        )
      }
      return
    }
    NowPlaying.set(entry: entry!, player: player!)
  }
  
  override public func observeValue(forKeyPath keyPath: String?,
                             of object: Any?,
                             change: [NSKeyValueChangeKey : Any]?,
                             context: UnsafeMutableRawPointer?) {
    
    guard context == &playerItemContext else {
      super.observeValue(forKeyPath: keyPath,
                         of: object,
                         change: change,
                         context: context)
      return
    }
    
    if keyPath == #keyPath(AVPlayerItem.tracks) {
      onTracksChange(change)
    } else if keyPath == #keyPath(AVPlayerItem.status)  {
      onStatusChange(change)
    } else if keyPath == #keyPath(AVPlayerItem.duration) {
      onDurationChange(change)
    }
  }
  
  func onItemDidPlayToEndTime() {
    event(.end)
  }
  
  func onItemNewErrorLogEntry() {
    event(.error(.log))
  }
  
  private func freshAsset(url: URL) -> AVURLAsset {
    let asset = AVURLAsset(url: url)
    return asset
  }
  
  private func freshItem(asset: AVURLAsset) -> AVPlayerItem {
    let item = AVPlayerItem(asset: asset)
    
    let keyPaths = [
      #keyPath(AVPlayerItem.status),
      #keyPath(AVPlayerItem.tracks),
      #keyPath(AVPlayerItem.duration)
    ]
    
    for keyPath in keyPaths {
      item.addObserver(self,
                       forKeyPath: keyPath,
                       options: [.old, .new],
                       context: &playerItemContext)
    }
    
    let nc = NotificationCenter.default
    
    nc.addObserver(self,
                   selector: #selector(onItemDidPlayToEndTime),
                   name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                   object: item)
    
    nc.addObserver(self,
                   selector: #selector(onItemNewErrorLogEntry),
                   name: NSNotification.Name.AVPlayerItemNewErrorLogEntry,
                   object: item)
    
    return item
  }
  
  private func removeObservers(item: AVPlayerItem) {
    let keyPaths = [
      #keyPath(AVPlayerItem.status),
      #keyPath(AVPlayerItem.tracks),
      #keyPath(AVPlayerItem.duration)
    ]
    for keyPath in keyPaths {
      item.removeObserver(self, forKeyPath: keyPath, context: &playerItemContext)
    }
    
    let nc = NotificationCenter.default
    let names = [
      NSNotification.Name.AVPlayerItemDidPlayToEndTime,
      NSNotification.Name.AVPlayerItemNewErrorLogEntry
    ]
    for name in names {
      nc.removeObserver(self, name: name, object: item)
    }
  }
  
  /// Passing `nil` as `url` dismisses the current player and returns `nil`.
  @discardableResult private func freshPlayer(with url: URL? = nil) -> AVPlayer? {
    if let prev = player?.currentItem {
      removeObservers(item: prev)
    }
    
    guard let url = url else {
      player = nil
      return nil
    }
    
    let asset = freshAsset(url: url)
    let item = freshItem(asset: asset)
    
    let p = AVPlayer(playerItem: item)
    p.actionAtItemEnd = .pause
    
    playerState = PlayerState(host: self) // TODO: Why exactly?
    
    return p
  }
  
  /// Resume playback of `entry` at `time`. Passing an invalid time, however, 
  /// causes the item to start from the beginning.
  ///
  /// - Parameters:
  ///   - entry: The entry whose enclosed audio media is played.
  ///   - time: Seek to `time` before playback begins.
  ///
  /// - Returns: The new playback state.
  private func resume(_ entry: Entry, at time: CMTime) -> PlaybackState {
    self.entry = entry
    self.time = time
    
    guard let urlString = entry.enclosure?.url,
      let url = URL(string: urlString) else {
      fatalError("URL required")
    }
    
    guard currentURL != url else {
      seekAndPlay()
      return .playing(entry)
    }
    
    player = freshPlayer(with: url)
    return .preparing(entry)
  }
  
  /// Returns a time slightly before the previous play time matching `uid` or
  /// an invalid time if no time to resume from is available. The invalid time,
  /// instead of nil, enables uniform handling down the line, as supposed seek
  /// times have to be validated anyways.
  ///
  /// - Parameter uid: The identifier for the item.
  ///
  /// - Returns: A time to resume from or an invalid time.
  private func time(for uid: String) -> CMTime {
    if let t = TimeRepository.shared.time(uid: uid) {
      return CMTimeSubtract(t, CMTime(seconds: 5, preferredTimescale: t.timescale))
    }
    return CMTime()
  }
  
  // MARK: - FSM
  
  var state = PlaybackState.paused {
    didSet {
      delegate?.playback(session: self, didChange: state)
    }
  }
  
  @discardableResult fileprivate func event(_ e: PlaybackEvent) -> Bool {
    
    let oldState = state
    
    defer {
      if #available(iOS 10.0, *) {
        os_log("%{public}@, after: %{public}@, while %{public}@",
               log: log, type: .debug,
               String(describing: state),
               String(describing: e),
               String(describing: oldState))
      }
    }
    
    switch state {
      
    case .paused:
      
      //      assert(playerState.isPaused)
      
      switch e {
      case .pause:
        return true
      case .play(let entry):
        guard let enclosureURL = entry.enclosure?.url,
          let url = URL(string: enclosureURL) else {
            fatalError("no enclosure")
        }
        
        state = resume(entry, at: time(for: url.absoluteString))
        
        return true
      case .ready:
        assert(playerState.isReadyToPlay)
        
        state = .paused
        
        return true
      default:
        break
      }
      
    case .preparing:
      
      switch e {
      case .play(let entry):
        guard
          let enclosureURL = entry.enclosure?.url,
          let url = URL(string: enclosureURL) else {
            fatalError("no enclosure")
        }
        
        defer {
          state = .preparing(entry)
        }
        
        guard url != currentURL else {
          return true
        }
        
        state = resume(entry, at: time(for: url.absoluteString))
        
        return true
      case .error(let er):
        assert(playerState.hasFailed)
        
        freshPlayer()
        NowPlaying.reset()
        
        delegate?.playback(session: self, error: er)
        state = .paused
        
        return false
      case .pause:
  
        state = .paused
        
        return true
      case .ready:
        assert(playerState.isReadyToPlay)
        
        seekAndPlay()
        
        state = .playing(entry!)
        
        return true
      case .video:
        // The tracks property, triggering this event, becomes available while
        // status is still unknown.
        
        state = .viewing(player!)
        
        return true
      default:
        break
      }
      
    case .playing:
      
      // assert(playerState.isPlaying)
      
      guard let player = self.player else {
        fatalError("player expected")
      }
      
      guard let tid = currentURL?.absoluteString else {
        fatalError("cannot identify time")
      }
      
      switch e {
      case .ready:
        state = .playing(entry!)
        
        return true
      case .pause:
        player.pause()
        
        NowPlaying.set(entry: entry!, player: player)
        TimeRepository.shared.set(player.currentTime(), for: tid)
        
        state = .paused
        
        return true
      case .play(let entry):
        guard let enclosureURL = entry.enclosure?.url,
          let url = URL(string: enclosureURL) else {
            fatalError("no enclosure")
        }
        
        guard url != currentURL else {
          
          // I‘m not happy that we‘re actually seeing this from time to time.
          
          print("already playing")
          return true
        }
        
        state = resume(entry, at: time(for: url.absoluteString))
        
        return true
      case .end:
        NowPlaying.set(entry: entry!, player: player)
        TimeRepository.shared.removeTime(for: tid)
        
        removeObservers(item: player.currentItem!)
        self.player = nil
        
        time = nil
        
        state = .paused
        
        return true
      default:
        break
      }
      
    case .viewing:
      
      switch e {
      case .ready:
        
        state = .viewing(player!)
        
        return true
      default:
        break
      }
    }
    
    // Obviously, if we reach this, we didn‘t handle the event and thus crash.
    
    if #available(iOS 10.0, *) {
      os_log("unhandled event: %{public}@ for state: %{public}@",
             log: log, type: .error,
             String(describing: e),
             String(describing: oldState))
    }
    
    fatalError()
  }

}

// MARK: - Playing

extension PlaybackSession: Playing {
  
  /// Plays enclosue of given `entry`. Without an entry, it assumes you want to 
  /// resume playing the current episode, meaning the enclosure of the current 
  /// entry. In this case, if no current entry exists, it is an error. The 
  /// episode will be resumed from its previous play position if possible.
  ///
  /// - Parameter entry: The `entry` to play or `nil`.
  ///
  /// - Returns: `true` if it worked.
  @discardableResult public func play(_ entry: Entry? = nil) -> Bool {
    return event(.play(entry ?? self.entry!))
  }
  
  /// Pauses the player.
  @discardableResult public func pause() -> Bool {
    return event(.pause)
  }
  
}

// MARK: - Intermediating

extension PlaybackSession: Intermediating {
  
  public func activate() throws {
    let audio = AVAudioSession.sharedInstance()
    
    guard audio.category != AVAudioSessionCategoryPlayback else {
      return
    }
    
    try audio.setCategory(AVAudioSessionCategoryPlayback)
    try audio.setActive(true)
    
    addRemoteCommandTargets()
  }
  
  public func deactivate() throws {
    try AVAudioSession.sharedInstance().setActive(false)
    
    removeRemoteCommandTargets()
  }
  
}
