//
//  TLPhotoLibrary.swift
//  TLPhotosPicker
//
//  Created by wade.hawk on 2017. 5. 3..
//  Copyright © 2017년 wade.hawk. All rights reserved.
//

import UIKit
import Photos

public protocol TLPhotoLibraryDelegate: class {
  func loadCameraRollCollection(collection: TLAssetsCollection)
  func loadCompleteAllCollection(collections: [TLAssetsCollection])
}

public class TLPhotoLibrary {

  public init() {}

  public weak var delegate: TLPhotoLibraryDelegate?

  public lazy var imageManager: PHCachingImageManager = {
    return PHCachingImageManager()
  }()
  public var limitMode: Bool = false
  public var assetCollections: [PHFetchResult<PHAssetCollection>] = []
  public var albums: PHFetchResult<PHCollection>?

  deinit {
    //        print("deinit TLPhotoLibrary")
  }

  @discardableResult
  public func livePhotoAsset(asset: PHAsset, size: CGSize = CGSize(width: 720, height: 1280), progressBlock: Photos.PHAssetImageProgressHandler? = nil, completionBlock:@escaping (PHLivePhoto, Bool) -> Void ) -> PHImageRequestID {
    let options = PHLivePhotoRequestOptions()
    options.deliveryMode = .opportunistic
    options.isNetworkAccessAllowed = true
    options.progressHandler = progressBlock
    let scale = min(UIScreen.main.scale, 2)
    let targetSize = CGSize(width: size.width*scale, height: size.height*scale)
    let requestID = self.imageManager.requestLivePhoto(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { (livePhoto, info) in
      let complete = (info?["PHImageResultIsDegradedKey"] as? Bool) == false
      if let livePhoto = livePhoto {
        completionBlock(livePhoto, complete)
      }
    }
    return requestID
  }

  @discardableResult
  public func videoAsset(asset: PHAsset, deliveryFormat: PHVideoRequestOptionsDeliveryMode = .automatic, progressBlock: Photos.PHAssetImageProgressHandler? = nil, completionBlock:@escaping (AVPlayerItem?, [AnyHashable: Any]?) -> Void ) -> PHImageRequestID {
    let options = PHVideoRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = deliveryFormat
    options.progressHandler = progressBlock
    let requestID = self.imageManager.requestPlayerItem(forVideo: asset, options: options, resultHandler: { playerItem, info in
      completionBlock(playerItem, info)
    })
    return requestID
  }

  @discardableResult
  public func imageAsset(asset: PHAsset, size: CGSize = CGSize(width: 160, height: 160), options: PHImageRequestOptions? = nil, completionBlock:@escaping (UIImage, Bool) -> Void ) -> PHImageRequestID {
    var options = options
    if options == nil {
      options = PHImageRequestOptions()
      options?.isSynchronous = false
      options?.resizeMode = .exact
      options?.deliveryMode = .opportunistic
      options?.isNetworkAccessAllowed = true
    }
    let scale = min(UIScreen.main.scale, 2)
    let targetSize = CGSize(width: size.width*scale, height: size.height*scale)
    let requestID = self.imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
      let complete = (info?["PHImageResultIsDegradedKey"] as? Bool) == false
      if let image = image {
        completionBlock(image, complete)
      }
    }
    return requestID
  }

  func cancelPHImageRequest(requestID: PHImageRequestID) {
    self.imageManager.cancelImageRequest(requestID)
  }

  @discardableResult
  public class func cloudImageDownload(asset: PHAsset, size: CGSize = PHImageManagerMaximumSize, progressBlock: @escaping (Double) -> Void, completionBlock:@escaping (UIImage?) -> Void ) -> PHImageRequestID {
    let options = PHImageRequestOptions()
    options.isSynchronous = false
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .opportunistic
    options.version = .current
    options.resizeMode = .exact
    options.progressHandler = { (progress, _, _, _) in
      progressBlock(progress)
    }
    let requestID = PHCachingImageManager().requestImageData(for: asset, options: options) { (imageData, _, _, info) in
      if let data = imageData, let _ = info {
        completionBlock(UIImage(data: data))
      } else {
        completionBlock(nil)// error
      }
    }
    return requestID
  }

