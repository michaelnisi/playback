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
import Ola

let log = OSLog.disabled

let worker = DispatchQueue(label: "ink.codes.playback.worker")

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
  }

  public var delegate: PlaybackDelegate?

  // MARK: Internals

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
      guard let r = seekableTimeRanges.first as? CMTimeRange else {
        return nil
      }
      return r.start
    }

    return st
  }

  /// Sets the playback time to previous for `entry`.
  public func seek(_ entry: Entry, playing: Bool) -> PlaybackState {
    guard
      let player = self.player,
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

  private func isVideo(tracks: [AVPlayerItemTrack], type: EnclosureType) -> Bool {
    let containsVideo = tracks.contains {
      $0.assetTrack.mediaType == .video
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

    event(.video)
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
      event(.ready)
    case .failed:
      event(.error(.failed))
    case .unknown:
      // TODO: Is this even an error?
      event(.error(.unknown))
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
        event(.paused)
      case .playing:
        event(.playing)
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
    event(.end)
  }

  @objc func onItemNewErrorLogEntry() {
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

    player?.removeObserver(self, forKeyPath: keyPath, context: &playerContext)

    return newPlayer
  }

  private func prepare(_ entry: Entry, playing: Bool = true) -> PlaybackState {
    guard
      let urlString = entry.enclosure?.url,
      let url = URL(string: urlString) else {
      fatalError("unhandled error: invalid enclosure: \(entry)")
    }
    
    guard let proxiedURL = delegate?.proxy(url: url) else {
      os_log("could not prepare: unreachable: %@", log: log, url.absoluteString)
      pausePlayer()
      return .paused(entry, .unreachable)
    }
    
    guard assetURL != proxiedURL else {
      assert(player?.status == .readyToPlay)
      return seek(entry, playing: playing)
    }
    
    player = makeAVPlayer(url: proxiedURL)
    
    return .preparing(entry, playing)
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
        switch state {
        case .paused(_, let error), .inactive(let error):
          return error != nil
        default:
          return false
        }
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
  
  /// Submits a block pausing our player on the main queue.
  private func pausePlayer() {
    DispatchQueue.main.async {
      self.player?.pause()
    }
  }

  private func event(_ e: PlaybackEvent) {
    sQueue.sync {
      os_log("event: %{public}@", log: log, type: .debug, e.description)

      // MARK: ...occured while:
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
            return state = deactivate()
          }
          do {
            try activate()
          } catch {
            return state = .inactive(.session)
          }
          return state = prepare(newEntry, playing: false)

        case .error, .end, .paused, .playing, .ready, .video,
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
          // Checking the error to give a chance for retrying.
          if pausedError == nil {
            guard entry != pausedEntry else {
              return
            }
          }
          guard let newEntry = entry else {
            return state = deactivate()
          }
          return state = prepare(newEntry, playing: false)

        case .toggle, .resume:
          return state = prepare(pausedEntry, playing: true)

        case .playing:
          guard
            let player = self.player,
            let tracks = player.currentItem?.tracks,
            let type = pausedEntry.enclosure?.type else {
            fatalError("impossible")
          }
          if isVideo(tracks: tracks, type: type) {
            return state = .viewing(pausedEntry, player)
          } else {
            return state = .listening(pausedEntry)
          }

        case .ready:
          return state = seek(pausedEntry, playing: false)

        case .paused, .video, .pause:
          os_log("""
          ignoring: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .debug, e.description, state.description)
          return

        case .error(let er):
          pausePlayer()
          let itemError = self.player?.currentItem?.error ?? er
          os_log("error while paused: %{public}@", log: log, type: .error,
                 itemError as CVarArg)
          return state = PlaybackState(paused: pausedEntry, error: itemError)

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
          pausePlayer()
          let itemError = self.player?.currentItem?.error ?? er
          os_log("error while preparing: %{public}@", log: log, type: .error,
                 itemError as CVarArg)
          return state = PlaybackState(paused: preparingEntry, error: itemError)

        case .resume:
          return state = .preparing(preparingEntry, true)

        case .pause:
          return pausePlayer()

        case .toggle:
          return state = .preparing(preparingEntry, !preparingShouldPlay)

        case .paused:
          return state = .paused(preparingEntry, nil)

        case .ready:
          return state = seek(preparingEntry, playing: preparingShouldPlay)

        case .change(let entry):
          guard entry != preparingEntry else {
            return
          }
          guard let newEntry = entry else {
            return state = deactivate()
          }
          return state = prepare(newEntry, playing: preparingShouldPlay)

        case .playing:
          guard
            let player = self.player,
            let tracks = player.currentItem?.tracks,
            let type = preparingEntry.enclosure?.type else {
            fatalError("impossible")
          }
          if isVideo(tracks: tracks, type: type) {
            return state = .viewing(preparingEntry, player)
          } else {
            return state = .listening(preparingEntry)
          }

        case .video:
          os_log("""
          ignoring: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .debug, e.description, state.description)
          return

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
          pausePlayer()
          
          let itemError = self.player?.currentItem?.error ?? er
          os_log("error while listening or viewing: %{public}@",
                 log: log, type: .error, itemError as CVarArg)
          return state = PlaybackState(paused: consumingEntry, error: itemError)

        case .paused, .end:
          assert(player?.error == nil)
          assert(player?.currentItem?.error == nil)
          setCurrentTime()
          return state = .paused(consumingEntry, nil)

        case .change(let changingEntry):
          guard changingEntry != consumingEntry else {
            return
          }
          setCurrentTime()
          guard let actualEntry = changingEntry else {
            return state = deactivate()
          }
          return state = prepare(actualEntry)

        case .toggle, .pause:
          return pausePlayer()

        case .ready, .playing, .resume:
          os_log("""
          ignoring: {
            event: %{public}@
            while: %{public}@
          }
          """, log: log, type: .debug, e.description, state.description)
          return

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
    os_log("activating", log: log)

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(AVAudioSessionCategoryPlayback)
    try session.setActive(true)

    addRemoteCommandTargets()
  }

  private func deactivate() -> PlaybackState {
    os_log("deactivatiing", log: log)
    
    do {
      try AVAudioSession.sharedInstance().setActive(false)
    } catch {
      return .inactive(.session)
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
  
  public func setCurrentEntry(_ newValue: Entry?) {
    worker.async {
      guard newValue != self.currentEntry else {
        return
      }
      
      if let entry = newValue {
        assert(entry.enclosure != nil, "URL required")
      }
      
      self.event(.change(newValue))
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
  
  // TODO: Review API
  //
  // As the returns of these APIs, initially meant for remote command blocks,
  // are all statically returning true, these have to thought over.

  public func forward() -> Bool {
    worker.async {
      guard let item = self.delegate?.nextItem() else {
        return
      }
      
      self.setCurrentEntry(item)
      
      guard self.checkState() else {
        os_log("forward command failed", log: log, type: .error)
        return
      }
    }
    
    return true
  }

  public func backward() -> Bool {
    worker.async {
      guard let item = self.delegate?.previousItem() else {
        return
      }
      
      self.setCurrentEntry(item)
      
      guard self.checkState() else {
        os_log("backward command failed", log: log, type: .error)
        return
      }
    }

    return true
  }

  @discardableResult
  public func resume() -> Bool {
    worker.async {
      self.event(.resume)
      
      guard self.checkState() else {
        os_log("resume command failed", log: log, type: .error)
        return
      }
    }
    
    return true
  }

  @discardableResult
  public func pause() -> Bool {
    worker.async {
      self.event(.pause)
      
      guard self.checkState() else {
        os_log("pause command failed", log: log, type: .error)
        return
      }
    }

    return true
  }

  @discardableResult
  public func toggle() -> Bool {
    worker.async {
      self.event(.toggle)
      
      guard self.checkState() else {
        os_log("toggle command failed", log: log, type: .error)
        return
      }
    }

    return true
  }

}

