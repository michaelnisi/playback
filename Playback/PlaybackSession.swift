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

let log = OSLog(subsystem: "ink.codes.playback", category: "sess")

struct RemoteCommandTargets {
  let pause: Any?
  let play: Any?
  let togglePlayPause: Any?
  let nextTrack: Any?
  let previousTrack: Any?
}

/// Implements `Playback` as FSM using worker and a serial queue.
public final class PlaybackSession: NSObject, Playback {

  private let times: Times

  // Internal serial queue, our inbox for events.
  private let sQueue = DispatchQueue(
    label: "ink.codes.playback.PlaybackSession",
    target: .global()
  )

  /// Makes a new playback session.
  ///
  /// - Parameter times: A repository for storing times (per URL).
  public init(times: Times) {
    self.times = times
    super.init()
  }

  public var delegate: PlaybackDelegate?

  // MARK: Internals

  /// An ephemeral player currently in use.
  private var player: AVPlayer? {
    willSet {
      player?.removeObserver(
        self,
        forKeyPath: #keyPath(AVPlayer.timeControlStatus),
        context: &playerContext
      )
    }

    didSet {
      player?.addObserver(
        self,
        forKeyPath: #keyPath(AVPlayer.timeControlStatus),
        options: [.old, .new],
        context: &playerContext
      )
    }
  }

  /// The URL of the currently playing asset.
  private var assetURL: URL? {
    guard let asset = player?.currentItem?.asset as? AVURLAsset else {
      return nil
    }

    return asset.url
  }

