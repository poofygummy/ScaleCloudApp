// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2021 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

import UIKit
import CoreLocation
import NextcloudKit
import Photos
import OrderedCollections
import LucidBanner

class NCAutoUpload: NSObject {
    static let shared = NCAutoUpload()

    private let database = NCManageDatabase.shared
    private let global = NCGlobal.shared
    private let networking = NCNetworking.shared
    private var endForAssetToUpload: Bool = false

    // MARK: - ScaleCloud Helpers

    /// Mirrors the Android isToCsaCloud check (specific to the "toth-adattar" tailnet).
    private func isToCsaCloud(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host else { return false }
        return host == "toth-adattar" || host.hasPrefix("toth-adattar.")
    }

    /// Returns the correct remote base path depending on the source album.
    /// This allows different folders (Camera, Screenshots, etc.) to upload to different locations.


    func initAutoUpload(controller: NCMainTabBarController? = nil) async -> Int {
        guard self.networking.isOnline else {
            return 0
        }
        var counter = 0

        let tblAccounts = await NCManageDatabase.shared.getTableAccountsAsync(predicate: NSPredicate(format: "autoUploadStart == true"))
        for tblAccount in tblAccounts {
            let albumIds = NCPreferences().getAutoUploadAlbumIds(account: tblAccount.account)
            let assetCollections = PHAssetCollection.allAlbums.filter({albumIds.contains($0.localIdentifier)})
            let result = await getCameraRollAssets(controller: nil, assetCollections: assetCollections, tblAccount: tableAccount(value: tblAccount))
            if !result.assets.isEmpty {
                let item = await uploadAssets(controller: nil, tblAccount: tblAccount, assets: result.assets, fileNames: result.fileNames, sourceCollections: result.sourceCollections)
                counter += item
            }

            // ScaleCloud: When we detect new photos for a ScaleCloud account, also scan common download locations
            // for newly created general files and queue them with a virtual "downloadsCollection" source.
            if isToCsaCloud(tblAccount.urlBase) {
                let bookmarks = NCPreferences().getScaleCloudWatchedDownloadBookmarks(account: tblAccount.account)
                await ScaleCloudDownloadsHelper.scanAndEnqueueDownloads(for: tableAccount(value: tblAccount), bookmarks: bookmarks)
            }
        }

        return counter
    }

    @MainActor
    func startManualAutoUploadForAlbums(controller: NCMainTabBarController?,
                                        model: NCAutoUploadModel,
                                        assetCollections: [PHAssetCollection],
                                        account: String) async {
        let windowScene = SceneManager.shared.getWindowScene(controller: controller)
        var banner: LucidBanner?
        defer {
            if let banner {
                banner.dismiss()
            }
        }

        guard let tblAccount = await self.database.getTableAccountAsync(predicate: NSPredicate(format: "account == %@", account)) else {
            return
        }

        (banner, _) = await showBanner(windowScene: windowScene,
                                       title: "_info_",
                                       subtitle: "_creating_db_photo_progress_",
                                       systemImage: "photo.on.rectangle.angled",
                                       imageAnimation: .bounce,
                                       imageColor: .systemBlue,
                                       autoDismissAfter: 0,
                                       swipeToDismiss: false
        )

        let result = await getCameraRollAssets(controller: controller, assetCollections: assetCollections, tblAccount: tblAccount)

        // IMPORTANT: Always set to autoUploadSinceDate to now
        await self.database.updateAccountPropertyAsync(\.autoUploadSinceDate, value: Date.now, account: tblAccount.account)

        model.onViewAppear()

        guard !result.assets.isEmpty else {
            nkLog(debug: "Automatic upload 0 upload")
            return
        }

        let num = await uploadAssets(controller: controller, tblAccount: tblAccount, assets: result.assets, fileNames: result.fileNames, sourceCollections: result.sourceCollections)
        nkLog(debug: "Automatic upload \(num) upload")
    }

