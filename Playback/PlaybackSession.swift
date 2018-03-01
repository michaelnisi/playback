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

private enum PlaybackEvent {
  case end
  case error(PlaybackError)
  case paused
  case play(Entry)
  case playing
  case ready
  case video
}

/// A `PlaybackSession` plays one audio or video file at a time.
public final class PlaybackSession: NSObject, Playback {
  
  @available(iOS 10.0, *)
  static let log = OSLog(subsystem: "ink.codes.playback", category: "play")
  
  private let proxy: FileProxying
  
  public init(proxy: FileProxying) {
    self.proxy = proxy
  }
  
  public var delegate: PlaybackDelegate?
  
  fileprivate var entry: Entry? {
    didSet {
      guard
        oldValue != entry,
        let player = self.player,
        let tid = oldValue?.enclosure?.url else {
          return
      }
      TimeRepository.shared.set(player.currentTime(), for: tid)
    }
  }
  
  /// The suggested time to start playback from.
  fileprivate var suggestedTime: CMTime?
  
  /// The current player.
  fileprivate var player: AVPlayer?
  
  /// The URL of the currently playing asset.
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
  
  // TODO: Review start time selection
  
  private func startTime() -> CMTime? {
    guard
      let seekableTimeRanges = player?.currentItem?.seekableTimeRanges,
      let t = self.suggestedTime else {
        return nil
    }
    
    guard let st = seekableTime(t, within: seekableTimeRanges) else {
      let r = seekableTimeRanges.first as! CMTimeRange
      return r.start
    }
    
    return st
  }
  
