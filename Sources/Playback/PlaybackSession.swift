//===----------------------------------------------------------------------===//
//
// This source file is part of the Playback open source project
//
// Copyright (c) 2021 Michael Nisi and collaborators
// Licensed under MIT License
//
// See https://github.com/michaelnisi/playback/blob/main/LICENSE for license information
//
//===----------------------------------------------------------------------===//

import AVFoundation
import AVKit
import Foundation
import os.log

let log = OSLog(subsystem: "ink.codes.playback", category: "Playback")

struct RemoteCommandTargets {
  let pause: Any?
  let play: Any?
  let togglePlayPause: Any?
  let nextTrack: Any?
  let previousTrack: Any?
}

/// Implements `Playback` as FSM using worker and a serial queue.
public final class PlaybackSession<Item: Playable>: NSObject {
  
  /// This closure should return a local or remote URL for `url`. One might return `nil` to signal that the URL is not reachable,
  /// implying that the returned URL must be reachable on the current network, otherwise return `nil`.
  public var makeURL: ((URL) -> URL?)?
  
  /// Should return the next item.
  public var nextItem: (() -> Item?)?
  
  /// Should return the previous item.
  public var previousItem: (() -> Item?)?
  
  /// The audio playback volume for the player.
  public var volume: Float {
    set { player?.volume = newValue }
    get { player?.volume ?? 0 }
  }

  private let times: Times
  
  /// Internal serial queue, our inbox for events.
  private let sQueue = DispatchQueue(
    label: "ink.codes.playback.PlaybackSession",
    target: .global(qos: .userInitiated)
  )

  /// Makes a new playback session.
  ///
  /// - Parameter times: A repository for storing times (per URL).
  public init(times: Times) {
    self.times = times
  }
  
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
      if v.timeRangeValue.containsTime(time) {
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

  private func startTime(
    item: AVPlayerItem?, url: String, position: TimeInterval? = nil
  ) -> CMTime? {
    guard let seekableTimeRanges = item?.seekableTimeRanges else {
      return nil
    }

    let t = position == nil ?
      startTime(matching: url) :
      CMTime(seconds: position!, preferredTimescale: 1000000)

    guard let st = PlaybackSession.seekableTime(t, within: seekableTimeRanges) else {
      guard let r = seekableTimeRanges.first?.timeRangeValue else {
        return nil
      }
      return r.start
    }

    return st
  }
    
  private var assetState: AssetState? {
    currentPlaybackItem?.nowPlaying
  }
  
  /// Sets the playback time to previous for `item`.
  public func seek(
    _ item: Item, playing: Bool, position: TimeInterval? = nil
  ) -> PlaybackState<Item>? {
    guard
      let player = self.player,
      let tracks = player.currentItem?.tracks, !tracks.isEmpty else {
      fatalError("requirements to seek and play not met")
    }
    
    let playbackItem = item.makePlaybackItem()

    let newState: PlaybackState<Item> = {
      guard playing else {
        return .paused(item, assetState, nil)
      }
    
      return PlaybackSession.isVideo(tracks: tracks, type: playbackItem.proclaimedMediaType)
        ? .viewing(item, player)
        : .listening(item, assetState!)
    }()
    
    guard let time = startTime(
      item: player.currentItem, url: playbackItem.url, position: position) else {
      if playing { player.play() }
        
      return newState
    }
    
    player.seek(to: time) { [weak self] finished in
      guard finished else {
        return
      }

      // Saving successfully seeked time positions.
      if position != nil {
        self?.setCurrentTime()
      }

      DispatchQueue.main.async {
        playing ? player.play() : player.pause()
        
        guard let currentPlaybackItem = self?.currentPlaybackItem else {
          return
        }
        
        NowPlaying.set(currentPlaybackItem)
      }
    }
    
    return nil
  }

  private static
  func isVideo(tracks: [AVPlayerItemTrack], type: PlaybackItem.MediaType) -> Bool {
    tracks.contains {
      $0.assetTrack?.mediaType == .video
    } && type.isVideo
  }

  // The context for player item key-value observation.
  private var playerItemContext = UUID()

  private func onTracksChange(_ change: [NSKeyValueChangeKey : Any]?) {
    guard let tracks = change?[.newKey] as? [AVPlayerItemTrack] else {
      fatalError("no tracks to play")
    }
    
    let playbackItem = currentItem?.makePlaybackItem()

    guard let type = playbackItem?.proclaimedMediaType,
      PlaybackSession.isVideo(tracks: tracks, type: type) else {
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

  private func onDurationChange(_ change: [NSKeyValueChangeKey : Any]?) {
    // Although the UIKit documentation states that duration would be available
    // when status is readyToPlay, the duration property needs to be monitored
    // separately to aquire a valid value.
    //
    // Another concern, for some reason, it is called multiple times, hence the
    // guard.
    
    guard change?[.newKey] as? CMTime != change?[.oldKey] as? CMTime else {
      return os_log("observed redundant duration change", log: log)
    }

    guard let currentPlaybackItem = currentPlaybackItem else {
      return os_log("unexpected duration change: no item or player", log: log, type: .error)
    }
    
    NowPlaying.set(currentPlaybackItem)
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
    let playerItem = AVPlayerItem(asset: asset)

    let keyPaths = [
      #keyPath(AVPlayerItem.status),
      #keyPath(AVPlayerItem.tracks),
      #keyPath(AVPlayerItem.duration)
    ]

    for keyPath in keyPaths {
      playerItem.addObserver(
        self,
        forKeyPath: keyPath,
        options: [.old, .new],
        context: &playerItemContext
      )
    }
    
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onItemDidPlayToEndTime),
      name: .AVPlayerItemDidPlayToEndTime,
      object: playerItem
    )
    
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onItemNewErrorLogEntry),
      name: .AVPlayerItemNewErrorLogEntry,
      object: playerItem
    )