    private func uploadAssets(controller: NCMainTabBarController?,
                              tblAccount: tableAccount,
                              assets: [PHAsset],
                              fileNames: [String],
                              sourceCollections: [PHAssetCollection] = []) async -> Int {
        let capabilities = await NKCapabilities.shared.getCapabilities(for: tblAccount.account)
        let autoMkcol = capabilities.serverVersionMajor >= NCGlobal.shared.nextcloudVersion33
        let session = NCSession.shared.getSession(account: tblAccount.account)
        let autoUploadServerUrlBase = await self.database.getAccountAutoUploadServerUrlBaseAsync(account: tblAccount.account, urlBase: tblAccount.urlBase, userId: tblAccount.userId)
        var metadatas: [tableMetadata] = []
        let formatCompatibility = NCPreferences().formatCompatibility
        let keychainLivePhoto = NCPreferences().livePhoto
        let fileSystem = NCUtilityFileSystem()
        let skipFileNames = await self.database.fetchSkipFileNamesAsync(account: tblAccount.account,
                                                                        autoUploadServerUrlBase: autoUploadServerUrlBase)

        nkLog(debug: "Automatic upload, new \(assets.count) assets found")

        for (index, asset) in assets.enumerated() {
            let fileName = fileNames[index]

            // Convert HEIC if compatibility mode is on
            let fileNameCompatible = formatCompatibility && (fileName as NSString).pathExtension.lowercased() == "heic" ? (fileName as NSString).deletingPathExtension + ".jpg" : fileName

            if skipFileNames.contains(fileNameCompatible) || skipFileNames.contains(fileName) {
                continue
            }

            let mediaType = asset.mediaType
            let isLivePhoto = asset.mediaSubtypes.contains(.photoLive) && keychainLivePhoto

            // Per-file server URL decision (for ScaleCloud multi-folder support)
            // For ScaleCloud accounts we completely control the base paths here
            // (independent of the account's normal autoUploadServerUrlBase setting).
            var effectiveBase = autoUploadServerUrlBase

            if isToCsaCloud(tblAccount.urlBase) && index < sourceCollections.count {
                let source = sourceCollections[index]
                switch source.assetCollectionSubtype {
                case .smartAlbumScreenshots:
                    effectiveBase = "/Képernyőmentések"
                default:
                    // Camera / Recents / everything else for ScaleCloud accounts
                    effectiveBase = "/Saját Fényképek és Videók/"
                }
            }

            let serverUrl = tblAccount.autoUploadCreateSubfolder ? fileSystem.createGranularityPath(asset: asset, serverUrlBase: effectiveBase) : effectiveBase
            let onWWAN = (mediaType == .image && tblAccount.autoUploadWWAnPhoto) || (mediaType == .video && tblAccount.autoUploadWWAnVideo)
            let uploadSession = onWWAN ? self.networking.sessionUploadBackgroundWWan : self.networking.sessionUploadBackground

            let metadata = await NCManageDatabaseCreateMetadata().createMetadataAsync(
                fileName: fileName,
                ocId: UUID().uuidString,
                serverUrl: serverUrl,
                session: session,
                sceneIdentifier: controller?.sceneIdentifier)

            if isLivePhoto {
                metadata.livePhotoFile = (metadata.fileName as NSString).deletingPathExtension + ".mov"
            }

            metadata.assetLocalIdentifier = asset.localIdentifier
            metadata.autoUploadServerUrlBase = autoUploadServerUrlBase
            metadata.session = uploadSession
            metadata.sessionSelector = NCGlobal.shared.selectorUploadAutoUpload
            metadata.status = NCGlobal.shared.metadataStatusWaitUpload
            metadata.sessionDate = Date()

            metadata.classFile = {
                switch mediaType {
                case .video: return NKTypeClassFile.video.rawValue
                case .image: return NKTypeClassFile.image.rawValue
                default: return ""
                }
            }()

            metadata.iconName = {
                switch mediaType {
                case .video: return NKTypeIconFile.video.rawValue
                case .image: return NKTypeIconFile.image.rawValue
                default: return ""
                }
            }()

            metadata.typeIdentifier = {
                switch mediaType {
                case .video: return "com.apple.quicktime-movie"
                case .image: return "public.image"
                default: return ""
                }
            }()

            metadatas.append(metadata)
        }

        // Set last date in autoUploadOnlyNewSinceDate
        if let metadata = metadatas.last {
            let date = metadata.creationDate as Date
            await self.database.updateAccountPropertyAsync(\.autoUploadSinceDate, value: date, account: session.account)
        }

        if !metadatas.isEmpty {
            if autoMkcol {
                await self.database.addMetadatasAsync(metadatas)
            } else {
                let metadatasFolder = await NCManageDatabaseCreateMetadata().createMetadatasFolderAsync(
                    assets: assets,
                    useSubFolder: tblAccount.autoUploadCreateSubfolder,
                    session: session)
                await self.database.addMetadatasAsync(metadatasFolder + metadatas)
            }
        }

        return metadatas.count
    }

