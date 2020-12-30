//
//  ImageRepository.swift
//  Playback
//
//  Created by Michael Nisi on 13.12.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import Nuke
import os.log
import FeedKit
import UIKit

/// Provides processed images as fast as possible.
public final class ImageRepository {

  private static func removeAllFromCache(named name: String) throws {
    guard let root = FileManager.default.urls(
      for: .cachesDirectory, in: .userDomainMask).first else {
      throw NSError(
        domain: NSCocoaErrorDomain,
        code: NSFileNoSuchFileError,
        userInfo: nil
      )
    }

    let url = root.appendingPathComponent(name)

    try FileManager.default.removeItem(at: url)
  }
  
  private static func makeDataLoader() -> DataLoading {
    let conf = DataLoader.defaultConfiguration
    let dice = Int.random(in: 1...6)
    
    if dice == 6 {
      os_log("using protocol cache policy", log: log)
      
      conf.requestCachePolicy = .useProtocolCachePolicy
    } else {
      conf.requestCachePolicy = .returnCacheDataElseLoad
    }
    
    return DataLoader(configuration: conf)
  }

  /// Returns a new image pipeline.
  ///
  /// Sporadically follows `.useProtocolCachePolicy`, instead of 
  /// `.returnCacheDataElseLoad`, for keeping up-to-date. This compromise can be
  /// unfortunate for users offline during this session.
  ///
  /// - Parameter removing: Clears the cache (for development).
  private static func makeImagePipeline(removing: Bool = false) -> ImagePipeline {
    let name = "ink.codes.feedkit.images"
    
    if removing {
      do {
        os_log("trying to remove cache", log: log, type: .info)
        try removeAllFromCache(named: name)
      } catch {
        os_log("nothing to remove", log: log)
      }
    }
    
    var conf = ImagePipeline.Configuration()
    conf.dataLoader = makeDataLoader()
    
    return ImagePipeline(configuration: conf)
  }

  init() {
    ImagePipeline.shared = ImageRepository.makeImagePipeline(removing: true)
  }

  public static var shared: Images = ImageRepository()

  fileprivate let preheater = Nuke.ImagePreheater()

  /// A thread-safe temporary cache for URL objects. Those aren’t cheap.
  private var urls = NSCache<NSString, NSURL>()
  
  /// Hi-res images of these feeds have been preloaded.
  var preloadedImages = Set<Int>()
}

// MARK: - Choosing and Caching URLs

extension ImageRepository {

  /// Picks and returns the optimal image URL for `size`.
  ///
  /// - Parameters:
  ///   - item: The image URL container.
  ///   - size: The size to choose an URL for.
  ///
  /// - Returns: An image URL or `nil` if the item doesn’t contain one of the
  /// expected URLs.
  private func imageURL(
    representing item: Imaginable, at size: CGSize) -> URL? {
    let wanted = size.width * UIScreen.main.scale

    var urlString: String?

    if wanted <= 30 {
      urlString = item.iTunes?.img30
    } else if wanted <= 60 {
      urlString = item.iTunes?.img60
    } else if wanted <= 180 {
      urlString = item.iTunes?.img100
    } else {
      urlString = item.iTunes?.img600
    }

    if urlString == nil {
      os_log("falling back on LARGE image", log: log)

      if let entry = item as? Entry {
        urlString = entry.feedImage
      }

      urlString = urlString ?? item.image
    }

    guard let string = urlString, let url = makeURL(string: string) else {
      os_log("no image URL", log: log, type: .error)
      return nil
    }

    return url
  }

  /// Returns a cached URL for `string` creating and caching new URLs.
  private func makeURL(string: String) -> URL? {
    guard let url = urls.object(forKey: string as NSString) as URL? else {
      if let fresh = URL(string: string) {
        urls.setObject(fresh as NSURL, forKey: string as NSString)
        return fresh
      }

      return nil
    }

    return url
  }

  /// Represents an image internally.
  private struct FKImage {

    /// Identifies an image.
    struct ID: CustomStringConvertible {
      let url: URL
      let size: CGSize
      let isClean: Bool

      var description: String {
        return "( \(url.lastPathComponent), \(size), \(isClean) )"
      }
    }
  }

  /// Returns URL and/or cached response for placeholding.
  ///
  /// Receiving an image response but no URL is impossible.
  private func makePlaceholder(
    item: Imaginable, size: CGSize, isClean: Bool) -> (URL?, ImageContainer?) {
    guard let iTunes = item.iTunes else {
      os_log("aborting placeholding: iTunes object not found", log: log)
      return (nil, nil)
    }

    var urlStrings = [iTunes.img30, iTunes.img60, iTunes.img100, iTunes.img600]

    if let image = item.image {
      urlStrings.append(image)
    }

    // Finding the first cached response.

    for urlString in urlStrings {
      guard let url = makeURL(string: urlString) else {
        continue
      }

      let exact = FKImage.ID(url: url, size: size, isClean: isClean)

      // Arbritrary size drawn from anecdotal evidence.
      let commonSize = CGSize(width: 82, height: 82)
      let common = FKImage.ID(url: url, size: commonSize, isClean: isClean)

      if let res =
        cachedResponse(matching: exact) ??
        cachedResponse(matching: common) {
        return (url, res)
      }
    }

    // Got no cached response, scaling placeholder to a quarter of the original
    // size, divided by the screen scale factor to compensate multiplication
    // in imageURL(representing:at:).

    let l =  1 / 4 / UIScreen.main.scale
    let s = size.applying(CGAffineTransform(scaleX: l, y: l))

    return (imageURL(representing: item, at: s), nil)
  }
}

