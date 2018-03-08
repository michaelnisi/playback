//
//  PlaybackSession.swift
//  Playback
//
//  Created by Michael Nisi on 01.03.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import AVFoundation
import AVKit
import FeedKit
import Foundation
import os.log

let log = OSLog(subsystem: "ink.codes.playback", category: "session")

/// Persists play times.
public protocol Times {
  func time(uid: String) -> CMTime?
  func set(_ time: CMTime, for uid: String)
  func removeTime(for uid: String)
}

struct RemoteCommandTargets {
  let pause: Any?
  let play: Any?
  let togglePlayPause: Any?
  let nextTrack: Any?
  let previousTrack: Any?
}

/// Implements `Playback` as
/// [Finite-state machine](https://en.wikipedia.org/wiki/Finite-state_machine).
public final class PlaybackSession: NSObject, Playback {
  
  private let times: Times
  
  public init(times: Times) {
    self.times = times
    super.init()
    try! activate()
  }
  
  public var delegate: PlaybackDelegate?
  
  // MARK: Internals
  
  var remoteCommandTargets: RemoteCommandTargets?
  
  /// The current player.
  private var player: AVPlayer?
  
  /// The URL of the currently playing asset.
  private var assetURL: URL? {
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
  
  /// Returns a time slightly, five seconds at the moment, before the previous
  /// play time matching `uid` or an invalid time if no time to resume from is
  /// available. The invalid time, instead of nil, enables uniform handling down
  /// the line, as supposed seek times have to be validated anyways.
  ///
  /// - Parameter uid: The identifier for the item.
  ///
  /// - Returns: A time to resume from or an invalid time.
  private func time(for uid: String) -> CMTime {
    if let t = times.time(uid: uid) {
      return CMTimeSubtract(t, CMTime(seconds: 5, preferredTimescale: t.timescale))
    }
    return CMTime()
  }
  
  private func startTime(item: AVPlayerItem?, url: String) -> CMTime? {
    guard let seekableTimeRanges = item?.seekableTimeRanges else {
      return nil
    }
    
    let t = time(for: url)
    
    guard let st = seekableTime(t, within: seekableTimeRanges) else {
      let r = seekableTimeRanges.first as! CMTimeRange
      return r.start
    }
    
    return st
  }
  
  /// Resumes playback of the current item.
  public func seek(playing: Bool) -> PlaybackState {
    guard
      let player = self.player,
      let entry = self.currentEntry,
      let enclosure = entry.enclosure,
      let tracks = player.currentItem?.tracks else {
      fatalError("requirements to seek and play not met")
    }

    guard player.rate != 1, !tracks.isEmpty else {
      return state
    }
    
    let newState: PlaybackState = {
      guard playing else {
        return .paused(entry)
      }
      return isVideo(tracks: tracks, type: enclosure.type)
        ? .viewing(entry, player)
        : .listening(entry)
    }()
    
    guard let time = startTime(item: player.currentItem, url: enclosure.url) else {
      if playing {
        player.play()
      }
      return newState
    }
    
    player.currentItem?.cancelPendingSeeks()
    
    player.seek(to: time) { [weak self] finished in
      guard finished else {
        return
      }
      DispatchQueue.main.async { [weak self] in
        if playing || self?.shouldPlay ?? false {
          player.play()
        }
        NowPlaying.set(entry: entry, player: player)
      }
    }
    
    return newState
  }
  
  private func isVideo(tracks: [AVPlayerItemTrack], type: EnclosureType) -> Bool {
    let containsVideo = tracks.contains {
      $0.assetTrack.mediaType == AVMediaType.video
    }
    return containsVideo && type.isVideo
  }
  
  private var playerItemContext = 0
  
  private func onTracksChange(_ change: [NSKeyValueChangeKey : Any]?) {
    guard let tracks = change?[.newKey] as? [AVPlayerItemTrack] else {
      fatalError("no tracks to play")
    }
    
    guard let enclosure = currentEntry?.enclosure,
      isVideo(tracks: tracks, type: enclosure.type) else {
        return
    }
    
    state = event(.video)
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
      state = event(.ready)
    case .failed:
      let error = PlaybackError.failed
      state = event(.error(error))
    case .unknown:
      let error = PlaybackError.unknown
      state = event(.error(error))
    }
  }
  
  // Although the UIKit documentation states that duration would be available
  // when status is readyToPlay, the duration property needs to be monitored
  // separately to aquire a valid value.
  //
  // Another concern, for some reason, it is called multiple times, hence the
  // guard.
  
  private func onDurationChange(_ change: [NSKeyValueChangeKey : Any]?) {
    os_log("duration change", log: log, type: .debug)
    
    guard change?[.newKey] as? CMTime != change?[.oldKey] as? CMTime else {
      os_log("observed redundant duration change", log: log)
      return
    }
    
    NowPlaying.set(entry: currentEntry!, player: player!)
  }
  