  @discardableResult
  public class func fullResolutionImageData(asset: PHAsset) -> UIImage? {
    let options = PHImageRequestOptions()
    options.isSynchronous = true
    options.resizeMode = .none
    options.isNetworkAccessAllowed = false
    options.version = .current
    var image: UIImage?
    _ = PHCachingImageManager().requestImageData(for: asset, options: options) { (imageData, _, _, _) in
      if let data = imageData {
        image = UIImage(data: data)
      }
    }
    return image
  }
}

public extension PHFetchOptions {
  public func merge(predicate: NSPredicate) {
    if let storePredicate = self.predicate {
      self.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [storePredicate, predicate])
    } else {
      self.predicate = predicate
    }
  }
}

// MARK: - Load Collection
extension TLPhotoLibrary {
  public func getOption(configure: TLPhotosPickerConfigure) -> PHFetchOptions {
    let options: PHFetchOptions
    if let fetchOption = configure.fetchOption {
      options = fetchOption
    } else {
      options = PHFetchOptions()
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    }
    if let mediaType = configure.mediaType {
      let mediaPredicate = NSPredicate(format: "mediaType = %i", mediaType.rawValue)
      options.merge(predicate: mediaPredicate)
    }
    if configure.allowedVideo == false {
      let notVideoPredicate = NSPredicate(format: "mediaType != %i", PHAssetMediaType.video.rawValue)
      options.merge(predicate: notVideoPredicate)
    }
    if configure.allowedLivePhotos == false {
      let notLivePhotoPredicate = NSPredicate(format: "NOT ((mediaSubtype & %d) != 0)", PHAssetMediaSubtype.photoLive.rawValue)
      options.merge(predicate: notLivePhotoPredicate)
    }
    if let maxVideoDuration = configure.maxVideoDuration {
      let durationPredicate = NSPredicate(format: "duration < %f", maxVideoDuration)
      options.merge(predicate: durationPredicate)
    }
    return options
  }

  public func fetchResult(collection: TLAssetsCollection?, configure: TLPhotosPickerConfigure) -> PHFetchResult<PHAsset>? {
    guard let phAssetCollection = collection?.phAssetCollection else { return nil }
    let options = getOption(configure: configure)
    return PHAsset.fetchAssets(in: phAssetCollection, options: options)
  }

