# Playback

The Playback framework plays audio and video on iOS. It manages a playback session, plays audio and video, integrates with remote command center, and persists playback times using [NSUbiquitousKeyValueStore](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore).

Playback is used in the [Podest](https://github.com/michaelnisi/podest) podcast app.

## Dependencies

- [feedkit](https://github.com/michaelnisi/feedkit), Get feeds and entries
- [ola](https://github.com/michaelnisi/ola), Check reachability

## Symbols

```swift
enum PlaybackError
```

```swift
protocol PlaybackDelegate
```

```swift
protocol Playing
```

```swift
protocol Playback
```

At the core of Playback sits a [finite-state machine](./fsm.md).

## Installation

Integrate Playback into your Xcode workspace.

## License

[MIT License](https://github.com/michaelnisi/playback/blob/master/LICENSE)
