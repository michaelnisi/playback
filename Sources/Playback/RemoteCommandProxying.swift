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

import Foundation
import MediaPlayer
import os.log

/// Indicates that remote commands have been added.
fileprivate var once = false

protocol RemoteCommandProxying {
  func addRemoteCommandTargets()
}

/// Sets up responding to remote control events sent by external accessories and 
/// system controls.
extension PlaybackSession: RemoteCommandProxying {

  // MARK: - Media Player Remote Command Handlers
  
  func status(_ ok: Bool) -> MPRemoteCommandHandlerStatus {
    ok ? .success : .commandFailed
  }
  
  func onPlay(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    status(resume())
  }
  
  func onPause(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    status(pause())
  }
  
  func onToggle(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    status(toggle())
  }
  
  func onPreviousTrack(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    status(backward())
  }
  
  func onNextTrack(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    status(forward())
  }

  func onChangePlaybackPosition(event: MPRemoteCommandEvent
  ) -> MPRemoteCommandHandlerStatus {
    guard let e = event as? MPChangePlaybackPositionCommandEvent else {
      return .commandFailed
    }

    return status(scrub(e.positionTime))
  }
  
  // MARK: - MPRemoteCommandCenter
  
  func addRemoteCommandTargets() {
    os_log("adding remote commands", log: log, type: .info)
    precondition(!once)
    
    once = true

    DispatchQueue.main.async {
      dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

      let rcc = MPRemoteCommandCenter.shared()

      rcc.pauseCommand.addTarget(handler: self.onPause)
      rcc.playCommand.addTarget(handler: self.onPlay)
      rcc.changePlaybackPositionCommand.addTarget(handler: self.onChangePlaybackPosition)
      rcc.togglePlayPauseCommand.addTarget(handler: self.onToggle)
      rcc.nextTrackCommand.addTarget(handler: self.onNextTrack)
      rcc.previousTrackCommand.addTarget(handler: self.onPreviousTrack)
    }
  }
}