    return playerItem
  }

  private func removeObservers(_ playerItem: AVPlayerItem) {
    let keyPaths = [
      #keyPath(AVPlayerItem.status),
      #keyPath(AVPlayerItem.tracks),
      #keyPath(AVPlayerItem.duration)
    ]
    
    for keyPath in keyPaths {
      playerItem.removeObserver(self, forKeyPath: keyPath, context: &playerItemContext)
    }

    let names: [NSNotification.Name] = [
      .AVPlayerItemDidPlayToEndTime,
      .AVPlayerItemNewErrorLogEntry
    ]
    
    for name in names {
      NotificationCenter.default.removeObserver(self, name: name, object: playerItem)
    }
  }

  // The context for player key-value observation.
  private var playerContext = UUID()

  /// Passing `nil` as `url` dismisses the current player and returns `nil`.
  @discardableResult private
  func makeAVPlayer(url: URL? = nil) -> AVPlayer? {
    if let previousPlayerItem = player?.currentItem {
      removeObservers(previousPlayerItem)
      previousPlayerItem.cancelPendingSeeks()
    }

    guard let url = url else {
      player = nil
      return nil
    }

    let asset = AVURLAsset(url: url)
    let playerItem = makePlayerItem(asset: asset)

    let newPlayer = AVPlayer(playerItem: playerItem)

    // Without disallowing external playback here, the system takes our player
    // as video player and delegates control to Apple TV, manifesting, for
    // example, in disabling volume controls in Control Centre.

    newPlayer.allowsExternalPlayback = false
    newPlayer.actionAtItemEnd = .none

    return newPlayer
  }

  /// Returns: `.paused`, `.preparing`, `listening` or `viewing`
  private func prepare(_ item: Item, playing: Bool = true) -> PlaybackState<Item> {
    guard let url = URL(string: item.makePlaybackItem().url) else {
      os_log(.info, log: log, "invalid enclosure: %{public}@", String(describing: item))
      pausePlayer()
      
      return .paused(item, nil, .failed)
    }
    
    guard let proxiedURL = makeURL?(url) else {
      os_log(.info, log: log, "could not prepare: unreachable: %@", url.absoluteString)
      pausePlayer()
      
      return .paused(item, assetState, .unreachable)
    }
    
    guard assetURL != proxiedURL else {
      if player?.status == .readyToPlay, !(player?.currentItem?.tracks.isEmpty ?? true) {
        return seek(item, playing: playing) ?? state
      } else {
        return state
      }
    }
    
    player = makeAVPlayer(url: proxiedURL)
    
    return .preparing(item, playing)
  }

  // MARK: - FSM
  
  /// Saves the current time position of the player. If the item is considered
  /// as completed, its time is saved as `CMTime.indefinite`.
  private func setCurrentTime() {
    guard let player = self.player,
          let url = currentItem?.makePlaybackItem().url else {
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

  @Published public private(set) var state = PlaybackState<Item>.inactive(nil) {
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
        case .paused(_, assetState, let error), .inactive(let error):
          return error != nil
        default:
          return false
        }
      }()

      guard needsUpdate else {
        return
      }

      switch state {
      case .paused, .preparing:
        guard let currentPlaybackItem = currentPlaybackItem else {
          return
        }
        NowPlaying.set(currentPlaybackItem)
      case .inactive, .listening, .viewing:
        break
      }
    }
  }
  
  /// Submits a block pausing our player on the main queue.
  private func pausePlayer() {
    DispatchQueue.main.async { [weak self] in
      self?.player?.pause()
    }
  }

  private func updateState(_ e: PlaybackEvent<Item>) {
    os_log("handling event: %{public}@", log: log, type: .info, e.description)

    switch state {
    case .inactive(let fault):
      // MARK: inactive
      guard fault == nil else {
        os_log("unresolved error while inactive: %{public}@",
               log: log, type: .error, fault! as CVarArg)
        fatalError(String(describing: fault))
      }

      switch e {
      case .change(let item, let playing):
        guard let newItem = item else {
          return state = deactivate()
        }
        do {
          try activate()
        } catch {
          return state = .inactive(.session)
        }
        return state = prepare(newItem, playing: playing)

      case .resume:
        os_log("resume before change event while inactive", log: log)
        return state = .inactive(fault)

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

    case let .paused(pausedItem, assetState, pausedError):
      // MARK: paused
      switch e {
      case .change(let item, let playing):
        guard let newItem = item else {
          return state = deactivate()
        }
        
        if let er = pausedError, state.item == item {
          os_log("retrying: %{public}@", 
                 log: log, type: .error, String(describing: er))
        }
        
        return state = prepare(newItem, playing: playing)

      case .toggle, .resume:
        return state = prepare(pausedItem, playing: true)

      case .playing:
        guard
          let player = self.player,
          let tracks = player.currentItem?.tracks else {
          fatalError("impossible")
        }
        if PlaybackSession.isVideo(tracks: tracks, type: pausedItem.makePlaybackItem().proclaimedMediaType) {
          return state = .viewing(pausedItem, player)
        } else {
          return state = .listening(pausedItem, currentPlaybackItem!.nowPlaying!)
        }

      case .ready:
        guard let state = seek(pausedItem, playing: false) else {
          return
        }
        
        return self.state = state
        
      case .paused:
        return self.state = .paused(pausedItem, self.assetState, pausedError)

      case .video, .pause:
        return

      case .error(let er):
        pausePlayer()
        let itemError = self.player?.currentItem?.error ?? er
        os_log("error while paused: %{public}@", log: log, type: .error,
               itemError as CVarArg)
        return state = PlaybackState(paused: pausedItem, assetState: assetState, error: itemError)

      case .scrub(let position):
        guard let state = seek(pausedItem, playing: false, position: position) else {
          return
        }
        
        return self.state = state

      case .end:
        os_log("""
          unhandled: (
            event: %{public}@
            while: %{public}@
          )
          """, log: log, type: .error, e.description, state.description)
        fatalError(String(describing: e))
      }

    case .preparing(let preparingItem, let preparingShouldPlay):
      // MARK: preparing
      switch e {
      case .error(let er):
        pausePlayer()
        let itemError = self.player?.currentItem?.error ?? er
        os_log("error while preparing: %{public}@", log: log, type: .error,
               itemError as CVarArg)
        return state = PlaybackState(paused: preparingItem, assetState: assetState, error: itemError)

      case .resume:
        return state = .preparing(preparingItem, true)

      case .pause:
        return pausePlayer()

      case .toggle:
        return state = .preparing(preparingItem, !preparingShouldPlay)

      case .paused:
        return state = .paused(preparingItem, assetState, nil)

      case .ready:
        guard !(player?.currentItem?.tracks.isEmpty ?? true) else {
          os_log("waiting for tracks", log: log)
          return state = .preparing(preparingItem, preparingShouldPlay)
        }
        
        guard let state = seek(preparingItem, playing: preparingShouldPlay) else {
          return
        }
        
        return self.state = state

      case .change(let item, let playing):
        guard item != preparingItem else {
          return
        }
        guard let newItem = item else {
          return state = deactivate()
        }
        return state = prepare(newItem, playing: playing)

      case .playing:
        guard
          let player = self.player,
          let tracks = player.currentItem?.tracks else {
          fatalError("impossible")
        }

        let isVideo = PlaybackSession.isVideo(tracks: tracks, type: preparingItem.makePlaybackItem().proclaimedMediaType)

        player.allowsExternalPlayback = isVideo

        if isVideo {
          return state = .viewing(preparingItem, player)
        } else {
          return state = .listening(preparingItem, currentPlaybackItem!.nowPlaying!)
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

    case .listening(let playingItem, _), .viewing(let playingItem, _):
      // MARK: listening/viewing
      switch e {
      case .error(let er):
        pausePlayer()

        let itemError = self.player?.currentItem?.error ?? er
        
        os_log("error while listening or viewing: %{public}@",
               log: log, type: .error, itemError as CVarArg)
        
        return state = PlaybackState(paused: playingItem, assetState: assetState, error: itemError)

      case .paused:
        assert(player?.error == nil)
        assert(player?.currentItem?.error == nil)
        setCurrentTime()
        
        return state = .paused(playingItem, assetState?.paused, nil)
      
      case .end:
        return pausePlayer()

      case .change(let changingItem, let playing):
        guard changingItem != playingItem else {
          return
        }
        
        setCurrentTime()
        
        guard let actualItem = changingItem else {
          return state = deactivate()
        }
        
        return state = prepare(actualItem, playing: playing)

      case .toggle, .pause:
        return pausePlayer()

      case .scrub(let position):
        guard let state = seek(playingItem, playing: true, position: position) else {
          return
        }
        
        return self.state = state
        
      case .playing:
        return self.state = .listening(playingItem, self.assetState!)

      case .ready, .resume:
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

  private func event(_ e: PlaybackEvent<Item>) {
    sQueue.sync {
      updateState(e)
    }
  }
}

// MARK: - Managing Audio Session and Remote Command Center

extension PlaybackSession {

  private func activate() throws {
    os_log("activating", log: log, type: .info)

    let s = AVAudioSession.sharedInstance()

    try s.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
    try s.setActive(true)

    addRemoteCommandTargets()
  }

  private func deactivate() -> PlaybackState<Item> {
    os_log("deactivating", log: log, type: .info)
    
    do {
      try AVAudioSession.sharedInstance().setActive(false)
    } catch {
      return .inactive(.session)
    }
    return .inactive(nil)
  }

  public func reclaim() {
    os_log("reclaiming: does nothing yet", log: log)
  }

}

// MARK: - Playing

extension PlaybackSession {
  
  public func isPlaying(guid: PlaybackItem.ID) -> Bool {
    switch state {
    case .listening(let item, _),
         .viewing(let item, _):
      return item.makePlaybackItem().id == guid
    case .inactive, .paused, .preparing:
      return false
    }
  }
  
  public func isUnplayed(uid: String) -> Bool {
    guard currentItem?.makePlaybackItem().url != uid else {
      return false
    }
    
    return times.isUnplayed(uid: uid)
  }

  public var currentItem: Item? {
    state.item
  }
  
  public var currentPlaybackItem: PlaybackItem? {
    guard let playbackItem = currentItem?.makePlaybackItem() else {
      return nil
    }
    
    return PlaybackItem(
      id: playbackItem.id,
      url: playbackItem.url,
      title: playbackItem.title,
      subtitle: playbackItem.subtitle,
      imageURLs: playbackItem.imageURLs,
      proclaimedMediaType: playbackItem.proclaimedMediaType,
      nowPlaying: makeAssetState()
    )
  }
  
  private func makeAssetState() -> AssetState? {
    guard let player = player,
          let playerItem = player.currentItem,
          let assetURL = assetURL else {
      return nil
    }
    
    let rate = player.rate
    let duration = playerItem.duration.seconds
    let time = min(playerItem.currentTime().seconds, duration)
    
    return AssetState(url: assetURL, rate: rate, duration: duration, time: time)
  }

  /// A system queue for our non-blocking surface area. Note, how all changes
  /// are routed through the state machine, using `event(_ e: PlaybackEvent)`.
  private var incoming: DispatchQueue {
    return DispatchQueue.global(qos: .userInitiated)
  }
}

// MARK: - Incoming

public extension PlaybackSession {
  @discardableResult
  func forward() -> Bool {
    incoming.async { [unowned self] in
      guard let item = nextItem?() else {
        return
      }

      event(.change(item, state.shouldResume))
      
      guard state.isOK else {
        os_log("forward command failed", log: log, type: .error)
        return
      }
    }
    
    return true
  }

  @discardableResult
  func backward() -> Bool {
    incoming.async { [unowned self] in
      guard let item = previousItem?() else {
        return
      }
      
      event(.change(item, state.shouldResume))
      
      guard state.isOK else {
        os_log("backward command failed", log: log, type: .error)
        return
      }
    }

    return true
  }

  @discardableResult
  func resume(_ item: Item? = nil, from time: Double? = nil) -> Bool {
    incoming.async { [unowned self] in
      if let item = item {
        event(.change(item, true))
      } else {
        event(.resume)
      }

      guard state.isOK else {
        os_log("resume command failed", log: log, type: .error)
        return
      }
    }
    
    return true
  }

  @discardableResult
  func pause(_ item: Item? = nil, at time: Double? = nil) -> Bool {
    incoming.async { [unowned self] in
      if let item = item {
        event(.change(item, false))
      } else {
        event(.pause)
      }
      
      guard state.isOK else {
        os_log("pause command failed", log: log, type: .error)
        return
      }
    }

    return true
  }

  @discardableResult
  func toggle() -> Bool {
    incoming.async { [unowned self] in
      event(.toggle)
      
      guard state.isOK else {
        os_log("toggle command failed", log: log, type: .error)
        return
      }
    }

    return true
  }

  @discardableResult
  func scrub(_ position: TimeInterval) -> Bool {
    incoming.async { [unowned self] in
      event(.scrub(position))

      guard state.isOK else {
        os_log("toggle command failed", log: log, type: .error)
        return
      }
    }

    return true
  }
}