  /// Resumes playback of the current item.
  public func seekAndPlay() -> PlaybackState {
    defer {
      self.suggestedTime = nil
    }
    
    guard
      let player = self.player,
      let entry = self.entry,
      let enclosure = entry.enclosure,
      let tracks = player.currentItem?.tracks else {
        fatalError("requirements to seek and play not met")
    }
    
    guard player.rate != 1 else {
      return state
    }
    
    let newState: PlaybackState = isVideo(tracks: tracks, type: enclosure.type)
      ? .viewing(entry, player)
      : .listening(entry)
    
    guard let time = startTime() else {
      player.play()
      NowPlaying.set(entry: entry, player: player)
      return newState
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
    
    return newState
  }
  
  private func isVideo(tracks: [AVPlayerItemTrack], type: EnclosureType) -> Bool {
    assert(!tracks.isEmpty, "tracks not loaded")
    
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
    
    guard let enclosure = entry?.enclosure,
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
    guard change?[.newKey] as? CMTime != change?[.oldKey] as? CMTime else {
      if #available(iOS 10.0, *) {
        os_log(
          "observed redundant duration change",
          log: PlaybackSession.log,
          type: .error
        )
      }
      return
    }
    NowPlaying.set(entry: entry!, player: player!)
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
  
  /// Resume playback of `entry` at `time`. Passing an invalid time, however,
  /// causes the item to start from the beginning.
  ///
  /// - Parameters:
  ///   - entry: The entry whose enclosed audio media is played.
  ///   - time: Seek to `time` before resuming playback.
  ///
  /// - Returns: The new playback state: `.viewing`, `.listening`, or `.preparing`.
  private func resume(_ entry: Entry, at time: CMTime) -> PlaybackState {
    self.entry = entry
    self.suggestedTime = time
    
    guard let urlString = entry.enclosure?.url,
      let url = URL(string: urlString) else {
        fatalError("URL required")
    }
    
    let opts = DownloadTaskConfiguration(
      countOfBytesClientExpectsToSend: nil,
      countOfBytesClientExpectsToReceive: nil,
      earliestBeginDate: Date().addingTimeInterval(60)
    )
    // To not overlap with streaming, we delay downloading.
    let proxiedURL = try! proxy.url(for: url, with: opts)
    
    guard currentURL != proxiedURL else {
      return seekAndPlay()
    }
    
    player = freshPlayer(with: proxiedURL)
    
    return .preparing(entry)
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
    if let t = TimeRepository.shared.time(uid: uid) {
      return CMTimeSubtract(t, CMTime(seconds: 5, preferredTimescale: t.timescale))
    }
    return CMTime()
  }
  
  // MARK: - FSM
  
  public private(set) var state = PlaybackState.paused {
    didSet {
      guard state != oldValue else {
        return
      }
      delegate?.playback(session: self, didChange: state)
    }
  }
  
  // TODO: Review playback error handling
  
  fileprivate func event(_ e: PlaybackEvent) -> PlaybackState {
    
    let oldState = state
    var newState: PlaybackState?
    
    // Always set newState, instead of returning the new state directly, from
    // within the switch statement cases, to ensure consistent logging, which
    // is a lifesaver while debugging this FSM.
    
    defer {
      if #available(iOS 10.0, *) {
        os_log("%{public}@, after: %{public}@, while %{public}@",
               log: PlaybackSession.log, type: .debug,
               String(describing: newState!),
               String(describing: e),
               String(describing: oldState))
      }
    }
    
    switch state {
      
    case .paused:
      
      switch e {
      case .play(let entry):
        guard let enclosureURL = entry.enclosure?.url,
          let url = URL(string: enclosureURL) else {
            fatalError("unexpected internal state")
        }
        
        newState = resume(entry, at: time(for: url.absoluteString))
        
      case .playing:
        
        // Assuming only the video player can trigger this.
        
        newState = .viewing(entry!, player!)
        
      case .ready, .paused:
        newState = state
        
      default:
        break
      }
      
    case .preparing(let entry):
      
      switch e {
      case .error(let er):
        delegate?.playback(session: self, error: er)
        newState = .paused
        
      case .play(let entry):
        guard
          let enclosureURL = entry.enclosure?.url,
          let url = URL(string: enclosureURL) else {
            fatalError("no enclosure")
        }
        newState = resume(entry, at: time(for: url.absoluteString))
        
      case .paused:
        newState = .paused
        
      case .ready:
        newState = seekAndPlay()
        
      case .video:
        newState = .viewing(entry, player!)
        
      default:
        break
      }
      
    case .listening(let entry), .viewing(let entry, _):
      
      guard let player = self.player else {
        fatalError("player expected")
      }
      
      guard let tid = entry.enclosure?.url else {
        fatalError("cannot identify time")
      }
      
      switch e {
      case .error(let er):
        delegate?.playback(session: self, error: er)
        newState = state
        
      case .paused:
        NowPlaying.set(entry: entry, player: player)
        TimeRepository.shared.set(player.currentTime(), for: tid)
        newState = .paused
        
      case .play(let entry):
        guard let enclosureURL = entry.enclosure?.url,
          let url = URL(string: enclosureURL) else {
            fatalError("no enclosure")
        }
        guard url != currentURL else {
          print("** already playing")
          newState = state
          break
        }
        newState = resume(entry, at: time(for: url.absoluteString))
        
      case .end:
        
        // Not releasing the item just yet, but keeping it around, user might
        // decide to replay.
        
        NowPlaying.set(entry: entry, player: player)
        TimeRepository.shared.removeTime(for: tid)
        newState = .paused
        
      case .ready, .playing:
        newState = state
        
      default:
        break
      }
      
    }
    
    if let s = newState {
      return s
    }
    
    // Obviously, if we reach this, we didn‘t handle the event and thus crash.
    
    if #available(iOS 10.0, *) {
      os_log("unhandled event: %{public}@ for state: %{public}@",
             log: PlaybackSession.log, type: .error,
             String(describing: e),
             String(describing: oldState))
    }
    
    fatalError()
  }
  
}

// MARK: - Playing

extension PlaybackSession: Playing {

  public var currentEntry: Entry? {
    switch state {
    case .preparing(let current), .listening(let current):
      return current
    default:
      return nil
    }
  }
  
  @discardableResult public func resume(
    entry: Entry? = nil,
    from position: ResumePosition = .previous
  ) -> Bool {
    guard let e = entry ?? self.entry else {
      return false
    }
    state = event(.play(e))
    return true
  }
  
  @discardableResult public func resume(entry: Entry) -> Bool {
    return resume(entry: entry)
  }
  
  @discardableResult public func resume() -> Bool {
    return resume(entry: nil)
  }
  
  /// Pauses the player.
  ///
  /// - Returns: `true` if it made sense.
  @discardableResult public func pause() -> Bool {
    guard entry != nil else {
      return false
    }
    player?.pause()
    return true
  }
  
}

// MARK: - Intermediating

extension PlaybackSession: Intermediating {
  
  public func activate() throws {
    let audio = AVAudioSession.sharedInstance()
    
    try audio.setCategory(AVAudioSessionCategoryPlayback)
    try audio.setActive(true)
    
    // Find remote managing code in './remote.swift'.
    addRemoteCommandTargets()
  }
  
  public func deactivate() throws {
    try AVAudioSession.sharedInstance().setActive(false)
    
    removeRemoteCommandTargets()
  }
  
}
