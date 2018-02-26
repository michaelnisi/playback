//
//  FileProxyDelegate.swift
//  fileproxy
//
//  Created by Michael Nisi on 22.02.18.
//

import Foundation

public protocol FileProxyDelegate {

  func proxy(
    _ proxy: FileProxying,
    url: URL,
    successfullyDownloadedTo location: URL)

  func proxy(
    _ proxy: FileProxying,
    url: URL?,
    didCompleteWithError error: Error?)

  func proxy(
    _ proxy: FileProxying,
    url: URL,
    failedToDownloadWith error: Error)

}
