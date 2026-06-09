// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// withscalecloud

/// =============================================================================
/// WHAT THIS FILE DOES (for people learning the code)
/// =============================================================================
///
/// This file contains the "brain" (ViewModel) for the screen where a ScaleCloud
/// user can manage the list of folders they want the app to automatically watch
/// for new downloaded files.
///
/// Why does this exist?
/// - On iOS, apps cannot freely access folders belonging to other apps.
/// - The only safe way for the user to give us access to a folder is by picking
///   it themselves using the system document picker.
/// - When they pick a folder, iOS gives us a "security-scoped bookmark" (a special
///   token that lets us access that folder later).
/// - We need to save those tokens, load them later, turn them back into real
///   folder URLs, and let the user add/remove them.
///
/// This model handles all of that logic so the SwiftUI view can stay relatively simple.
///
/// It is only shown for accounts that pass the isToCsaCloud check (ScaleCloud accounts).
///
/// =============================================================================

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// This is a SwiftUI ViewModel (@ObservableObject) that manages the list of
/// "Watched Download Folders" for a single ScaleCloud account.
///
/// Its job is to:
/// - Load the list of folders the user previously chose
/// - Let the user add new folders (via the Files app picker)
/// - Let the user remove folders
/// - Handle all the complicated iOS security rules around accessing folders the user picked
///
/// This model is only used by ScaleCloudWatchedFoldersView.swift.
@MainActor
class ScaleCloudWatchedFoldersModel: ObservableObject {

    // The list of folders we are currently watching.
    // @Published means the SwiftUI view will automatically refresh when this array changes.
    @Published var watchedFolders: [URL] = []

    @Published var isLoading = false

    // The account this list belongs to (e.g. "user@cloud.example.com")
    private let account: String

    // We use NCPreferences to load and save the bookmarks persistently.
    private let preferences = NCPreferences()

    init(account: String) {
        self.account = account
        // As soon as the model is created, load whatever folders the user has already saved.
        loadBookmarks()
    }

    /// Loads the saved bookmarks from storage and turns them into real folder URLs we can use.
    func loadBookmarks() {
        // Ask NCPreferences for the raw bookmark Data we previously saved for this account.
        let bookmarkDatas = preferences.getScaleCloudWatchedDownloadBookmarks(account: account)
        var resolved: [URL] = []
        var validDatas: [Data] = []

        for data in bookmarkDatas {
            var isStale = false

            // Turn the saved bookmark Data back into a real URL.
            // On iOS, security scope is automatically included for URLs from UIDocumentPickerViewController.
            // We use empty options [] instead of .withSecurityScope (which is macOS-only).
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: [],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale),
               !isStale {
                guard url.startAccessingSecurityScopedResource() else { continue }
                resolved.append(url)
                validDatas.append(data)
            }
        }

        // Update the published property → the UI will refresh.
        watchedFolders = resolved
        // Update the stored bookmarks if any were stale
        if validDatas.count != bookmarkDatas.count {
            preferences.setScaleCloudWatchedDownloadBookmarks(account: account, bookmarks: validDatas)
        }
    }

    /// Called when the user picks a new folder using the document picker.
    /// We must do the "security scoped bookmark dance":
    /// 1. Start accessing the folder right now
    /// 2. Ask iOS to create a bookmark token we can save
    /// 3. Save that token using NCPreferences
    /// 4. Refresh the list so the UI updates
    func addFolder(url: URL) {
        // Ask iOS for permission to access this folder right now.
        // If this returns false, we are not allowed to read it.
        guard url.startAccessingSecurityScopedResource() else { return }

        // This guarantees that no matter what happens (success or error),
        // we will release the access when this function ends.
        defer {
            url.stopAccessingSecurityScopedResource()
        }

        do {
            // Ask iOS to create a bookmark token for this folder.
            // On iOS, security scope is automatically included for URLs from UIDocumentPickerViewController.
            // We use empty options [] instead of .withSecurityScope (which is macOS-only).
            let bookmarkData = try url.bookmarkData(options: [],
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil)

            // Load the current list of bookmarks we already have for this account
            var current = preferences.getScaleCloudWatchedDownloadBookmarks(account: account)

            // Add the new one
            current.append(bookmarkData)

            // Save the updated list back to persistent storage
            preferences.setScaleCloudWatchedDownloadBookmarks(account: account, bookmarks: current)

            // Refresh the list so the UI shows the newly added folder
            loadBookmarks()
        } catch {
            print("Failed to create bookmark: \(error)")
        }
    }

    /// Removes one or more folders from the watched list.
    /// This just removes the bookmark data from storage — it does not delete anything on disk.
    func removeFolder(at offsets: IndexSet) {
        var current = preferences.getScaleCloudWatchedDownloadBookmarks(account: account)

        for index in offsets.reversed() {
            if index < watchedFolders.count {
                let url = watchedFolders[index]
                url.stopAccessingSecurityScopedResource() // Stop accessing the folder if we were watching it
                watchedFolders.remove(at: index)
                current.remove(at: index)
            }
        }

        preferences.setScaleCloudWatchedDownloadBookmarks(account: account, bookmarks: current)
    }

    // Note: We don't need a deinit to call stopAccessingSecurityScopedResource()
    // because iOS automatically releases security-scoped resources when the URL is deallocated.
    // Attempting to access @MainActor-isolated 'watchedFolders' from deinit would cause a
    // compilation error since deinit can run on any thread.
}