  private static func seekableTime(
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
  /// - Parameter url: The identifier for the item.
  ///
  /// - Returns: A time to resume from or an invalid time.
  private func startTime(matching url: String) -> CMTime {
    let t = times.time(uid: url)
    
    guard t.isValid, !t.isIndefinite else {
      return CMTime()
    }
    
    return CMTimeSubtract(t, CMTime(seconds: 5, preferredTimescale: t.timescale))
  }

  private func startTime(item: AVPlayerItem?, url: String, position: TimeInterval? = nil) -> CMTime? {
    guard let seekableTimeRanges = item?.seekableTimeRanges else {
      return nil
    }

    let t = position == nil ?
      startTime(matching: url) :
      CMTime(seconds: position!, preferredTimescale: 1000000)

    guard let st = PlaybackSession.seekableTime(t, within: seekableTimeRanges) else {
      guard let r = seekableTimeRanges.first as? CMTimeRange else {
        return nil
      }
      return r.start
    }

    return st
  }

  /// Sets the playback time to previous for `entry`.
  public func seek(_ entry: Entry, playing: Bool, position: TimeInterval? = nil) -> PlaybackState {
    guard
      let player = self.player,
      let enclosure = entry.enclosure,
      let tracks = player.currentItem?.tracks, !tracks.isEmpty else {
      fatalError("requirements to seek and play not met")
    }

    let newState: PlaybackState = {
      guard playing else {
        return .paused(entry, nil)
      }
      return PlaybackSession.isVideo(tracks: tracks, type: enclosure.type)
        ? .viewing(entry, player)
        : .listening(entry)
    }()
    
    guard let time = startTime(
      item: player.currentItem, url: enclosure.url, position: position) else {
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

      // Saving successfully seeked time positions.
      if position != nil {
        self.setCurrentTime()
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

  private static func isVideo(
    tracks: [AVPlayerItemTrack], type: EnclosureType) -> Bool {
    let containsVideo = tracks.contains {
      $0.assetTrack?.mediaType == .video
    }
    return containsVideo && type.isVideo
  }

  // The context for player item key-value observation.
  private var playerItemContext = 0

  private func onTracksChange(_ change: [NSKeyValueChangeKey : Any]?) {
    guard let tracks = change?[.newKey] as? [AVPlayerItemTrack] else {
      fatalError("no tracks to play")
    }

    guard let enclosure = currentEntry?.enclosure,
      PlaybackSession.isVideo(tracks: tracks, type: enclosure.type) else {
      return
    }

    // Allowing external playback mode for videos.
    player?.allowsExternalPlayback = true

    event(.video)
  }

  private func onStatusChange(_ change: [NSKeyValueChangeKey : Any]?) {
    let status: AVPlayerItem.Status

    if let newNumber = change?[.newKey] as? NSNumber,
      let newStatus = AVPlayerItem.Status(rawValue: newNumber.intValue) {
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
    @unknown default:
      fatalError("unknown case in switch: \(status)")
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
    // Direct cast to AVPlayerTimeControlStatus fails here.
    guard let s = change?[.newKey] as? Int,
      let status = AVPlayer.TimeControlStatus(rawValue: s) else {
        return
    }

    switch status {
    case .paused:
      event(.paused)
    case .playing:
      event(.playing)
    case .waitingToPlayAtSpecifiedRate:
      break
    @unknown default:
      fatalError("unknown case in switch: \(status)")
    }
  }

  override public func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey : Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    switch (context, keyPath) {
    case (&playerItemContext, #keyPath(AVPlayerItem.tracks)):
      onTracksChange(change)
    case (&playerItemContext, #keyPath(AVPlayerItem.status)):
      onStatusChange(change)
    case (&playerItemContext, #keyPath(AVPlayerItem.duration)):
      onDurationChange(change)
    case (&playerContext, #keyPath(AVPlayer.timeControlStatus)):
      onTimeControlChange(change)
    default:
      super.observeValue(
        forKeyPath: keyPath, of: object, change: change, context: context)
    }
  }

  @objc func onItemDidPlayToEndTime() {
    event(.end)
  }

  @objc func onItemNewErrorLogEntry() {
    event(.error(.log))
  }

  private func makePlayerItem(asset: AVURLAsset) -> AVPlayerItem {
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
                   name: .AVPlayerItemDidPlayToEndTime,
                   object: item)

    nc.addObserver(self,
                   selector: #selector(onItemNewErrorLogEntry),
                   name: .AVPlayerItemNewErrorLogEntry,
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
    let names: [NSNotification.Name] = [
      .AVPlayerItemDidPlayToEndTime,
      .AVPlayerItemNewErrorLogEntry
    ]
    for name in names {
      nc.removeObserver(self, name: name, object: item)
    }
  }

  // The context for player key-value observation.
  private var playerContext = 0

  /// Passing `nil` as `url` dismisses the current player and returns `nil`.
  @discardableResult private
  func makeAVPlayer(url: URL? = nil) -> AVPlayer? {
    if let prev = player?.currentItem {
      removeObservers(item: prev)
      delegate?.dismissVideo()
    }

    guard let url = url else {
      player = nil
      return nil
    }

    let asset = AVURLAsset(url: url)
    let item = makePlayerItem(asset: asset)

    let newPlayer = AVPlayer(playerItem: item)

    // Without disallowing external playback here, the system takes our player
    // as video player and delegates control to Apple TV, manifesting, for
    // example, in disabling volume controls in Control Centre.

    newPlayer.allowsExternalPlayback = false
    newPlayer.actionAtItemEnd = .none

    return newPlayer
  }

  /// Returns: `.paused`, `.preparing`, `listening` or `viewing`
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
      if player?.status == .readyToPlay,
        !(player?.currentItem?.tracks.isEmpty ?? true) {
        return seek(entry, playing: playing)
      } else {
        return state
      }
    }
    
    player = makeAVPlayer(url: proxiedURL)   
    
    return .preparing(entry, playing)
  }

  // MARK: - FSM

  /// Saves the current time position of the player. If the item is considered
  /// as played, its time is saved as `CMTime.indefinite`.
  private func setCurrentTime() {
    guard let player = self.player,
      let url = currentEntry?.enclosure?.url else {
      os_log("aborting: unexpected attempt to set time", log: log)
      return
    }

    let t = player.currentTime()
    let threshold = CMTime(seconds: 15, preferredTimescale: t.timescale)
    let leading = CMTimeCompare(t, threshold)
    
    guard leading != -1 else {
      // Not new but will resume from the beginning.
      times.set(.zero, for: url)
      return
    }

    if let duration = player.currentItem?.duration, duration != .indefinite {
      let end = CMTimeSubtract(duration, threshold)
      let trailing = CMTimeCompare(t, end)
      
      guard trailing == -1 else {
        // This one has been completed.
        times.set(.indefinite, for: url)
        return
      }
    }

    // And this has a resumabe timestamp.
    times.set(t, for: url)
  }

  private var state = PlaybackState.inactive(nil, false) {
    didSet {
      os_log("new state: %{public}@, old state: %{public}@",
             log: log, type: .info,
             state.description, oldValue.description
      )

      let needsUpdate: Bool = {
        guard state == oldValue else {
          return true
        }

        switch state {
        case .paused(_, let error), .inactive(let error, _):
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

  private func updateState(_ e: PlaybackEvent) {
    os_log("handling event: %{public}@", log: log, type: .info, e.description)

    switch state {
    case .inactive(let fault, let resuming):
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
          return state = .inactive(.session, resuming)
        }
        return state = prepare(newEntry, playing: resuming)

      case .resume:
        os_log("** resume before change event while inactive", log: log)
        return state = .inactive(fault, true)

      case .error, .end, .paused, .playing, .ready, .video,
           .toggle, .pause, .scrub:
        os_log("""
          unhandled: (
            event: %{public}@
            while: %{public}@
          )
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
        if PlaybackSession.isVideo(tracks: tracks, type: type) {
          return state = .viewing(pausedEntry, player)
        } else {
          return state = .listening(pausedEntry)
        }

      case .ready:
        return state = seek(pausedEntry, playing: false)

      case .paused, .video, .pause:
        return

      case .error(let er):
        pausePlayer()
        let itemError = self.player?.currentItem?.error ?? er
        os_log("error while paused: %{public}@", log: log, type: .error,
               itemError as CVarArg)
        return state = PlaybackState(paused: pausedEntry, error: itemError)

      case .scrub(let position):
        return state = seek(pausedEntry, playing: false, position: position)

      case .end:
        os_log("""
          unhandled: (
            event: %{public}@
            while: %{public}@
          )
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
        guard !(player?.currentItem?.tracks.isEmpty ?? true) else {
          os_log("** waiting for tracks", log: log)
          return state = .preparing(preparingEntry, preparingShouldPlay)
        }
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

        let isVideo = PlaybackSession.isVideo(tracks: tracks, type: type)

        player.allowsExternalPlayback = isVideo

        if isVideo {
          return state = .viewing(preparingEntry, player)
        } else {
          return state = .listening(preparingEntry)
        }

      case .video, .scrub:
        os_log("""
          ** ignoring: (
            event: %{public}@
            while: %{public}@
          )
          """, log: log, e.description, state.description)
        return

      case .end:
        os_log("""
          unhandled: (
            event: %{public}@
            while: %{public}@
          )
          """, log: log, type: .error, e.description, state.description)
        fatalError(String(describing: e))
      }

    case .listening(let playingEntry), .viewing(let playingEntry, _):
      // MARK: listening/viewing
      switch e {
      case .error(let er):
        pausePlayer()

        let itemError = self.player?.currentItem?.error ?? er
        
        os_log("error while listening or viewing: %{public}@",
               log: log, type: .error, itemError as CVarArg)
        
        return state = PlaybackState(paused: playingEntry, error: itemError)

      case .paused:
        assert(player?.error == nil)
        assert(player?.currentItem?.error == nil)
        setCurrentTime()
        
        return state = .paused(playingEntry, nil)
      
      case .end:
        return pausePlayer()

      case .change(let changingEntry):
        guard changingEntry != playingEntry else {
          return
        }
        
        setCurrentTime()
        
        guard let actualEntry = changingEntry else {
          return state = deactivate()
        }
        
        return state = prepare(actualEntry)

      case .toggle, .pause:
        return pausePlayer()

      case .scrub(let position):
        return state = seek(playingEntry, playing: true, position: position)

      case .ready, .playing, .resume:
        return

      case .video:
        os_log("""
          unhandled: (
            event: %{public}@
            while: %{public}@
          )
          """, log: log, type: .error, e.description, state.description)
        fatalError(String(describing: e))
      }
    }
  }

  private func event(_ e: PlaybackEvent) {
    sQueue.sync {
      // Just saving an indention in the big switch above.
      updateState(e)
    }
  }

}

// MARK: - Managing Audio Session and Remote Command Center

extension PlaybackSession {

  private func activate() throws {
    os_log("activating", log: log, type: .info)

    let s = AVAudioSession.sharedInstance()

    try s.setCategory(.playback, mode: .spokenAudio, policy: .longForm)
    try s.setActive(true)

    addRemoteCommandTargets()
  }

  private func deactivate() -> PlaybackState {
    os_log("deactivating", log: log, type: .info)
    
    do {
      try AVAudioSession.sharedInstance().setActive(false)
    } catch {
      return .inactive(.session, false)
    }
    return .inactive(nil, false)
  }

  public func reclaim() {
    os_log("reclaiming: does nothing yet", log: log)
  }

}

// MARK: - Playing

extension PlaybackSession: Playing {
  
  public func isUnplayed(uid: String) -> Bool {
    guard currentEntry?.enclosure?.url != uid else {
      return false
    }
    
    return times.isUnplayed(uid: uid)
  }

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

  /// A system queue for our non-blocking surface area. Note, how all changes
  /// are routed through the state machine, using `event(_ e: PlaybackEvent)`.
  private var incoming: DispatchQueue {
    return DispatchQueue.global(qos: .userInitiated)
  }
  
  public func setCurrentEntry(_ newValue: Entry?) {
    incoming.async {
      self.event(.change(newValue))
    }
  }

  /// Synchronously checking the playback state like this can only provide
  /// guidance, for its asynchronous nature. Paused state, for example,
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
    incoming.async {
      guard let item = self.delegate?.nextItem() else {
        return
      }

      self.event(.change(item))
      
      guard self.checkState() else {
        os_log("forward command failed", log: log, type: .error)
        return
      }
    }
    
    return true
  }

  public func backward() -> Bool {
    incoming.async {
      guard let item = self.delegate?.previousItem() else {
        return
      }
      
      self.event(.change(item))
      
      guard self.checkState() else {
        os_log("backward command failed", log: log, type: .error)
        return
      }
    }

    return true
  }

  @discardableResult
  public func resume() -> Bool {
    incoming.async {
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
    incoming.async {
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
    incoming.async {
      self.event(.toggle)
      
      guard self.checkState() else {
        os_log("toggle command failed", log: log, type: .error)
        return
      }
    }

    return true
  }

  @discardableResult
  public func scrub(_ position: TimeInterval) -> Bool {
    incoming.async {
      self.event(.scrub(position))

      guard self.checkState() else {
        os_log("toggle command failed", log: log, type: .error)
        return
      }
    }

    return true
  }

}
