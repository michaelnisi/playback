//
//  times.swift
//  Podest
//
//  Created by Michael on 6/2/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import AVFoundation
import os.log

/// Returns 32-bit hash of `string`.
///
/// - [djb2](http://www.cse.yorku.ca/~oz/hash.html)
/// - [Use Your Loaf](https://useyourloaf.com/blog/swift-hashable/)
///
/// - Parameter string: The string to hash.
///
/// - Returns: A 32-bit signed Integer.
private func djb2Hash32(string: String) -> Int32 {
  let unicodeScalars = string.unicodeScalars.map { $0.value }
  return Int32(unicodeScalars.reduce(5381) {
    ($0 << 5) &+ $0 &+ Int32($1)
  })
}

public final class TimeRepository: NSObject, Times {

  public static let shared = TimeRepository()

  /// The maximum number of keys in the store, before we begin to remove keys:
  /// removing the older 256 keys.
  static let threshold = 512

  /// Produces a key for a unique identifier.
  private static func key(from uid: String) -> String {
    return String(djb2Hash32(string: uid))
  }

  private lazy var store = NSUbiquitousKeyValueStore.default

  public func time(uid: String) -> CMTime? {
    os_log("get time: %@ ", log: log, type: .debug, uid)

    let k = TimeRepository.key(from: uid)

    guard
      let dict = store.dictionary(forKey: k),
      let seconds = dict["seconds"] as? Double,
      let timescale = dict["timescale"] as? CMTimeScale
    else {
      os_log("no time for: { %@, %@ }", log: log, type: .debug, uid, k)
      return nil
    }

    return CMTime(seconds: seconds, preferredTimescale: timescale)
  }

  private static func timestamp() -> TimeInterval {
    return Date().timeIntervalSince1970
  }

  public func set(_ time: CMTime, for uid: String) {
    let seconds = time.seconds as NSNumber
    let timescale = time.timescale as NSNumber
    let ts = TimeRepository.timestamp() as NSNumber

    var dict = [NSString : NSNumber]()
    dict["seconds"] = seconds
    dict["timescale"] = timescale
    dict["ts"] = ts

    let k = TimeRepository.key(from: uid)
    store.set(dict, forKey: k)

    os_log("set time: { %@: %@ }", log: log, type: .debug, uid, seconds)

    vacuum()
  }

  public func removeTime(for uid: String) {
    os_log("removing time: %@", log: log, type: .debug, uid)
    store.removeObject(forKey: TimeRepository.key(from: uid))
  }

  /// Removes oldest 256 objects from store to create space for new ones.
  /// Remember that the objects, of course, need to be timestamped.
  public func vacuum() {
    let items = store.dictionaryRepresentation

    guard items.count > TimeRepository.threshold else {
      return
    }

    let timestampsByKeys = items.reduce([String : TimeInterval]()) { acc, item in
      let k = item.key
      guard
        let v = item.value as? [NSString : NSNumber],
        let ts = v["ts"] as? TimeInterval
        else {
        return acc
      }
      var tmp = acc
      tmp[k] = ts
      return tmp
    }

    // Checking the count again, because there might have been objects without
    // timestamps, which are none of our business.

    guard timestampsByKeys.count > TimeRepository.threshold else {
      return os_log("sufficient key space", log: log, type: .debug)
    }

    os_log("removing objects from the shared iCloud key-value store", log: log)

    let objects = timestampsByKeys.sorted {
      $0.value > $1.value
    }.suffix(from: TimeRepository.threshold / 2)

    for object in objects {
      store.removeObject(forKey: object.key)
    }
  }
}
