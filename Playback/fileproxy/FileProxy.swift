//
//  FileProxy.swift
//  fileproxy
//
//  Created by Michael Nisi on 21.02.18.
//

import Foundation
import os.log

@available(iOS 10.0, macOS 10.13, *)
private let log = OSLog(subsystem: "ink.codes.fileproxy", category: "fs")

final class FileProxy: NSObject {

  var backgroundCompletionHandler: (() -> Void)?

  let identifier: String
  let maxBytes: Int
  var delegate: FileProxyDelegate?

  init(
    identifier: String = "ink.codes.fileproxy",
    maxBytes: Int = 256 * 1024 * 1024,
    delegate: FileProxyDelegate? = nil
  ) {
    self.identifier = identifier
    self.maxBytes = maxBytes
    self.delegate = delegate
  }

  lazy var session: URLSession = {
    let conf = URLSessionConfiguration.background(withIdentifier: identifier)
    conf.isDiscretionary = true
    return URLSession(configuration: conf, delegate: self, delegateQueue: nil)
  }()

  deinit {
    session.finishTasksAndInvalidate()
  }

}

// MARK: - URLSessionDelegate

extension FileProxy: URLSessionDelegate {

  #if(iOS)
  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async { [weak self] in
      self?.backgroundCompletionHandler?()
    }
  }
  #endif

}

// MARK: - URLSessionTaskDelegate

extension FileProxy: URLSessionTaskDelegate {

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    let url = task.originalRequest?.url
    delegate?.proxy(self, url: url, didCompleteWithError: error)
  }

}

// MARK: - URLSessionDownloadDelegate

extension FileProxy: URLSessionDownloadDelegate {

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL) {
    guard
      let origin = downloadTask.originalRequest?.url,
      let savedURL = FileLocator(url: origin)?.localURL else {
      delegate?.proxy(self, url: nil, didCompleteWithError: nil)
      return
    }

    guard let res = downloadTask.response as? HTTPURLResponse  else {
      if #available(iOS 10.0, macOS 10.13, *) {
        os_log("no reponse: %{public}@", log: log, type: .debug,
               downloadTask as CVarArg)
      }
      return
    }

    guard (200...299).contains(res.statusCode) else {
      if #available(iOS 10.0, macOS 10.13, *) {
        os_log("unexpected response: %@", log: log, res.statusCode)
      }
      delegate?.proxy(self, url: origin, failedToDownloadWith: FileProxyError.http(res.statusCode))
      return
    }

    if #available(iOS 10.0, macOS 10.13, *) {
      os_log("moving item: %{public}@", log: log, type: .debug,
             downloadTask as CVarArg)
    }

    do {
      try FileManager.default.moveItem(at: location, to: savedURL)

      delegate?.proxy(self, url: origin, successfullyDownloadedTo: savedURL)
    } catch {
      delegate?.proxy(self, url: origin, failedToDownloadWith: error)
      return
    }

  }

}

// MARK: - FileProxying

extension FileProxy: FileProxying {

  func totalBytes() throws -> Int {
    do {
      let dir = try FileLocator.targetDirectory()
      let urls = try FileManager.default.contentsOfDirectory(at: dir,
        includingPropertiesForKeys: [.fileSizeKey])
      return try urls.reduce(0, { acc, url in
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else {
          throw FileProxyError.fileSizeRequired
        }
        return acc + fileSize
      })
    } catch {
      throw error
    }
  }

  /// Throws if we ran out of file space.
  private func checkSize() throws {
    let bytes = try totalBytes()
    let space = maxBytes - bytes
    guard space > 0 else {
      throw FileProxyError.maxBytesExceeded(space)
    }
  }

  @discardableResult func url(
    for url: URL,
    with configuration: DownloadTaskConfiguration? = nil
  ) throws -> URL {
    guard let localURL = FileLocator(url: url)?.localURL else {
      throw FileProxyError.invalidURL(url)
    }

    if #available(iOS 10.0, macOS 10.13, *) {
      os_log(
        """
        checking: {
          %{public}@,
          %{public}@
        }
        """, log: log, type: .debug, url as CVarArg, localURL as CVarArg)
    }

    do {
      if try localURL.checkResourceIsReachable() {
        if #available(iOS 10.0, macOS 10.13, *) {
          os_log("reachable: %{public}@", log: log, type: .debug,
                 localURL as CVarArg)
        }
        return localURL
      }
    } catch {
      if #available(iOS 10.0, macOS 10.13, *) {
        os_log("not reachable: %{public}@", log: log, type: .debug,
               localURL as CVarArg)
      }

    }

    try checkSize()

    let session = self.session

    func go() {
      let task = session.downloadTask(with: url)

      if #available(iOS 11.0, macOS 10.13, *) {
        if let s = configuration?.countOfBytesClientExpectsToSend {
          task.countOfBytesClientExpectsToSend = s
        }
        if let r = configuration?.countOfBytesClientExpectsToReceive {
          task.countOfBytesClientExpectsToReceive = r
        }
        if let d = configuration?.earliestBeginDate {
          task.earliestBeginDate = d
        }
      }

      if #available(iOS 10.0, macOS 10.13, *) {
        os_log("downloading: %{public}@", log: log, type: .debug,
               task as CVarArg)
      }

      task.resume()
    }

    // Guarding against URLs already in-flight.
    session.getTasksWithCompletionHandler { _, _, tasks in
      guard !tasks.isEmpty else {
        return go()
      }

      print("got tasks")

      // TODO: Get matching task and analyze

      let inFlight = tasks.contains { $0.originalRequest?.url == url }
      guard !inFlight else {
        if #available(iOS 10.0, macOS 10.13, *) {
          os_log("aborting: %{public}@ in-flight", log: log, type: .debug, url as CVarArg)
        }
        return // nothing to do
      }
      go()
    }

    return url
  }
}
