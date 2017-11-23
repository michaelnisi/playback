//
//  times.swift
//  Podest
//
//  Created by Michael on 6/2/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import AVFoundation
import FeedKit
import os.log

fileprivate let log = OSLog(subsystem: "ink.codes.playback", category: "times")

protocol Times {
  func time(uid: String) -> CMTime?
  func set(_ time: CMTime, for uid: String)
  func removeTime(for uid: String)
}

public final class TimeRepository: NSObject, Times {
  
  public static let shared = TimeRepository()
  
  /// Produces a key for a unique identifier.
  private static func key(from uid: String) -> String {
    return String(djb2Hash32(string: uid))
  }
  
  private lazy var store = NSUbiquitousKeyValueStore.default
  
  public func time(uid: String) -> CMTime? {
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
    
    os_log("set seconds: { %@: %@ }", log: log, type: .debug, k, seconds)
    
    vacuum()
  }
  
  public func removeTime(for uid: String) {
    store.removeObject(forKey: TimeRepository.key(from: uid))
  }

  /// Removes oldest 256 objects from store to create space for new ones. 
  /// Remember that the objects, of course, need to be timestamped.
  public func vacuum() {
    let m = 512
    
    let items = store.dictionaryRepresentation
    
    guard items.count > m else {
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
    // timestamps.
    
    guard timestampsByKeys.count > m else {
      return
    }
    
    os_log("vacuum ubiquitous-kv-store", log: log, type: .debug)

    let objects = timestampsByKeys.sorted {
      $0.value > $1.value
    }.suffix(from: m / 2)
    
    for object in objects {
      store.removeObject(forKey: object.key)
    }
  }
}
