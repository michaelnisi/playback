//
//  remote.swift
//  Playback
//
//  Created by Michael on 5/28/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import MediaPlayer
import os.log

protocol RemoteCommanding {
  func addRemoteCommandTargets()
  func removeRemoteCommandTargets()
}

/// Sets up responding to remote control events sent by external accessories and 
/// system controls.
extension PlaybackSession: RemoteCommanding {

  // MARK: - Media Player Remote Command Handlers
  
  func status(_ ok: Bool) -> MPRemoteCommandHandlerStatus {
    return ok ? MPRemoteCommandHandlerStatus.success :
      MPRemoteCommandHandlerStatus.commandFailed
  }
  
  func onPlay(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    return status(resume())
  }
  
  func onPause(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    return status(pause())
  }
  
  func onToggle(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    if case .paused = state {
      return status(resume())
    } else {
      return status(pause())
    }
  }
  
  func onPreviousTrack(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    return status(backward())
  }
  
  func onNextTrack(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    return status(forward())
  }
  
  func onSeek(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    return .commandFailed
  }
  
  // MARK: - MPRemoteCommandCenter
  
  func addRemoteCommandTargets() {
    removeRemoteCommandTargets()
    
    let rcc = MPRemoteCommandCenter.shared()
    
    os_log("adding remote commands", log: log)
    
    self.remoteCommandTargets = RemoteCommandTargets(
      pause: rcc.pauseCommand.addTarget(handler: onPause),
      play: rcc.playCommand.addTarget(handler: onPlay),
      togglePlayPause: rcc.togglePlayPauseCommand.addTarget(handler: onToggle),
      nextTrack: rcc.nextTrackCommand.addTarget(handler: onNextTrack),
      previousTrack: rcc.previousTrackCommand.addTarget(handler: onPreviousTrack)
    )
  }
  
  func removeRemoteCommandTargets() {
    guard let targets = remoteCommandTargets else {
      return
    }
    
    os_log("removing remote commands", log: log)
    
    let rcc = MPRemoteCommandCenter.shared()
    rcc.pauseCommand.removeTarget(targets.pause)
    rcc.playCommand.removeTarget(targets.play)
    rcc.togglePlayPauseCommand.removeTarget(targets.togglePlayPause)
    rcc.nextTrackCommand.removeTarget(targets.nextTrack)
    rcc.previousTrackCommand.removeTarget(targets.previousTrack)
  }
}
