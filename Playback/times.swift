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

  private lazy var store = NSUbiquitousKeyValueStore.default
  
  /// Produces a key for a unique identifier.
  private static func key(from uid: String) -> String {
    return String(djb2Hash32(string: uid))
  }
  
  public func time(uid: String) -> CMTime? {
    let k = TimeRepository.key(from: uid)

    guard
      let dict = store.dictionary(forKey: k),
      let seconds = dict["seconds"] as? Double,
      let timescale = dict["timescale"] as? CMTimeScale
    else {
      return nil
    }
    
    return CMTime(seconds: seconds, preferredTimescale: timescale)
  }

  private static func timestamp() -> Double {
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
    
    store.set(dict, forKey: TimeRepository.key(from: uid))
    
    vacuum()
  }
  
  public func removeTime(for uid: String) {
    store.removeObject(forKey: TimeRepository.key(from: uid))
  }

  /// Removes oldest 256 objects from store to create space for new ones. 
  /// Remember that the objects, of course, need to be timestamped.
  public func vacuum() {
    let m = 512
    
    let dicts = store.dictionaryRepresentation
    
    guard dicts.count > m else {
      return
    }
    
    let timestampsByKeys = dicts.reduce([String : Double]()) { acc, dict in
      let k = dict.key
      guard let v = dict.value as? Double else {
        return acc
      }
      var tmp = acc
      tmp[k] = v
      return tmp
    }
    
    // Checking the count again, because there might me objects containing no 
    // timestamps.
    
    guard timestampsByKeys.count > m else {
      return
    }

    let objects = timestampsByKeys.sorted {
      $0.value > $1.value
    }.suffix(from: m / 2)
    
    for object in objects {
      store.removeObject(forKey: object.key)
    }
  }
}


