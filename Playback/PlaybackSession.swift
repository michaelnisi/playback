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

  // Internal serial queue.
  private let sQueue = DispatchQueue(label: "ink.codes.playback.serial")

  public init(times: Times) {
    self.times = times
    super.init()
//    try! activate()
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
    return DispatchQueue.global().sync {
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
          return .paused(entry, nil)
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
      
      player.seek(to: time) { finished in
        guard finished else {
          return
        }
        DispatchQueue.main.async {
          if playing {
            player.play()
          }
          NowPlaying.set(entry: entry, player: player)
        }
      }
      
      return newState
    }
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

    if let newNumber = change?[.newKey] as? NSNumber,
      let newStatus = AVPlayerItemStatus(rawValue: newNumber.intValue) {
      status = newStatus
    } else {
      status = .unknown
    }

    switch status {
    case .readyToPlay:
      state = event(.ready)
    case .failed:
      state = event(.error(.failed))
    case .unknown:
      // TODO: Is this even an error?
      state = event(.error(.unknown))
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

    guard let e = currentEntry, let p = self.player else {
      os_log("unexpected duration change: no entry or player", log: log,
             type: .error)
      return
    }
    
    NowPlaying.set(entry: e, player: p)
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
  private func makeAVPlayer(url: URL? = nil) -> AVPlayer? {
    if let prev = player?.currentItem {
      removeObservers(item: prev)
      delegate?.dismissVideo()
    }

    guard let url = url else {
      player = nil
      return nil
    }

    let asset = freshAsset(url: url)
    let item = freshItem(asset: asset)

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

    return newPlayer
  }

  private func prepare(_ entry: Entry, playing: Bool = true) -> PlaybackState {
    return DispatchQueue.global().sync {
      guard
        let urlString = entry.enclosure?.url,
        let url = URL(string: urlString) else
      {
        fatalError("unhandled error: invalid enclosure: \(entry)")
      }
      
      guard let proxiedURL = delegate?.proxy(url: url) else {
        os_log("could not prepare: unreachable: %@", log: log, url.absoluteString)
        return event(.error(.unreachable))
      }
      
      guard assetURL != proxiedURL else {
        return seek(playing: playing)
      }
      
      player = makeAVPlayer(url: proxiedURL)
      
      return .preparing(entry, playing)
    }
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

  private var state = PlaybackState.inactive(nil) {
    didSet {
      os_log("new state: %{public}@, old state: %{public}@",
             log: log, type: .debug,
             state.description, oldValue.description
      )

      let needsUpdate: Bool = {
        guard state == oldValue else {
          return true
        }
        if case .paused(_, let error) = state {
          return error != nil
        }
        return false
      }()
      
      guard needsUpdate else {
        return
      }
      
      delegate?.playback(session: self, didChange: state)
      
      switch state {
      case .paused(let entry, _), .preparing(let entry, _):
        NowPlaying.set(entry: entry, player: player)
      case .inactive, .listening, .viewing:
        break
      }
    }
    
  }

  /// Returns the new playback state after processing event `e` appropriately
  /// to the current state. The event handler of the state machine, where the
  /// shit hits the fan. **Don’t block!**
  ///
  /// The playback state machine has five states: inactive, paused, preparing,
  /// listening, and viewing; where listening and viewing are incorporated.
  ///
  /// # inactive
  ///
  /// ## change
  ///
  /// The `.change(Entry?)` event with an entry activates the session and
  /// transits to the **paused** state, while `.change` without entry
  /// deactivates the session remaining in **inactive** state.
  ///
  /// # paused
  ///
  /// ## change
  ///
  /// In **paused** state the current entry can be changed or set to `nil`
  /// deactivating the session.
  ///
  /// ## toggle/resume
  ///
  /// Plays the current item, eventually, after transfering to **preparing**,
  /// which will trigger `ready` or `error` events.
  ///
  /// ...
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
  private func event(_ e: PlaybackEvent) -> PlaybackState {
    return sQueue.sync {
      os_log("event: %{public}@", log: log, type: .debug, e.description)
      
      // MARK: Occured while:
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
          do {
            try activate()
          } catch {
            return .inactive(.session)
          }
          return prepare(newEntry, playing: false)
          
        case .end, .error, .paused, .playing, .ready, .video,
             .toggle, .resume, .pause:
          os_log("""
          unhandled: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .error, e.description, state.description)
          fatalError(String(describing: e))
        }
        
      case .paused(let pausedEntry, let pausedError):
        // MARK: paused
        switch e {
        case .change(let entry):
          if pausedError == nil {
            // Giving a chance to retry with an error.
            guard entry != pausedEntry else {
              return state
            }
          }
          guard let newEntry = entry else {
            return deactivate()
          }
          return prepare(newEntry, playing: false)
          
        case .toggle, .resume:
          return prepare(pausedEntry, playing: true)

        case .playing:
          guard
            let player = self.player,
            let tracks = player.currentItem?.tracks,
            let type = pausedEntry.enclosure?.type else {
            fatalError("impossible")
          }
          if isVideo(tracks: tracks, type: type) {
            return .viewing(pausedEntry, player)
          } else {
            return .listening(pausedEntry)
          }
          
        case .ready:
          return seek(playing: false)
          
        case .paused, .video, .pause:
          os_log("""
          ignoring: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .debug, e.description, state.description)
          return state
          
        case .error(let er):
          DispatchQueue.global().async {
            self.player?.pause()
          }
          let itemError = self.player?.currentItem?.error ?? er
          os_log("error while paused: %{public}@", log: log, type: .error,
                 itemError as CVarArg)
          return PlaybackState(paused: pausedEntry, error: itemError)
          
        case .end:
          os_log("""
          unhandled: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .error, e.description, state.description)
          fatalError(String(describing: e))
        }
        
      case .preparing(let preparingEntry, let preparingShouldPlay):
        // MARK: preparing
        switch e {
        case .error(let er):
          DispatchQueue.global().async {
            self.player?.pause()
          }
          let itemError = self.player?.currentItem?.error ?? er
          os_log("error while preparing: %{public}@", log: log, type: .error,
                 itemError as CVarArg)
          return PlaybackState(paused: preparingEntry, error: itemError)
          
        case .resume:
          return .preparing(preparingEntry, true)
          
        case .pause:
          DispatchQueue.global().async {
            self.player?.pause()
          }
          return state
          
        case .toggle:
          return .preparing(preparingEntry, !preparingShouldPlay)
          
        case .paused:
          return .paused(preparingEntry, nil)
          
        case .ready:
          return seek(playing: preparingShouldPlay)
          
        case .change(let entry):
          guard entry != preparingEntry else {
            return state
          }
          guard let newEntry = entry else {
            return deactivate()
          }
          return prepare(newEntry, playing: preparingShouldPlay)
          
        case .playing:
          guard
            let player = self.player,
            let tracks = player.currentItem?.tracks,
            let type = preparingEntry.enclosure?.type else {
            fatalError("impossible")
          }
          if isVideo(tracks: tracks, type: type) {
            return .viewing(preparingEntry, player)
          } else {
            return .listening(preparingEntry)
          }
          
        case .video:
          os_log("""
          ignoring: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .debug, e.description, state.description)
          return state
          
        case .end:
          os_log("""
          unhandled: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .error, e.description, state.description)
          fatalError(String(describing: e))
        }
        
      case .listening(let consumingEntry), .viewing(let consumingEntry, _):
        // MARK: listening/viewing
        switch e {
        case .error(let er):
          DispatchQueue.global().async {
            self.player?.pause()
          }
          let itemError = self.player?.currentItem?.error ?? er
          os_log("error while listening or viewing: %{public}@",
                 log: log, type: .error, itemError as CVarArg)
          return PlaybackState(paused: consumingEntry, error: itemError)
          
        case .paused, .end:
          setCurrentTime()
          return .paused(consumingEntry, nil)
          
        case .change(let changingEntry):
          guard changingEntry != consumingEntry else {
            return state
          }
          setCurrentTime()
          guard let actualEntry = changingEntry else {
            return deactivate()
          }
          return prepare(actualEntry)
          
        case .toggle, .pause:
          DispatchQueue.global().async {
            self.player?.pause()
          }
          return state
          
        case .ready, .playing, .resume:
          os_log("""
          ignoring: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .debug, e.description, state.description)
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
    return DispatchQueue.global().sync {
      os_log("deactivate", log: log)
      do {
        try AVAudioSession.sharedInstance().setActive(false)
      } catch {
        return .inactive(.session)
      }
      return .inactive(nil)
    }
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
      case .preparing(let entry, _),
           .listening(let entry),
           .viewing(let entry, _),
           .paused(let entry, _):
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
  
  /// Synchronously checking the playback state with this function isn’t
  /// reliable, for its asynchronous nature. Paused state, for example,
  /// is entered after a delay, when the playback actually has been paused.
  private func checkState() -> Bool {
    switch state {
    case .paused(_, let error):
      return error == nil
    case .preparing, .listening, .viewing:
      return true
    case .inactive:
      return false
    }
  }
  
  public func forward() -> Bool {
    guard let item = delegate?.nextItem() else {
      return false
    }
    
    currentEntry = item

    guard checkState() else {
      os_log("forward command failed", log: log, type: .error)
      return false
    }
    
    return true
  }
  
  public func backward() -> Bool {
    guard let item = delegate?.previousItem() else {
      return false
    }
    
    currentEntry = item

    guard checkState() else {
      os_log("backward command failed", log: log, type: .error)
      return false
    }
    
    return true
  }
  
  @discardableResult
  public func resume() -> Bool {
    state = event(.resume)
    
    guard checkState() else {
      os_log("resume command failed", log: log, type: .error)
      return false
    }

    return true
  }
  
  @discardableResult
  public func pause() -> Bool {
    state = event(.pause)
    
    guard checkState() else {
      os_log("pause command failed", log: log, type: .error)
      return false
    }
    
    return true
  }
  
  @discardableResult
  public func toggle() -> Bool {
    state = event(.toggle)
    
    guard checkState() else {
      os_log("toggle command failed", log: log, type: .error)
      return false
    }
    
    return true
  }

}