// MARK: - Images

extension ImageRepository: Images {

  public func cancel(displaying imageView: UIImageView?) {
    guard let v = imageView else {
      return
    }
    
    Nuke.cancelRequest(for: v)
  }

  public func flush() {
    urls.removeAllObjects()

    // The Nuke image cache automatically removes all stored elements when it
    // received a memory warning. It also sweeps its cache when the app enters 
    // the background.
  }
  
  private func cachedImage(url: URL) -> UIImage? {
    let req = URLRequest(url: url)
    let res = Nuke.DataLoader.sharedUrlCache.cachedResponse(for: req)
    
    guard let data = res?.data else {
      return nil
    }
    
    return UIImage(data: data, scale: UIScreen.main.scale)
  }
  
  private static func matchingSize(image: UIImage, size rhs: CGSize) -> Bool {
    let s = image.scale
    let lhs = CGSize(width: image.size.width * s, height: image.size.height * s)

    return lhs == rhs
  }

  public func cachedImage(
    representing item: Imaginable, at size: CGSize) -> UIImage? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    
    guard let url = imageURL(representing: item, at: size) else {
      return nil
    }
    
    os_log("accessing cached: %{public}@",
           log: log, type: .info, url.lastPathComponent)

    guard let img = cachedImage(url: url) else {
      os_log("not cached: %{public}@", log: log, String(describing: item))
      return nil
    }
    
    guard ImageRepository.matchingSize(image: img, size: size) else {
      os_log("resizing: %{public}@", 
             log: log, type: .info, String(describing: item))
      return ImageProcessors.Resize(size: size, crop: true).process(img)
    }
  
    return img
  }

  private static func makeImageLoadingOptions(
    placeholder: UIImage?,
    failureImage: UIImage?
  ) -> ImageLoadingOptions {
    ImageLoadingOptions(
      placeholder: placeholder,
      transition: nil,
      failureImage: failureImage,
      failureImageTransition: nil,
      contentModes: nil
    )
  }
  
  private static func makeProcessors(id: FKImage.ID) -> [ImageProcessing] {
    guard !id.isClean else {
      return [ImageProcessors.Resize(size: id.size, crop: true)]
    }
    
    let r: CGFloat = id.size.width <= 100 ? 3 : 6
    
    return [ImageProcessors.Composition([
      ImageProcessors.Resize(size: id.size, crop: true),
      ImageProcessors.RoundedCorners(radius: r, border: .none)
    ])]
  }
  
  /// Returns a request for image `url` at `size`.
  ///
  /// - Parameter identifier: Identifies the image to load.
  ///
  /// The default processor adds rounded corners and a gray frame.
  private static func makeImageRequest(identifier id: FKImage.ID) -> ImageRequest {
    let processors = makeProcessors(id: id)
    var req = ImageRequest(url: id.url, processors: processors)
    
    // Preferring smaller images, assuming they are placeholders or lists.
    if id.size.width <= 120 {
      req.priority = .veryHigh
    }
    
    return req
  }

  private func cachedResponse(matching id: FKImage.ID) -> ImageContainer? {
    let req = ImageRepository.makeImageRequest(identifier: id)

    return ImagePipeline.shared.cachedImage(for: req)
  }

  /// Scales `size` for`quality`.
  private static
  func makeSize(size: CGSize, quality: ImageQuality = .medium) -> CGSize {
    let q = quality.rawValue
    let (w, h) = ((size.width / q).rounded(), (size.height / q).rounded())

    return CGSize(width: w, height: h)
  }

  public func loadImage(
    representing item: Imaginable,
    into imageView: UIImageView,
    options: FKImageLoadingOptions,
    completionBlock: (() -> Void)? = nil
  ) {
    dispatchPrecondition(condition: .onQueue(.main))
    
    let originalSize = imageView.bounds.size

    os_log("getting: ( %{public}@, %{public}@ )",
           log: log, type: .info, item.title, originalSize as CVarArg)

    let relativeSize = ImageRepository.makeSize(
      size: originalSize, quality: options.quality)

    guard let itemURL = imageURL(representing: item, at: relativeSize) else {
      os_log("missing URL: %{public}@",
             log: log, type: .error, String(describing: item))
      return
    }

    let id = FKImage.ID(url: itemURL, size: originalSize, isClean: options.isClean)

    if let res = cachedResponse(matching: id) {
      os_log("cache hit: ( %{public}@, %{public}@ )",
             log: log, type: .info, item.title, itemURL.lastPathComponent)

      imageView.image = res.image

      completionBlock?()
      return
    }

    /// Issues the actual load request.
    func issue(_ url: URL, cb: (() -> Void)? = nil) {
      dispatchPrecondition(condition: .onQueue(.main))

      let req = ImageRepository.makeImageRequest(identifier: FKImage.ID(
        url: url, size: originalSize, isClean: options.isClean))

      let opts = ImageRepository.makeImageLoadingOptions(
        placeholder: imageView.image,
        failureImage: options.fallbackImage ?? imageView.image
      )

      os_log("loading: %{public}@", log: log, type: .info, url.lastPathComponent)

      Nuke.loadImage(with: req, options: opts, into: imageView, completion: { result in
        switch result {
        case .failure(let er):
          os_log("image loading failed: ( %{public}@, %{public}@ )", log: log, er as CVarArg, String(describing: req))

        case .success:
          break
        }

        dispatchPrecondition(condition: .onQueue(.main))
        cb?()
      })
    }

    // If this isn’t specifically direct, no cached response is available, and
    // we can find a suitable placeholder, we are loading a smaller image first.

    guard !options.isDirect else {
      return issue(itemURL) {
        completionBlock?()
      }
    }

    let (placeholderURL, placeholder) = makePlaceholder(
      item: item, size: originalSize, isClean: options.isClean)

    guard placeholderURL != nil || placeholder != nil else {
      return issue(itemURL) {
        completionBlock?()
      }
    }
    
    os_log("placeholding", log: log, type: .info)

    if let image = placeholder?.image {
      let p = placeholderURL?.lastPathComponent ?? "weirdly got no URL"
      os_log("cache hit: ( %{public}@, %{public}@ )", log: log, type: .info, item.title, p)
      
      imageView.image = image

      return issue(itemURL) {
        completionBlock?()
      }
    }

    issue(placeholderURL!) {
      issue(itemURL) {
        completionBlock?()
      }
    }
  }

  public func loadImage(
    representing item: Imaginable,
    into imageView: UIImageView,
    options: FKImageLoadingOptions
  ) {
    loadImage(
      representing: item,
      into: imageView,
      options: options,
      completionBlock: nil
    )
  }

  public func loadImage(
    representing item: Imaginable, into imageView: UIImageView) {
    let defaults = FKImageLoadingOptions()

    loadImage(representing: item, into: imageView, options: defaults)
  }
}

