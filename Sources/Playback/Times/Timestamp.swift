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
import AVFoundation

/// The timely playback status of an AV item.
public struct Timestamp: Hashable, Codable {
  
  /// Contextual information of a timestamp.
  public enum Tag: Int, Codable {
    
    /// A reasonable timestamp for resuming playback (including zero).
    case normal
    
    /// The according item has been played to its end.
    case finished
  }
  
  let seconds: Double
  let timescale: CMTimeScale
  let ts: TimeInterval
  let tag: Tag
  
  public init?(
    seconds: Double, 
    timescale: CMTimeScale, 
    ts: TimeInterval,
    tag: Tag = .normal
  ) {
    self.seconds = seconds
    self.timescale = timescale
    self.ts = ts
    self.tag = tag
  }
}

extension Timestamp: CustomStringConvertible {
  
  public var description: String {
    switch tag {
    case .normal:
      return "Timestamp: ( normal, \(seconds) )"
    case .finished:
      return "Timestamp: ( finished )"
    }
  }
}

// MARK: - Encoding and Decoding

extension Timestamp {
  
  init?(dict: [String : Any]) {
    guard let seconds = dict["seconds"] as? Double,
      let timescale = dict["timescale"] as? CMTimeScale,
      let ts = dict["ts"] as? TimeInterval else {
      return nil
    }
    
    let rawTag = dict["tag"] as? Int ?? 0
    
    let tag: Tag = {
      return Tag(rawValue: rawTag) ?? .normal
    }()
    
    self.seconds = seconds
    self.timescale = timescale
    self.ts = ts
    self.tag = tag
  }
  
  init?(time: CMTime) {
    guard time.isValid || time.isIndefinite, 
      !time.isPositiveInfinity, 
      !time.isNegativeInfinity else {
      return nil
    }
    
    self.seconds = time.seconds
    self.timescale = time.timescale
    self.ts = Date().timeIntervalSince1970
    self.tag = time.isIndefinite ? .finished : .normal
  }
  
  /// A dictionary of this timestamp.
  /// 
  /// For legacy reasons, we are using dictionary objects in the key-value 
  /// store. With Timestamp being Codable, JSON Data would be better.
  var dictionary: [String: Any] {
    return [
      "seconds": seconds,
      "timescale": timescale,
      "ts": ts,
      "tag": tag.rawValue
    ]
  }
}
