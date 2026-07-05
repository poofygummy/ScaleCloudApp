// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2017 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import UIKit
import RealmSwift
import ScaleCloudKit
import CoreMedia
import Photos
import CommonCrypto

protocol DateCompareable {
    var dateKey: Date { get }
}

final class NCManageDatabase: @unchecked Sendable {
    static let shared = NCManageDatabase()

    internal let core: NCManageDatabaseCore
    internal let utilityFileSystem = NCUtilityFileSystem()

    init() {
        let dirGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NCBrandOptions.shared.capabilitiesGroup)
        let bundleUrl: URL = Bundle.main.bundleURL
        let bundlePathExtension: String = bundleUrl.pathExtension
        let isAppex: Bool = bundlePathExtension == "appex"

        self.core = NCManageDatabaseCore()

        // Disable file protection for directory DB
        if let folderPathURL = dirGroup?.appendingPathComponent(NCGlobal.shared.appDatabaseNextcloud) {
            let folderPath = folderPathURL.path
            do {
                try FileManager.default.setAttributes([FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: folderPath)
            } catch {
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .error, message: "Realm directory setAttributes error: \(error)")
            }
        }

        // Open Realm
        if isAppex {
            self.openRealmAppex()
        }
    }

    // MARK: -

    /// Deletes all Realm database files at the given URL.
    /// Safe to call even if files don't exist.
    private func deleteRealmFiles(at realmURL: URL) {
        let filesToDelete = [
            realmURL,
            realmURL.appendingPathExtension("lock"),
            realmURL.appendingPathExtension("note"),
            realmURL.appendingPathExtension("management")
        ]
        for file in filesToDelete {
            try? FileManager.default.removeItem(at: file)
        }
        nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .warning, message: "Realm files deleted at: \(realmURL.path)")
    }

    func openRealm() {
        nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "openRealm: start, appSchema=\(databaseSchemaVersion)")

        let dirGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NCBrandOptions.shared.capabilitiesGroup)
        let databaseFileUrl = dirGroup?.appendingPathComponent(NCGlobal.shared.appDatabaseNextcloud + "/" + databaseName)

        guard let realmURL = databaseFileUrl else {
            nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .error, message: "openRealm: app group container URL is nil — cannot open Realm")
            return
        }
        nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "openRealm: path=\(realmURL.path)")

        // Any schema mismatch (higher OR lower than expected), corruption, or unreadable file:
        // wipe the DB proactively. Realm fires an uncatchable preconditionFailure on mismatch,
        // so we must delete before calling Realm.init. Data loss is acceptable — fresh install.
        if FileManager.default.fileExists(atPath: realmURL.path) {
            do {
                let onDiskVersion = try schemaVersionAtURL(realmURL)
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "openRealm: on-disk schema v\(onDiskVersion)")
                if onDiskVersion != databaseSchemaVersion {
                    nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .warning,
                          message: "openRealm: schema mismatch (disk=\(onDiskVersion) app=\(databaseSchemaVersion)) — wiping DB")
                    deleteRealmFiles(at: realmURL)
                }
            } catch {
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .warning,
                      message: "openRealm: schemaVersionAtURL failed (\(error)) — wiping DB")
                deleteRealmFiles(at: realmURL)
            }
        } else {
            nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "openRealm: no existing DB file, will create fresh")
        }

        // No migration block needed: any old DB was wiped above.
        let configuration = Realm.Configuration(fileURL: realmURL,
                                                schemaVersion: databaseSchemaVersion)
        Realm.Configuration.defaultConfiguration = configuration
        nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "openRealm: calling Realm(configuration:)")

        do {
            let realm = try Realm(configuration: configuration)
            if let url = realm.configuration.fileURL {
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "Realm is located at: \(url.path)", consoleOnly: true)
            }
        } catch let error {
            nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .error, message: "openRealm: Realm(configuration:) threw: \(error) — wiping and retrying")
            deleteRealmFiles(at: realmURL)
            do {
                let realm = try Realm()
                if let url = realm.configuration.fileURL {
                    nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "Realm is located at: \(url.path)", consoleOnly: true)
                }
            } catch {
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .error, message: "openRealm: retry also failed: \(error)")
            }
        }
        nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "openRealm: done")
    }

    @discardableResult
    func openRealmBackground() -> Bool {
        let dirGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NCBrandOptions.shared.capabilitiesGroup)
        guard let realmURL = dirGroup?.appendingPathComponent(NCGlobal.shared.appDatabaseNextcloud + "/" + databaseName) else {
            nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .error, message: "openRealmBackground: app group container URL is nil")
            return false
        }

        // Wipe on any schema mismatch or corruption, same policy as openRealm().
        if FileManager.default.fileExists(atPath: realmURL.path) {
            if let onDiskVersion = try? schemaVersionAtURL(realmURL), onDiskVersion != databaseSchemaVersion {
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .warning,
                      message: "openRealmBackground: schema mismatch (disk=\(onDiskVersion) app=\(databaseSchemaVersion)) — wiping DB")
                deleteRealmFiles(at: realmURL)
            } else if (try? schemaVersionAtURL(realmURL)) == nil {
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .warning,
                      message: "openRealmBackground: schemaVersionAtURL failed — wiping DB")
                deleteRealmFiles(at: realmURL)
            }
        }

        let configuration = Realm.Configuration(fileURL: realmURL,
                                                schemaVersion: databaseSchemaVersion)
        Realm.Configuration.defaultConfiguration = configuration

        do {
            let realm = try Realm(configuration: configuration)
            if let url = realm.configuration.fileURL {
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "Realm is located at: \(url.path)", consoleOnly: true)
            }
            return true
        } catch {
            nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .error, message: "openRealmBackground: Realm error: \(error)")
            return false
        }
    }

    private func openRealmAppex() {
        guard let dirGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NCBrandOptions.shared.capabilitiesGroup) else {
            return
        }
        let databaseFileUrl = dirGroup.appendingPathComponent(NCGlobal.shared.appDatabaseNextcloud + "/" + databaseName)

        // Wipe on any schema mismatch or corruption, same policy as openRealm().
        if FileManager.default.fileExists(atPath: databaseFileUrl.path) {
            do {
                let onDiskVersion = try schemaVersionAtURL(databaseFileUrl)
                if onDiskVersion != databaseSchemaVersion {
                    nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .warning,
                          message: "openRealmAppex: schema mismatch (disk=\(onDiskVersion) app=\(databaseSchemaVersion)) — wiping DB")
                    deleteRealmFiles(at: databaseFileUrl)
                }
            } catch {
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .warning,
                      message: "openRealmAppex: schemaVersionAtURL failed (\(error)) — wiping DB")
                deleteRealmFiles(at: databaseFileUrl)
            }
        }

        let objectTypes = [
            NCKeyValue.self, tableMetadata.self, tableMetadataTag.self, tableLocalFile.self,
            tableDirectory.self, tableTag.self, tableAccount.self,
            tableCapabilities.self, tableE2eEncryption.self, tableE2eEncryptionLock.self,
            tableE2eMetadata12.self, tableE2eMetadata.self, tableE2eUsers.self,
            tableE2eCounter.self, tableShare.self, tableChunk.self, tableAvatar.self,
            tableDashboardWidget.self, tableDashboardWidgetButton.self,
            NCDBLayoutForView.self, TableSecurityGuardDiagnostics.self, tableLivePhoto.self
        ]

        do {
            // No migration block needed: any old DB was wiped above.
            let runtimeCfg = Realm.Configuration(fileURL: databaseFileUrl,
                                                 schemaVersion: databaseSchemaVersion,
                                                 objectTypes: objectTypes)
            Realm.Configuration.defaultConfiguration = runtimeCfg

            let realm = try Realm(configuration: runtimeCfg)
            if let url = realm.configuration.fileURL {
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "Realm is located at: \(url.path)", consoleOnly: true)
            }
        } catch let error {
            nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .error, message: "openRealmAppex: Realm error: \(error)")
            isSuspendingDatabaseOperation = true
        }
    }

    // MARK: -

    /// Forces a Realm flush by refreshing the latest state from disk.
    /// This ensures that the current thread has the most recent version
    /// of all committed transactions.
    func flushRealmAsync() async {
        await withCheckedContinuation { continuation in
            core.realmQueue.async(qos: .utility) {
                autoreleasepool {
                    do {
                        let realm = try Realm()
                        _ = realm.refresh()
                    } catch {
                        nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .error, message: "Realm flush error: \(error)")
                    }
                    continuation.resume()
                }
            }
        }
    }

    func clearTable(_ table: Object.Type, account: String? = nil) {
        core.performRealmWrite { realm in
            var results: Results<Object>
            if let account = account {
                results = realm.objects(table).filter("account == %@", account)
            } else {
                results = realm.objects(table)
            }

            realm.delete(results)
        }
    }

    func clearTableAsync(_ table: Object.Type, account: String? = nil) async {
        await core.performRealmWriteAsync { realm in
            var results: Results<Object>
            if let account = account {
                results = realm.objects(table).filter("account == %@", account)
            } else {
                results = realm.objects(table)
            }

            realm.delete(results)
        }
    }

    func clearDBCache() {
        self.clearTable(tableAvatar.self)
        self.clearTable(tableChunk.self)
        self.clearTable(tableDirectory.self)
        self.clearTable(TableDownloadLimit.self)
        self.clearTable(tableExternalSites.self)
        self.clearTable(tableLivePhoto.self)
        self.clearTable(tableLocalFile.self)
        self.clearTable(tableMetadata.self)
        self.clearTable(tableMetadataTag.self)
        self.clearTable(tableRecommendedFiles.self)
        self.clearTable(tableShare.self)
        self.clearTable(tableTrash.self)
    }

    func clearDatabase(account: String) {
        self.clearTable(tableAccount.self, account: account)
        self.clearTable(tableActivity.self, account: account)
        self.clearTable(tableActivityLatestId.self, account: account)
        self.clearTable(tableActivityPreview.self, account: account)
        self.clearTable(tableActivitySubjectRich.self, account: account)
        self.clearTable(tableAutoUploadTransfer.self, account: account)
        self.clearTable(tableAvatar.self)
        self.clearTable(tableCapabilities.self, account: account)
        self.clearTable(tableChunk.self, account: account)
        self.clearTable(tableComments.self, account: account)
        self.clearTable(tableDashboardWidget.self, account: account)
        self.clearTable(tableDashboardWidgetButton.self, account: account)
        self.clearTable(tableDirectory.self, account: account)
        self.clearTable(TableDownloadLimit.self, account: account)
        self.clearTablesE2EE(account: account)
        self.clearTable(tableExternalSites.self, account: account)
        self.clearTable(tableGPS.self, account: nil)
        self.clearTable(TableGroupfolders.self, account: account)
        self.clearTable(TableGroupfoldersGroups.self, account: account)
        self.clearTable(NCDBLayoutForView.self, account: account)
        self.clearTable(tableLivePhoto.self, account: account)
        self.clearTable(tableLocalFile.self, account: account)
        self.clearTable(tableMetadata.self, account: account)
        self.clearTable(tableMetadataTag.self, account: account)
        self.clearTable(tableRecommendedFiles.self, account: account)
        self.clearTable(TableSecurityGuardDiagnostics.self, account: account)
        self.clearTable(tableShare.self, account: account)
        self.clearTable(tableTag.self, account: account)
        self.clearTable(tableTrash.self, account: account)
        self.clearTable(tableVideo.self, account: account)
        self.clearTable(NCKeyValue.self)
    }

    func clearTablesE2EE(account: String?) {
        self.clearTable(tableE2eEncryption.self, account: account)
        self.clearTable(tableE2eEncryptionLock.self, account: account)
        self.clearTable(tableE2eMetadata12.self, account: account)
        self.clearTable(tableE2eMetadata.self, account: account)
        self.clearTable(tableE2eUsers.self, account: account)
        self.clearTable(tableE2eCounter.self, account: account)
    }

    func cleanTablesOcIds(account: String, userId: String, urlBase: String) async {
        let metadatas = await getMetadatasAsync(predicate: NSPredicate(format: "account == %@", account))
        let directories = await getDirectoriesAsync(predicate: NSPredicate(format: "account == %@", account))
        let locals = await getTableLocalFilesAsync(predicate: NSPredicate(format: "account == %@", account))

        let metadatasOcIds = Set(metadatas.map { $0.ocId })
        let directoriesOcIds = Set(directories.map { $0.ocId })
        let localsOcIds = Set(locals.map { $0.ocId })

        let localMissingOcIds = localsOcIds.subtracting(metadatasOcIds)
        let directoriesMissingOcIds = directoriesOcIds.subtracting(metadatasOcIds)

        await withTaskGroup(of: Void.self) { group in
            for ocId in localMissingOcIds {
                group.addTask {
                    await self.deleteLocalFileAsync(id: ocId)
                    self.utilityFileSystem.removeFile(atPath: self.utilityFileSystem.getDirectoryProviderStorageOcId(ocId, userId: userId, urlBase: urlBase))
                }
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for ocId in directoriesMissingOcIds {
                group.addTask {
                    await self.deleteDirectoryOcIdAsync(ocId)
                }
            }
        }
    }

    func getThreadConfined(_ object: Object) -> Any {
        return ThreadSafeReference(to: object)
    }

    func sha256Hash(_ input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: -
    // MARK: Func T

    func fetchPagedResults<T: Object>(ofType type: T.Type, primaryKey: String, recordsPerPage: Int, pageNumber: Int, filter: NSPredicate? = nil, sortedByKeyPath: String? = nil, sortedAscending: Bool = true) -> Results<T>? {
        let startIndex = recordsPerPage * (pageNumber - 1)

        do {
            let realm = try Realm()
            var results = realm.objects(type)

            if let filter, let sortedByKeyPath {
                results = results.filter(filter).sorted(byKeyPath: sortedByKeyPath, ascending: sortedAscending)
            }

            guard startIndex < results.count else {
                return nil
            }
            let pagedResults = results.dropFirst(startIndex).prefix(recordsPerPage)
            let pagedResultsKeys = pagedResults.compactMap { $0.value(forKey: primaryKey) as? String }

            return realm.objects(type).filter("\(primaryKey) IN %@", Array(pagedResultsKeys))
        } catch {
            print("Error opening Realm: \(error)")
            return nil
        }
    }

    // MARK: -
    // MARK: Utils

    func sortedMetadata(layoutForView: NCDBLayoutForView?, account: String, metadatas: [tableMetadata]) async -> [tableMetadata] {
        let layout: NCDBLayoutForView = layoutForView ?? NCDBLayoutForView()
        let directoryOnTop = NCPreferences().getDirectoryOnTop(account: account)
        let favoriteOnTop = NCPreferences().getFavoriteOnTop(account: account)

        let sorted = metadatas.sorted { lhs, rhs in
            if favoriteOnTop, lhs.favorite != rhs.favorite {
                return lhs.favorite && !rhs.favorite
            }

            if directoryOnTop, lhs.directory != rhs.directory {
                return lhs.directory && !rhs.directory
            }

            switch layout.sort {
            case "fileName":
                let result = lhs.fileNameView.localizedStandardCompare(rhs.fileNameView)
                return layout.ascending ? result == .orderedAscending : result == .orderedDescending
            case "date":
                let lhsDate = lhs.date as Date
                let rhsDate = rhs.date as Date
                return layout.ascending ? lhsDate < rhsDate : lhsDate > rhsDate
            case "size":
                return layout.ascending ? lhs.size < rhs.size : lhs.size > rhs.size
            default:
                return true
            }
        }

        return Array(sorted)
    }

    /// Filters metadata entries and normalizes Live Photo relationships.
    ///
    /// Behavior:
    /// - Keeps image items as the canonical representation of a Live Photo.
    /// - Removes video items that belong to a Live Photo.
    /// - Clears broken Live Photo references on image items when the paired file is missing.
    /// - Removes orphan Live Photo video items when the paired image is missing.
    ///
    /// - Parameter metadatas: Detached metadata objects to normalize.
    /// - Returns: A cleaned array without duplicated or orphaned Live Photo video entries.
    func filterAndNormalizeLivePhotos(from metadatas: [tableMetadata]) -> [tableMetadata] {
        // Build a fast lookup set containing all available file identifiers.
        let allFileIds = Set(metadatas.map(\.fileId))

        return metadatas.compactMap { metadata in
            let linkedFileId = metadata.livePhotoFile
            let hasLivePhotoLink = !linkedFileId.isEmpty
            let linkedTargetExists = allFileIds.contains(linkedFileId)

            switch metadata.classFile {

            case SCKTypeClassFile.image.rawValue:
                // Keep the image as the canonical Live Photo item.
                // If the paired file is missing, clear the broken reference.
                if hasLivePhotoLink && !linkedTargetExists {
                    metadata.livePhotoFile = ""
                }
                return metadata

            case SCKTypeClassFile.video.rawValue:
                // Remove every Live Photo video:
                // - if the paired image exists, it is a duplicate representation
                // - if the paired image does not exist, it is an orphan and should not be shown
                if hasLivePhotoLink {
                    return nil
                }

                // Keep normal standalone videos.
                return metadata

            default:
                return metadata
            }
        }
    }

    func filterAndNormalizeLivePhotos(from metadatas: [tableMetadata], completion: @escaping ([tableMetadata]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let normalized = self.filterAndNormalizeLivePhotos(from: metadatas)
            completion(normalized)
        }
    }

    /// Compacts the Realm database by writing a compacted copy and replacing the original.
    /// Must be called when no Realm instances are open.
    func compactRealm() throws {
        nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "compactRealm: start, appSchema=\(databaseSchemaVersion)")

        guard let dirGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NCBrandOptions.shared.capabilitiesGroup) else {
            nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .error, message: "compactRealm: app group container URL is nil — skipping")
            return
        }
        let url = dirGroup.appendingPathComponent(NCGlobal.shared.appDatabaseNextcloud + "/" + databaseName)
        let fileManager = FileManager.default
        nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "compactRealm: path=\(url.path)")

        // Any schema mismatch or corruption: wipe and skip compaction.
        // openRealm() will create a fresh DB after maintenance completes.
        if fileManager.fileExists(atPath: url.path) {
            do {
                let onDiskVersion = try schemaVersionAtURL(url)
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "compactRealm: on-disk schema v\(onDiskVersion)")
                if onDiskVersion != databaseSchemaVersion {
                    nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .warning,
                          message: "compactRealm: schema mismatch (disk=\(onDiskVersion) app=\(databaseSchemaVersion)) — wiping DB, skipping compaction")
                    deleteRealmFiles(at: url)
                    return
                }
            } catch {
                nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .warning,
                      message: "compactRealm: schemaVersionAtURL failed (\(error)) — wiping DB, skipping compaction")
                deleteRealmFiles(at: url)
                return
            }
        } else {
            nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "compactRealm: no DB file, nothing to compact")
            return
        }

        let compactedURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".compact.realm")
        let backupURL = url.appendingPathExtension("bak")

        nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "compactRealm: opening Realm for compaction")
        // Write a compacted copy inside an autoreleasepool to ensure file handles are closed
        try autoreleasepool {
            // No migration block needed: schema matches exactly.
            let configuration = Realm.Configuration(fileURL: url,
                                                    schemaVersion: databaseSchemaVersion)
            Realm.Configuration.defaultConfiguration = configuration
            let realm = try Realm(configuration: configuration)
            nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "compactRealm: writing compacted copy")
            try realm.writeCopy(toFile: compactedURL)
        }

        // Atomic-ish swap: old → .bak, compacted → original path
        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: backupURL)
        }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.moveItem(at: url, to: backupURL)
        }
        try fileManager.moveItem(at: compactedURL, to: url)
        try? fileManager.removeItem(at: backupURL)
        nkLog(tag: NCGlobal.shared.logTagDatabase, emoji: .start, message: "compactRealm: done")
    }

    // MARK: -
    // MARK: SWIFTUI PREVIEW

    func createDBForPreview() async {
        // Account
        let account = "marinofaggiana https://cloudtest.nextcloud.com"
        let account2 = "mariorossi https://cloudtest.nextcloud.com"
        await addAccountAsync(account, urlBase: "https://cloudtest.nextcloud.com", user: "marinofaggiana", userId: "marinofaggiana", password: "password")
        await addAccountAsync(account2, urlBase: "https://cloudtest.nextcloud.com", user: "mariorossi", userId: "mariorossi", password: "password")
        let userProfile = SCKUserProfile()
        userProfile.displayName = "Marino Faggiana"
        userProfile.address = "Hirschstrasse 26, 70192 Stuttgart, Germany"
        userProfile.phone = "+49 (711) 252 428 - 90"
        userProfile.email = "cloudtest@nextcloud.com"
        await setAccountUserProfileAsync(account: account, userProfile: userProfile)
        let userProfile2 = SCKUserProfile()
        userProfile2.displayName = "Mario Rossi"
        userProfile2.email = "cloudtest@nextcloud.com"
        await setAccountUserProfileAsync(account: account2, userProfile: userProfile2)
    }
}
