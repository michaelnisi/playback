# Playback FSM

Audiovisual playback is asynchronous, a combination of IO and user events. Playback synchronizes these events and handles them serially implementing a finite-state machine with five states.

- inactive
- paused
- preparing
- listening
- viewing

Here are the states and their transitions in detail. Unhandled events trap.

## inactive

A Playback session starts **inactive** with an unconfigured, inactive `AVAudioSession`, waiting for `.change(Entry?)` to start, trapping all all other events, except `.resume`, which turns on `Resuming`, so the next `.change(Entry?)` will start playing.

Being **inactive** may be unintended, so this state optionally stores an error, the cause of inactivity.

### Events

```swift
.change(let entry)
```

The `.change(Entry?)` event with an entry activates the session and transits to the **paused** state, while `.change` without entry deactivates the session remaining in **inactive** state.

## paused

In **paused** we have an item and finished a setup cycle, leaving us either ready to play or with an error.

### Events

```swift
.change(Entry?)
```

In **paused** state the current entry can be changed or set to `nil` deactivating the session—leaving us in **paused** or transfering to **inactive**.

```swift
.toggle | .resume
```

Plays the current item, eventually, after transfering to **preparing**, which will trigger `ready` or `error` events.

```swift
.playing
```

Tansfers to `.listening(Entry)` or `viewing(Entry, AVPlayer`). If our internal player is not in the required state, this will trap.

```swift
.ready
```

After `ready` in **paused** state, we seek the player to the previous play time of this item and pause, leaving us in **paused**, but seeked to the correct position, ready to play.

```swift
.error(PlaybackError)
```

If an `error` occures during **paused**, it will be added to the **paused** state, in which we remain.

### Ignored Events

While in **paused**, `.paused`, `.video`, and `.pause` events are ignored.

## preparing

To be continued…

## listening/viewing

To be continued…
