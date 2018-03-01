//
//  remote.swift
//  Playback
//
//  Created by Michael on 5/28/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import MediaPlayer

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
    return status(state == .paused ? resume() : pause())
  }
  
  func onPreviousTrack(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    return status((delegate?.previousTrack())!)
  }
  
  func onNextTrack(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    return status((delegate?.nextTrack())!)
  }
  
  func onSeek(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    return .commandFailed
  }
  
  // MARK: - MPRemoteCommandCenter
  
  func addRemoteCommandTargets() {
    let rcc = MPRemoteCommandCenter.shared()

    rcc.pauseCommand.addTarget(handler: onPause)
    rcc.playCommand.addTarget(handler: onPlay)
    rcc.togglePlayPauseCommand.addTarget(handler: onToggle)
    
    // TODO: Add more remote commands
    
    rcc.nextTrackCommand.addTarget(handler: onNextTrack)
    rcc.previousTrackCommand.addTarget(handler: onPreviousTrack)
    
//    rcc.seekForwardCommand.addTarget(handler: onSeek)
//    rcc.seekBackwardCommand.addTarget(handler: onSeek)
  }
  
  func removeRemoteCommandTargets() {
    let rcc = MPRemoteCommandCenter.shared()
    
    rcc.pauseCommand.removeTarget(onPause)
    rcc.playCommand.removeTarget(onPlay)
    rcc.togglePlayPauseCommand.removeTarget(onToggle)
    
//    rcc.nextTrackCommand.removeTarget(onNextTrack)
//    rcc.previousTrackCommand.removeTarget(onPreviousTrack)
    
//    rcc.seekForwardCommand.removeTarget(onSeek)
//    rcc.seekBackwardCommand.removeTarget(onSeek)
  }
}
