//
//  times.swift
//  Playback
//
//  Created by Michael on 6/2/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import AVFoundation
import os.log

public final class TimeRepository: NSObject {
  
  struct Key: Hashable {
    let uid: String
    
    /// A super wack hash of the `uid`.
    var hash: Int32 {
      let unicodeScalars = uid.unicodeScalars.map { $0.value }
      
      return Int32(unicodeScalars.reduce(5381) {
        ($0 << 5) &+ $0 &+ Int32($1)
      })
    }
  }
  
  public static let shared = TimeRepository()

  private lazy var store = NSUbiquitousKeyValueStore.default

  /// The maximum number of keys in the store, before we begin removing the 
  /// older 256 keys.
  static let threshold = 512
  
  /// In-memory cache for making this faster.
  private var unplayedByUIDs = Set<Int32>()
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
        let ts = v["ts"] as? TimeInterval else {
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

  /// Returns the timestamp matching `uid`, our intermediate format.
  func timestamp(key: Key) -> Timestamp? {
    guard let dict = store.dictionary(forKey: String(key.hash)) else {
      unplayedByUIDs.insert(key.hash)
      return nil
    }
    
    unplayedByUIDs.remove(key.hash)
    
    return Timestamp(dict: dict)
  }

  public func time(uid: String) -> CMTime {
    guard let ts = timestamp(key: Key(uid: uid)) else {
      return CMTime()
    }
    
    return CMTime(seconds: ts.seconds, preferredTimescale: ts.timescale)
  }
  
  public func set(_ time: CMTime, for uid: String) {    
    guard let ts = Timestamp(time: time) else {
      os_log("removing invalid time: %{public}@", log: log, uid)
      
      return removeTime(for: uid)
    }
    
    let key = Key(uid: uid)
    
    store.set(ts.dictionary, forKey: String(key.hash))
    vacuum()
  }

  public func removeTime(for uid: String) {
    let key = Key(uid: uid)
  
    store.removeObject(forKey: String(key.hash))
  }

  public func isUnplayed(uid: String) -> Bool {
    let key = Key(uid: uid)
    
    guard !unplayedByUIDs.contains(key.hash) else {
      return true
    }

    return timestamp(key: key) == nil
  }
}