  private func onTimeControlChange(_ change: [NSKeyValueChangeKey : Any]?) {
    if #available(iOS 10.0, *) {
      // Direct cast to AVPlayerTimeControlStatus fails here.
      guard let s = change?[.newKey] as? Int,
        let status = AVPlayerTimeControlStatus(rawValue: s) else {
          return
      }
      
      switch status {
      case .paused:
        state = event(.paused)
      case .playing:
        state = event(.playing)
      case .waitingToPlayAtSpecifiedRate:
        break
      }
    }
  }
  
  override public func observeValue(forKeyPath keyPath: String?,
                                    of object: Any?,
                                    change: [NSKeyValueChangeKey : Any]?,
                                    context: UnsafeMutableRawPointer?) {
    
    guard context == &playerItemContext || context == &playerContext else {
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
    } else if keyPath == #keyPath(AVPlayer.timeControlStatus) {
      onTimeControlChange(change)
    }
  }
  
  @objc func onItemDidPlayToEndTime() {
    state = event(.end)
  }
  
  @objc func onItemNewErrorLogEntry() {
    state = event(.error(.log))
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
  
  private var playerContext = 0
  
  /// Passing `nil` as `url` dismisses the current player and returns `nil`.
  @discardableResult
  private func freshPlayer(with url: URL? = nil) -> AVPlayer? {
    if let prev = player?.currentItem {
      removeObservers(item: prev)
      player?.replaceCurrentItem(with: nil)
    }
    
    guard let url = url else {
      player = nil
      return nil
    }
    
    let asset = freshAsset(url: url)
    let item = freshItem(asset: asset)
    
    let start = Date()
    
    let newPlayer = AVPlayer(playerItem: item)
    newPlayer.actionAtItemEnd = .pause
    
    let keyPath = #keyPath(AVPlayer.timeControlStatus)
    
    newPlayer.addObserver(self,
                          forKeyPath: keyPath,
                          options: [.old, .new],
                          context: &playerContext)
    
    if let oldPlayer = self.player {
      oldPlayer.removeObserver(self, forKeyPath: keyPath, context: &playerContext)
    }
    
    let took = start.timeIntervalSinceNow
    os_log("** took %@ seconds to create a new player",
           log: log, type: .debug, took.description)
    
    return newPlayer
  }
  
  private func playback(_ entry: Entry) -> PlaybackState {
    guard
      let urlString = entry.enclosure?.url,
      let url = URL(string: urlString) else {
      fatalError("you are drunk: URL required")
    }
    
    guard let proxiedURL = delegate?.proxy(url: url) else {
      os_log("aborting playback: not reachable: %@", log: log, url.absoluteString)
      return event(.paused)
    }
    
    guard assetURL != proxiedURL else {
      return seek(playing: true)
    }
    
    player = freshPlayer(with: proxiedURL)
    
    return .preparing(entry)
  }
  
  private func pause(_ entry: Entry) -> PlaybackState {
    guard
      let urlString = entry.enclosure?.url,
      let url = URL(string: urlString) else {
      fatalError("you are drunk: URL required")
    }
    
    guard let proxiedURL = delegate?.proxy(url: url) else {
      os_log("aborting playback: not reachable: %@", log: log, url.absoluteString)
      return event(.paused)
    }
    
    guard assetURL != proxiedURL else {
      return seek(playing: false)
    }
    
    player = freshPlayer(with: proxiedURL)
    
    return .paused(entry)
  }
  
  // MARK: - FSM
  
  private func setCurrentTime() {
    guard let player = self.player,
      let url = currentEntry?.enclosure?.url else {
      os_log("** could not set time", log: log, type: .debug)
      return
    }
    
    let t = player.currentTime()
    let threshold = CMTime(seconds: 15, preferredTimescale: t.timescale)
    
    let leading = CMTimeCompare(t, threshold)
    guard leading != -1 else {
      times.removeTime(for: url)
      return
    }
    
    if let duration = player.currentItem?.duration,
      duration != kCMTimeIndefinite {
      let end = CMTimeSubtract(duration, threshold)
      let trailing = CMTimeCompare(t, end)
      guard trailing == -1 else {
        times.removeTime(for: url)
        return
      }
    }
    
    times.set(t, for: url)
  }
  
  public private(set) var state: PlaybackState = .inactive(nil) {
    didSet {
      os_log("new state: %{public}@, old state: %{public}@", log: log, type: .debug,
              state.description, oldValue.description)
      guard state != oldValue else {
        return
      }
      
      switch state {
      case .paused(let entry), .preparing(let entry):
        NowPlaying.set(entry: entry, player: player)
      case .inactive, .listening, .viewing:
        break
      }

      delegate?.playback(session: self, didChange: state)
    }
  }
  
  private var shouldPlay = false

  /// Returns the new playback state, arrived at by handling event `e` according
  /// to the current state.
  private func event(_ e: PlaybackEvent) -> PlaybackState {
    os_log("event: %@", log: log, type: .debug, e.description)

    // MARK: occured while:
    switch state {
      
    case .inactive(let fault):
       // MARK: inactive
      guard fault == nil else {
        os_log("unresolved error while inactive: %{public}@",
               log: log, type: .error, fault! as CVarArg)
        fatalError(String(describing: fault))
      }

      switch e {
      case .change(let entry):
        guard let newEntry = entry else {
          return deactivate()
        }
        return pause(newEntry)
      
      case .play(let entry):
        guard entry == currentEntry else {
          return state
        }
        return playback(currentEntry!)

      case .end, .error, .paused, .playing, .ready, .video:
        os_log("""
          unhandled: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .error, e.description, state.description)
        fatalError(String(describing: e))
      }
      
    case .paused:
      // MARK: paused
      switch e {
      case .change(let entry):
        guard let newEntry = entry else {
          return deactivate()
        }
        return pause(newEntry)
        
      case .play(let entry):
        guard entry == currentEntry else {
          return state
        }
        guard let player = self.player else {
          fatalError("impossible")
        }
        switch player.status {
        case .unknown:
          shouldPlay = true
          return state
        case .readyToPlay:
          return playback(currentEntry!)
        case .failed:
          fatalError("failed")
        }

      case .playing: // TODO: Add entry
        shouldPlay = false
        guard let entry = currentEntry,
          let player = self.player,
          let tracks = player.currentItem?.tracks,
          let type = entry.enclosure?.type else {
          fatalError("impossible")
        }
        if isVideo(tracks: tracks, type: type) {
          return .viewing(entry, player)
        } else {
          return .listening(entry)
        }
        
      case .ready:
        return seek(playing: false)
        
      case .paused, .video:
        return state
        
      case .end, .error:
        os_log("""
          unhandled: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .error, e.description, state.description)
        fatalError(String(describing: e))
      }
      
    case .preparing(let entry):
      // MARK: preparing
      switch e {
      case .error(let er):
        delegate?.playback(session: self, error: er)
        return .paused(entry)
        
      case .play(let entry):
        guard entry == currentEntry else {
          return state
        }
        return playback(currentEntry!)
        
      case .paused:
        return .paused(entry)
        
      case .ready:
        return seek(playing: true)
        
      case .video:
        return .viewing(entry, player!)
        
      case .change, .end, .playing:
        os_log("""
          unhandled: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .error, e.description, state.description)
        fatalError(String(describing: e))
      }
      
    case .listening(let entry), .viewing(let entry, _):
      // MARK: listening or viewing
      switch e {
      case .error(let er):
        delegate?.playback(session: self, error: er)
        return state
        
      case .paused, .end:
        setCurrentTime()
        return .paused(entry)
        
      case .change(let newEntry):
        setCurrentTime()
        guard let actualEntry = newEntry else {
          return deactivate()
        }
        return playback(actualEntry)
        
      case .ready, .playing, .play:
        return state

      case .video:
        os_log("""
          unhandled: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .error, e.description, state.description)
        fatalError(String(describing: e))
      }
      
    }

  }
  
}

