// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// withscalecloud

import Foundation
import NextcloudKit

/// This enum acts as a container (namespace) for all logic related to scanning
/// user-chosen "Download" folders for new files on ScaleCloud accounts.
///
/// The goal is: When the normal photo auto-upload detects new pictures for a
/// ScaleCloud account, we also want to check if the user has any "watched"
/// folders (that they manually selected) and upload new files from those too.
enum ScaleCloudDownloadsHelper {

    /// Main entry point.
    /// This function is called from NCAutoUpload after it has finished looking
    /// for new photos for a ScaleCloud account.
    ///
    /// It receives a list of security-scoped bookmarks (the folders the user
    /// previously chose via the "Watched Download Folders" screen).
    ///
    /// For each bookmarked folder:
    /// - We resolve the bookmark back into a real folder URL
    /// - We check if we still have permission to access it
    /// - We look for files that were modified since the last time we scanned this folder
    /// - Any new files get passed to enqueueLocalFileForUpload()
    static func scanAndEnqueueDownloads(for tblAccount: tableAccount, bookmarks: [Data]) async {
        let fileManager = FileManager.default

        // Go through every folder the user has told us to watch
        for bookmarkData in bookmarks {

            // Turn the saved bookmark Data back into a real URL we can use.
            // The "withSecurityScope" option is required so iOS knows we have
            // permission to access this folder later.
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmarkData,
                                     options: .withSecurityScope,
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &isStale),
                  !isStale else {
                // Bookmark is invalid or too old → skip this folder
                continue
            }

            // This is required by iOS. We must explicitly "start accessing"
            // a security-scoped URL before we can read its contents.
            // The 'defer' below guarantees we will call stopAccessing later,
            // even if something goes wrong.
            guard url.startAccessingSecurityScopedResource() else {
                continue
            }
            defer {
                url.stopAccessingSecurityScopedResource()
            }

            // Make sure the folder actually still exists on disk
            guard fileManager.fileExists(atPath: url.path) else { continue }

            // Each watched folder has its own "last time we scanned it" timestamp.
            // We store this in UserDefaults using a key that includes both
            // the account and the folder path.
            let lastScanKey = "ScaleCloud.LastDownloadsScan.\(tblAccount.account).\(url.path)"
            let lastScanDate = UserDefaults.standard.object(forKey: lastScanKey) as? Date ?? Date.distantPast

            do {
                // Get all files in this folder (we skip hidden files)
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )

                var newestDate = lastScanDate

                for fileURL in contents {
                    // Only look at actual files (not subfolders)
                    guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                          resourceValues.isRegularFile == true,
                          let modDate = resourceValues.contentModificationDate,
                          // Only care about files that changed since our last scan
                          modDate > lastScanDate else { continue }

                    // We found a new file → send it to be prepared for upload
                    await enqueueLocalFileForUpload(fileURL, account: tblAccount)

                    // Keep track of the newest modification date we saw
                    if modDate > newestDate {
                        newestDate = modDate
                    }
                }

                // Remember when we finished scanning this folder so next time
                // we only look at files newer than this moment.
                UserDefaults.standard.set(newestDate, forKey: lastScanKey)

            } catch {
                nkLog(error: "ScaleCloudDownloadsHelper: Failed to scan watched folder: \(error)")
            }
        }
    }

    private static func enqueueLocalFileForUpload(_ localURL: URL, account: tableAccount) async {
        let fileSystem = NCUtilityFileSystem()
        let database = NCManageDatabase.shared
        let networking = NCNetworking.shared

        guard let session = NCSession.shared.getSession(account: account.account) else {
            nkLog(error: "ScaleCloudDownloadsHelper: No session for account \(account.account)")
            return
        }

        // Hardcoded target for downloads on ScaleCloud accounts.
        // We respect the account's subfolder setting and always use year-based folders
        // (matching the behavior used for photos and screenshots).
        let downloadsRemoteBase = "/Letöltések"

        var targetServerUrl = downloadsRemoteBase

        if account.autoUploadCreateSubfolder {
            let date = (try? localURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let year = Calendar.current.component(.year, from: date)
            targetServerUrl = downloadsRemoteBase + "/\(year)"
        }

        // Create a unique ocId for this upload item
        let ocId = UUID().uuidString

        // Create metadata for the local file
        let metadata = await NCManageDatabaseCreateMetadata().createMetadataAsync(
            fileName: localURL.lastPathComponent,
            ocId: ocId,
            serverUrl: targetServerUrl,
            url: localURL.path,
            session: session,
            sceneIdentifier: nil
        )

        // Copy the file to the provider storage (required for uploads)
        let fileNamePath = fileSystem.getDirectoryProviderStorageOcId(ocId, fileName: metadata.fileNameView, userId: account.userId, urlBase: account.urlBase)
        guard fileSystem.copyFile(atPath: localURL.path, toPath: fileNamePath) else {
            nkLog(error: "ScaleCloudDownloadsHelper: Failed to copy file to provider storage: \(localURL.lastPathComponent)")
            return
        }

        // Configure for background auto-upload
        metadata.session = networking.sessionUploadBackground
        metadata.sessionSelector = NCGlobal.shared.selectorUploadAutoUpload
        metadata.status = NCGlobal.shared.metadataStatusWaitUpload
        metadata.sessionDate = Date()
        metadata.size = Int64((try? localURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)

        // Optional: mark it as coming from ScaleCloud downloads (for future filtering/logging)
        // metadata.add(.scaleCloudDownload) or similar if we add a tag later

        await database.addMetadatasAsync([metadata])

        nkLog(debug: "ScaleCloudDownloadsHelper: Queued download file: \(localURL.lastPathComponent)")
    }

}
