//
//  FileLocator.swift
//  fileproxy
//
//  Created by Michael Nisi on 21.02.18.
//

import Foundation

typealias FileID = Int
typealias RemoteURL = URL

/// Locates one file.
struct FileLocator: Codable {

  /// A naiive hash of the remote URL to identify the file.
  let fileID: FileID

  /// The remote URL of the file.
  let url: RemoteURL

  private static func djb2Hash(string: String) -> Int {
    let unicodeScalars = string.unicodeScalars.map { $0.value }
    return Int(unicodeScalars.reduce(5381) {
      ($0 << 5) &+ $0 &+ Int($1)
    })
  }

  /// Returns unsafe, but good enough, hash of `url`.
  private static func makeHash(url: URL) -> Int {
    let str = url.absoluteString
    let hash = djb2Hash(string: str)
    return hash
  }

  init?(url: RemoteURL) {
    guard !url.isFileURL else {
      return nil
    }
    self.fileID = FileLocator.makeHash(url: url)
    self.url = url
  }


  static func targetDirectory() throws -> URL {
    let parent: URL? = try {
      #if os(iOS)
        return try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil,
            create: false)
      #elseif os(macOS)
        guard #available(macOS 10.12, *) else {
          throw FileProxyError.targetRequired
        }
        return FileManager.default.homeDirectoryForCurrentUser
      #endif
    }()

    guard
      let p = parent,
      let target = URL(string: "ink.codes.fileproxy", relativeTo: p) else {
      throw FileProxyError.targetRequired
    }

    return target
  }

  private func targetURL() throws -> URL {
    let target = try FileLocator.targetDirectory()

    func path() -> URL {
      return target.appendingPathComponent("\(fileID)")
        .appendingPathExtension(url.pathExtension)
    }

    do {
      try FileManager.default.createDirectory(
        at: target, withIntermediateDirectories: false, attributes: nil)
      return path()
    } catch CocoaError.fileWriteFileExists {
      return path()
    } catch {
      throw error
    }
  }

  public var localURL: URL? {
    do {
      return try targetURL()
    } catch {
      fatalError("unhandled error")
    }
  }
}

// MARK: - Hashable

extension FileLocator: Hashable {

  public var hashValue: Int {
    return fileID
  }

  public static func ==(lhs: FileLocator, rhs: FileLocator) -> Bool {
    return lhs.fileID == rhs.fileID
  }

}