// MARK: - Managing Audio Session and Remote Command Center

extension PlaybackSession {
  
  private func activate() throws {
    os_log("activate", log: log)
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(AVAudioSessionCategoryPlayback)
    try session.setActive(true)
    addRemoteCommandTargets()
  }
  
  private func deactivate() -> PlaybackState {
    os_log("deactivate", log: log)
    do {
      try AVAudioSession.sharedInstance().setActive(false)
    } catch {
      return .inactive(error)
    }
    return .inactive(nil)
  }
  
  public func reclaim() {
    addRemoteCommandTargets()
  }
  
}

// MARK: - Playing

extension PlaybackSession: Playing {
  
  public var currentEntry: Entry? {
    get {
      switch state {
      case .preparing(let entry),
           .listening(let entry),
           .viewing(let entry, _),
           .paused(let entry):
        return entry
      case .inactive:
        return nil
      }
    }
    
    set {
      guard newValue != currentEntry else {
        return
      }
      
      if let entry = newValue {
        assert(entry.enclosure != nil, "URL required")
      }
      
      state = event(.change(newValue))
    }
    
  }
  
  @discardableResult
  public func resume() -> Bool {
    guard let entry = currentEntry else {
      return false
    }
    state = event(.play(entry))
    return true
  }
  
  @discardableResult
  public func pause() -> Bool {
    guard currentEntry != nil else {
      return false
    }
    player?.pause()
    return true
  }
  
}

