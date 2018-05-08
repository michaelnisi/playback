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

protocol RemoteCommandProxying {
  func addRemoteCommandTargets()
}

/// Sets up responding to remote control events sent by external accessories and 
/// system controls.
extension PlaybackSession: RemoteCommandProxying {

  // MARK: - Media Player Remote Command Handlers
  
  func status(_ ok: Bool) -> MPRemoteCommandHandlerStatus {
    os_log("last remote command status: %i", log: log, type: .debug, ok)
    return ok ? MPRemoteCommandHandlerStatus.success :
      MPRemoteCommandHandlerStatus.commandFailed
  }
  
  func onPlay(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    os_log("handling remote command: play", log: log, type: .debug)
    return status(resume())
  }
  
  func onPause(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    os_log("handling remote command: pause", log: log, type: .debug)
    return status(pause())
  }
  
  func onToggle(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    os_log("handling remote command: toggle", log: log, type: .debug)
    return status(toggle())
  }
  
  func onPreviousTrack(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    os_log("handling remote command: previous track", log: log, type: .debug)
    return status(backward())
  }
  
  func onNextTrack(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    os_log("handling remote command: next track", log: log, type: .debug)
    return status(forward())
  }
  
  func onSeek(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    return .noActionableNowPlayingItem
  }
  
  // MARK: - MPRemoteCommandCenter
  
  func addRemoteCommandTargets() {
    os_log("adding remote commands", log: log)
    
    let rcc = MPRemoteCommandCenter.shared()

    rcc.pauseCommand.addTarget(handler: onPause)
    rcc.playCommand.addTarget(handler: onPlay)
    rcc.togglePlayPauseCommand.addTarget(handler: onToggle)
    rcc.nextTrackCommand.addTarget(handler: onNextTrack)
    rcc.previousTrackCommand.addTarget(handler: onPreviousTrack)
  }
  
//  func removeRemoteCommandTargets() {
//    guard let targets = remoteCommandTargets else {
//      return
//    }
//
//    os_log("removing remote commands", log: log)
//
//    let rcc = MPRemoteCommandCenter.shared()
//    rcc.pauseCommand.removeTarget(targets.pause)
//    rcc.playCommand.removeTarget(targets.play)
//    rcc.togglePlayPauseCommand.removeTarget(targets.togglePlayPause)
//    rcc.nextTrackCommand.removeTarget(targets.nextTrack)
//    rcc.previousTrackCommand.removeTarget(targets.previousTrack)
//  }
}
