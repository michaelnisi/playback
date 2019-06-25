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

public final class TimeRepository: NSObject {

  public static let shared = TimeRepository()
  
  private lazy var store = NSUbiquitousKeyValueStore.default

  /// The maximum number of keys in the store, before we begin to remove keys:
  /// removing the older 256 keys.
  static let threshold = 512

  /// Produces a key for a unique identifier.
  private static func makeKey(uid: String) -> String {
    return String(djb2Hash32(string: uid))
  }
}

// MARK: - Stable Size

extension TimeRepository {
  
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
      return
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

// MARK: - Times

extension TimeRepository: Times {
  
  func timestamp(uid: String) -> Timestamp? {
    let k = TimeRepository.makeKey(uid: uid)
    
    guard let dict = store.dictionary(forKey: k) else { 
      return nil
    }

    return Timestamp(dict: dict)
  }
    
  public func time(uid: String) -> CMTime {
    guard let ts = timestamp(uid: uid) else {
      return CMTime()
    }
    
    return CMTime(seconds: ts.seconds, preferredTimescale: ts.timescale)
  }
  
  public func set(_ time: CMTime, for uid: String) {
    guard let d = Timestamp(time: time)?.dictionary else {
      os_log("removing invalid time: %{public}@", log: log, uid)
      return removeTime(for: uid)
    }
    
    let k = TimeRepository.makeKey(uid: uid)
    
    store.set(d, forKey: k)
    vacuum()
  }
  
  public func removeTime(for uid: String) {
    store.removeObject(forKey: TimeRepository.makeKey(uid: uid))
  }
  
  public func isUnplayed(uid: String) -> Bool {
    return timestamp(uid: uid)?.tag == .normal
  }
}