// MARK: - Loading without UIView

extension ImageRepository {
  
  public func loadImage(
    representing item: Imaginable,
    at size: CGSize,
    completed: ((UIImage?) -> Void)?) {
    guard let request = makeRequests(items: [item], size: size, quality: .medium).first else {
      return
    }
    
    Nuke.ImagePipeline.shared.loadImage(with: request, completion: { result in
      if case .success(let data) = result {
        completed?(data.image)
      } else {
        completed?(nil)
      }
    })
  }
}

// MARK: - Prefetching

extension ImageRepository {

  private func makeRequests(
    items: [Imaginable], size: CGSize, quality: ImageQuality
  ) -> [ImageRequest] {
    return items.compactMap {
      let relativeSize = ImageRepository.makeSize(size: size, quality: quality)

      guard let url = imageURL(representing: $0, at: relativeSize) else {
        return nil
      }

      let id = FKImage.ID(url: url, size: size, isClean: false)

      return ImageRepository.makeImageRequest(identifier: id)
    }
  }

  public func prefetchImages(
    representing items: [Imaginable], at size: CGSize, quality: ImageQuality
  ) -> [ImageRequest] {
    os_log("prefetching: %{public}i", log: log, type: .info, items.count)

    let reqs = makeRequests(items: items, size: size, quality: quality)
    
    preheater.startPreheating(with: reqs)

    return reqs
  }

  public func cancel(prefetching requests: [ImageRequest]) {
    os_log("cancelling prefetching", log: log, type: .info)
    preheater.stopPreheating(with: requests)
  }

  public func cancelPrefetching(
    _ items: [Imaginable], at size: CGSize, quality: ImageQuality) {
    os_log("cancelling prefetching: %{public}i", 
           log: log, type: .info, items.count)

    let reqs = makeRequests(items: items, size: size, quality: quality)

    preheater.stopPreheating(with: reqs)
  }
}

// MARK: - Preloading

extension ImageRepository {
  
  public func preloadImages(representing items: [Imaginable], at size: CGSize) {
    let ids = Set(items.compactMap { $0.iTunes?.iTunesID })
    let diff = ids.subtracting(preloadedImages)
    
    let needed = items.filter { 
      guard let id = $0.iTunes?.iTunesID else { return false }
      return diff.contains(id) 
    }
    
    let preloading: [Int] = needed.compactMap {
      guard let id = $0.iTunes?.iTunesID, !preloadedImages.contains(id),
        let url = imageURL(representing: $0, at: size) else {
        return nil
      }
      
      Nuke.ImagePipeline.shared.loadImage(with: url, completion: { [weak self] result in
        switch result {
        case .failure:
          os_log("preloading failed: %{public}@", log: log, url as CVarArg)
        case .success:
          self?.preloadedImages.insert(id)
        }
      })
      
      return id
    }
    
    os_log("preloading: %{public}i", log: log, type: .info, preloading.count)
  }
}
