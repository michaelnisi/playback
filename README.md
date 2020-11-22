# Playback

The Playback Swift package for iOS is the audiovisual counterpart of [FeedKit](https://github.com/michaelnisi/feedkit) for playing audio and video. It manages a playback session, plays audio and video, integrates with remote command center, and persists playback times using [NSUbiquitousKeyValueStore](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore).

Playback is used in the [Podest](https://github.com/michaelnisi/podest) podcast app.

## Symbols

Two protocols form the core surface of Playback.

```swift
protocol Playback
```

A `Playback` implementation is provided by the framework. It lets you play, pause, and resume `FeedKit.Entry` objects.

```swift
protocol PlaybackDelegate
```

The `PlaybackDelegate`, implemented by users, is queried by `Playback` for user feedback.

## FSM

Audiovisual playback is asynchronous, a combination of IO and user events. Internally, Playback synchronizes these events and serially handles them, implementing a finite-state machine with five states.

- inactive
- paused
- preparing
- listening
- viewing

## Install

📦 Add `https://github.com/michaelnisi/playback`  to your package manifest.

## License

[MIT License](https://github.com/michaelnisi/playback/blob/master/LICENSE)