    // MARK: -

    func getCameraRollAssets(controller: NCMainTabBarController?,
                             assetCollections: [PHAssetCollection] = [],
                             tblAccount: tableAccount) async -> (assets: [PHAsset], fileNames: [String], sourceCollections: [PHAssetCollection]) {
        let hasPermission = await withCheckedContinuation { continuation in
            NCAskAuthorization().askAuthorizationPhotoLibrary(controller: controller) { granted in
                continuation.resume(returning: granted)
            }
        }
        guard hasPermission else {
            return ([], [], [])
        }
        let autoUploadServerUrlBase = await self.database.getAccountAutoUploadServerUrlBaseAsync(account: tblAccount.account, urlBase: tblAccount.urlBase, userId: tblAccount.userId)
        var mediaPredicates: [NSPredicate] = []
        var datePredicates: [NSPredicate] = []
        let fetchOptions = PHFetchOptions()

        if tblAccount.autoUploadImage {
            mediaPredicates.append(NSPredicate(format: "mediaType == %i", PHAssetMediaType.image.rawValue))
        }

        if tblAccount.autoUploadVideo {
            mediaPredicates.append(NSPredicate(format: "mediaType == %i", PHAssetMediaType.video.rawValue))
        }

        if let autoUploadSinceDate = tblAccount.autoUploadSinceDate {
            datePredicates.append(NSPredicate(format: "creationDate > %@", autoUploadSinceDate as NSDate))
        } else if let lastDate = await self.database.fetchLastAutoUploadedDateAsync(account: tblAccount.account, autoUploadServerUrlBase: autoUploadServerUrlBase) {
            datePredicates.append(NSPredicate(format: "creationDate > %@", lastDate as NSDate))
        }

        fetchOptions.predicate = {
            switch (mediaPredicates.isEmpty, datePredicates.isEmpty) {
            case (false, false):
                return NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSCompoundPredicate(orPredicateWithSubpredicates: mediaPredicates),
                    NSCompoundPredicate(andPredicateWithSubpredicates: datePredicates)
                ])
            case (false, true):
                return NSCompoundPredicate(orPredicateWithSubpredicates: mediaPredicates)
            case (true, false):
                return NSCompoundPredicate(andPredicateWithSubpredicates: datePredicates)
            default:
                return nil
            }
        }()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let collections: [PHAssetCollection] = {
            if assetCollections.isEmpty {
                let fetched = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
                return fetched.firstObject.map { [$0] } ?? []
            } else {
                return assetCollections
            }
        }()

        guard !collections.isEmpty else {
             return ([], [], [])
        }

        var allAssets: [PHAsset] = []
        var allFileNames: [String] = []
        var allSources: [PHAssetCollection] = []

        for collection in collections {
            let result = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            let assetsInColl = result.objects(at: IndexSet(0..<result.count))

            for asset in assetsInColl {
                allAssets.append(asset)
                let date = asset.creationDate ?? Date()
                let fn = NCUtilityFileSystem().createFileName(asset.originalFilename, fileDate: date, fileType: asset.mediaType)
                allFileNames.append(fn)
                allSources.append(collection)
            }
        }

        // Dedup while keeping the first-seen source collection
        var seen = Set<String>()
        var finalAssets: [PHAsset] = []
        var finalNames: [String] = []
        var finalSources: [PHAssetCollection] = []

        for i in 0..<allAssets.count {
            let id = allAssets[i].localIdentifier
            if !seen.contains(id) {
                seen.insert(id)
                finalAssets.append(allAssets[i])
                finalNames.append(allFileNames[i])
                finalSources.append(allSources[i])
            }
        }

        return (finalAssets, finalNames, finalSources)
    }

    // MARK: -

    // Executes the background synchronization flow for Auto Upload.
    //
    // The function:
    // - discovers new Auto Upload items,
    // - fetches pending metadata,
    // - creates missing folders when required,
    // - checks remote existence,
    // - expands seeds into concrete metadata items,
    // - queues uploads sequentially.
    //
    // The flow cooperates with Swift task cancellation triggered by BGTask expiration.
    func autoUploadBackgroundSync() async {
        guard !Task.isCancelled else { return }

        // Discover new items for Auto Upload.
        let numAutoUpload = await initAutoUpload()
        nkLog(tag: self.global.logTagBgSync, emoji: .start, message: "Auto upload found \(numAutoUpload) new items")

        guard !Task.isCancelled else { return }

        // Fetch pending metadata.
        let metadatas = await NCManageDatabase.shared.getMetadataProcess()
        guard !metadatas.isEmpty, !Task.isCancelled else {
            return
        }

        // Create all pending Auto Upload folders (fail-fast).
        let pendingCreateFolders = metadatas.lazy.filter {
            $0.status == self.global.metadataStatusWaitCreateFolder &&
            $0.sessionSelector == self.global.selectorUploadAutoUpload
        }

        // Resolve capabilities once per account.
        let accounts = Array(Set(pendingCreateFolders.map { $0.account }))
        var capabilitiesByAccount: [String: NKCapabilities.Capabilities] = [:]

        for account in accounts {
            guard !Task.isCancelled else { return }

            let capabilities = await NKCapabilities.shared.getCapabilities(for: account)
            capabilitiesByAccount[account] = capabilities
        }

        for metadata in pendingCreateFolders {
            guard !Task.isCancelled else { return }

            // If server supports auto MKCOL (Nextcloud >= 33), skip manual folder creation.
            if let capabilities = capabilitiesByAccount[metadata.account] {
                let autoMkcol = capabilities.serverVersionMajor >= NCGlobal.shared.nextcloudVersion33
                if autoMkcol {
                    continue
                }
            }

            let err = await NCNetworking.shared.createFolderForAutoUpload(
                serverUrlFileName: metadata.serverUrlFileName,
                account: metadata.account
            )

            if err != .success {
                nkLog(
                    tag: self.global.logTagBgSync,
                    emoji: .error,
                    message: "Create folder '\(metadata.serverUrlFileName)' failed: \(err.errorCode) – aborting sync"
                )
                return
            }
        }

        // Compute available capacity.
        let downloading = metadatas.lazy.filter { $0.status == self.global.metadataStatusDownloading }.count
        let uploading = metadatas.lazy.filter { $0.status == self.global.metadataStatusUploading }.count
        let availableProcess = max(0, NCBrandOptions.shared.numMaximumProcess - (downloading + uploading))

        // Select Auto Upload candidates.
        let metadatasToUpload = Array(
            metadatas.lazy.filter {
                $0.status == self.global.metadataStatusWaitUpload &&
                $0.sessionSelector == self.global.selectorUploadAutoUpload &&
                $0.chunk == 0
            }
            .prefix(availableProcess)
        )

        let cameraRoll = NCCameraRoll()

        for metadata in metadatasToUpload {
            guard !Task.isCancelled else { return }

            // Check whether the file already exists remotely.
            let existsResult = await NCNetworking.shared.fileExists(
                serverUrlFileName: metadata.serverUrlFileName,
                account: metadata.account
            )

            if existsResult == .success {
                await NCManageDatabase.shared.deleteMetadataAsync(id: metadata.ocId)
                continue
            } else if existsResult.errorCode != 404 {
                continue
            }

            // Expand the seed into concrete metadata entries (for example, Live Photo pairs).
            let extractedMetadatas = await cameraRoll.extractCameraRoll(from: metadata)

            guard !Task.isCancelled else { return }

            for extractedMetadata in extractedMetadatas {
                guard !Task.isCancelled else { return }

                let err = await NCNetworking.shared.uploadFileInBackground(
                    metadata: extractedMetadata.detachedCopy()
                )

                if err == .success {
                    nkLog(
                        tag: self.global.logTagBgSync,
                        message: "In queued upload \(extractedMetadata.fileName) -> \(extractedMetadata.serverUrl)"
                    )
                } else {
                    nkLog(
                        tag: self.global.logTagBgSync,
                        emoji: .error,
                        message: "Upload failed \(extractedMetadata.fileName) -> \(extractedMetadata.serverUrl) [\(err.errorDescription)]"
                    )
                }
            }
        }
    }
}
