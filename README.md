# Playback

The Playback Swift package for iOS plays audio and video. It manages a playback session, plays audio and video, integrates with [Remote Command Center](https://developer.apple.com/documentation/mediaplayer/remote_command_center_events), and persists playback times using [NSUbiquitousKeyValueStore](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore).

Playback is used in the [Podest](https://github.com/michaelnisi/podest) podcast app.

## FSM

Audiovisual playback is asynchronous, a combination of IO and user events. Internally, Playback synchronizes these events and serially handles them, implementing a finite-state machine with five states.

- inactive
- paused
- preparing
- listening
- viewing

## Install

📦 Add `https://github.com/michaelnisi/playback` to your package manifest.

## License

[MIT License](https://github.com/michaelnisi/playback/blob/master/LICENSE)
