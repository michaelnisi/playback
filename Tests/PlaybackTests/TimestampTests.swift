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

import XCTest
import AVFoundation
@testable import Playback

class TimestampTests: XCTestCase {
  
  func testDecodable() {
    let json = """
    {
      "seconds": 123,
      "timescale": 10000,
      "ts": 3600,
      "tag": 0
    }
    """
    
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    let found = try! decoder.decode(Timestamp.self, from: data)
    let wanted = Timestamp(seconds: 123, timescale: 10000, ts: 3600, tag: .normal)
    
    XCTAssertEqual(found, wanted)
  }
  
  func testMakeDictionary() {
    XCTAssertNil(Timestamp(time: CMTime())?.dictionary)  
    
    XCTAssertNil((Timestamp(time: .negativeInfinity))?.dictionary) 
    XCTAssertNil((Timestamp(time: .positiveInfinity))?.dictionary)
    
    XCTAssertNotNil((Timestamp(time: .indefinite))?.dictionary)
    
    XCTAssertNotNil((Timestamp(time: CMTime(
      seconds: 30, 
      preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    ))?.dictionary)  
  }
  
  func testMakeTimeStamp() {
    XCTAssertNil(Timestamp(dict: [:]))
    XCTAssertNil(Timestamp(dict: ["hello": "here dog"]))
    XCTAssertNil(Timestamp(dict: [
      "seconds": 123,
      "timescale": 123,
      "ts": 123
    ]))
    
    XCTAssertNotNil(Timestamp(dict: [
      "seconds": 123.0,
      "timescale": CMTimeScale(exactly: 1000)!,
      "ts": 123.0
    ]))
    
    let fixtures: [(Int?, Timestamp.Tag)] = [
      (nil, .normal),
      (0, .normal),
      (1, .finished),
      (2, .normal)
    ]
    
    for f in fixtures {
      let found = Timestamp(dict: [
        "seconds": 123.0,
        "timescale": CMTimeScale(exactly: 1000)!,
        "ts": 123.0,
        "tag": f.0 as Any
      ])
      
      let wanted = Timestamp(seconds: 123, timescale: 1000, ts: 123.0, tag: f.1)
      
      XCTAssertEqual(found, wanted)
    }
  }
}