  public func fetchCollection(configure: TLPhotosPickerConfigure) {
    self.albums = nil
    self.assetCollections = []
    let useCameraButton = configure.usedCameraButton
    let options = getOption(configure: configure)
    let fetchCollectionOption = configure.fetchCollectionOption

    func getAlbum(subType: PHAssetCollectionSubtype, result: inout [TLAssetsCollection]) {
      let collectionOption = fetchCollectionOption[.assetCollections(.album)]
      let fetchCollection = PHAssetCollection.fetchAssetCollections(with: .album,
                                                                    subtype: subType,
                                                                    options: collectionOption)
      self.assetCollections.append(fetchCollection)
      var collections = [PHAssetCollection]()
      fetchCollection.enumerateObjects { (collection, _, _) in
        if configure.allowedAlbumCloudShared == false && collection.assetCollectionSubtype == .albumCloudShared {
        } else {
          collections.append(collection)
        }
      }
      for collection in collections {
        if !result.contains(where: { $0.localIdentifier == collection.localIdentifier }) {
          var assetsCollection = TLAssetsCollection(collection: collection)
          assetsCollection.title = configure.customLocalizedTitle[assetsCollection.title] ?? assetsCollection.title
          assetsCollection.fetchResult = PHAsset.fetchAssets(in: collection, options: options)
          if assetsCollection.count > 0 {
            result.append(assetsCollection)
          }
        }
      }
    }

    @discardableResult
    func getSmartAlbum(subType: PHAssetCollectionSubtype,
                       useCameraButton: Bool = false,
                       result: inout [TLAssetsCollection])
    -> TLAssetsCollection? {
      let collectionOption = fetchCollectionOption[.assetCollections(.smartAlbum)]
      let fetchCollection = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                                    subtype: subType,
                                                                    options: collectionOption)
      self.assetCollections.append(fetchCollection)
      if
        let collection = fetchCollection.firstObject,
        result.contains(where: { $0.localIdentifier == collection.localIdentifier }) == false {
        var assetsCollection = TLAssetsCollection(collection: collection)
        assetsCollection.title = configure.customLocalizedTitle[assetsCollection.title] ?? assetsCollection.title
        assetsCollection.fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        if assetsCollection.count > 0 || useCameraButton {
          result.append(assetsCollection)
          return assetsCollection
        }
      }
      return nil
    }
    if let fetchCollectionTypes = configure.fetchCollectionTypes {
      DispatchQueue.global(qos: .userInteractive).async { [weak self] in
        var assetCollections = [TLAssetsCollection]()
        for (type, subType) in fetchCollectionTypes {
          if type == .smartAlbum {
            getSmartAlbum(subType: subType, result: &assetCollections)
          } else {
            getAlbum(subType: subType, result: &assetCollections)
          }
        }
        DispatchQueue.main.async {
          self?.delegate?.loadCompleteAllCollection(collections: assetCollections)
        }
      }
    } else {
      DispatchQueue.global(qos: .userInteractive).async { [weak self] in
        var assetCollections = [TLAssetsCollection]()

        // Recents
        let recentsCollection = getSmartAlbum(subType: .smartAlbumUserLibrary,
                                              useCameraButton: useCameraButton,
                                              result: &assetCollections)
        if var cameraRoll = recentsCollection {
          cameraRoll.title = configure.customLocalizedTitle[cameraRoll.title] ?? cameraRoll.title
          cameraRoll.useCameraButton = useCameraButton
          assetCollections[0] = cameraRoll
          DispatchQueue.main.async {
            self?.delegate?.loadCameraRollCollection(collection: cameraRoll)
          }
        }
        // Screenshots
        getSmartAlbum(subType: .smartAlbumScreenshots, result: &assetCollections)
        // Selfies
        getSmartAlbum(subType: .smartAlbumSelfPortraits, result: &assetCollections)
        // Panoramas
        getSmartAlbum(subType: .smartAlbumPanoramas, result: &assetCollections)
        // Favorites
        getSmartAlbum(subType: .smartAlbumFavorites, result: &assetCollections)
        // CloudShared
        getSmartAlbum(subType: .albumCloudShared, result: &assetCollections)

        // Other smart albums
        getSmartAlbum(subType: .smartAlbumGeneric, result: &assetCollections)
        getSmartAlbum(subType: .smartAlbumTimelapses, result: &assetCollections)
        getSmartAlbum(subType: .smartAlbumAllHidden, result: &assetCollections)
        getSmartAlbum(subType: .smartAlbumRecentlyAdded, result: &assetCollections)

        getSmartAlbum(subType: .smartAlbumBursts, result: &assetCollections)
        getSmartAlbum(subType: .smartAlbumSlomoVideos, result: &assetCollections)

        if #available(iOS 10.2, *) {
          getSmartAlbum(subType: .smartAlbumDepthEffect, result: &assetCollections)
        }
        if #available(iOS 10.3, *) {
          getSmartAlbum(subType: .smartAlbumLivePhotos, result: &assetCollections)
        }
        if #available(iOS 11.0, *) {
          getSmartAlbum(subType: .smartAlbumAnimated, result: &assetCollections)
          getSmartAlbum(subType: .smartAlbumLongExposures, result: &assetCollections)
        }

        // get all another albums
        getAlbum(subType: .any, result: &assetCollections)
        if configure.allowedVideo {
          // Videos
          getSmartAlbum(subType: .smartAlbumVideos, result: &assetCollections)
        }
        // Album
        let collectionOption = fetchCollectionOption[.topLevelUserCollections]
        let albumsResult = PHCollectionList.fetchTopLevelUserCollections(with: collectionOption)
        self?.albums = albumsResult
        albumsResult.enumerateObjects({ (collection, _, _) -> Void in
          guard let collection = collection as? PHAssetCollection else { return }
          var assetsCollection = TLAssetsCollection(collection: collection)
          assetsCollection.title = configure.customLocalizedTitle[assetsCollection.title] ?? assetsCollection.title
          assetsCollection.fetchResult = PHAsset.fetchAssets(in: collection, options: options)
          if assetsCollection.count > 0, !assetCollections.contains(where: { $0.localIdentifier == collection.localIdentifier }) {
            assetCollections.append(assetsCollection)
          }
        })

        DispatchQueue.main.async {
          self?.delegate?.loadCompleteAllCollection(collections: assetCollections)
        }
      }
    }
  }
}
