//
//  NCPermissions.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 05/06/24.
// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2024 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

import UIKit
import Foundation
import ScaleCloudKit

enum NCSharePermissions {

    static let permissionMinFileShare: Int = 1
    static let permissionMaxFileShare: Int = 19
    static let permissionMinFolderShare: Int = 1
    static let permissionMaxFolderShare: Int = 31
    static let permissionDefaultFileRemoteShareNoSupportShareOption: Int = 3
    static let permissionDefaultFolderRemoteShareNoSupportShareOption: Int = 15

    // Additional attributes. This also includes the permission to download.
    // Check https://docs.nextcloud.com/server/latest/developer_manual/client_apis/OCS/ocs-share-api.html#share-attributes
    static let permissionDownloadShare: Int = 0

    static func hasPermissionToRead(_ permission: Int) -> Bool {
        return ((permission & SCKShare.Permission.read.rawValue) > 0)
    }

    static func hasPermissionToDelete(_ permission: Int) -> Bool {
        return ((permission & SCKShare.Permission.delete.rawValue) > 0)
    }

    static func hasPermissionToCreate(_ permission: Int) -> Bool {
        return ((permission & SCKShare.Permission.create.rawValue) > 0)
    }

    static func hasPermissionToEdit(_ permission: Int) -> Bool {
        return ((permission & SCKShare.Permission.update.rawValue) > 0)
    }

    static func hasPermissionToShare(_ permission: Int) -> Bool {
        return ((permission & SCKShare.Permission.share.rawValue) > 0)
    }

    static func isAnyPermissionToEdit(_ permission: Int) -> Bool {
        let canCreate = hasPermissionToCreate(permission)
        let canEdit = hasPermissionToEdit(permission)
        let canDelete = hasPermissionToDelete(permission)
        return canCreate || canEdit || canDelete
    }

    /// "Can edit" means it has can read, create, edit, and delete.
    static func canEdit(_ permission: Int, isDirectory: Bool) -> Bool {
        let canRead   = hasPermissionToRead(permission)
        let canCreate = isDirectory ? hasPermissionToCreate(permission) : true
        let canEdit = hasPermissionToEdit(permission)
        let canDelete = isDirectory ? hasPermissionToDelete(permission) : true
        return canCreate && canEdit && canRead && canDelete
    }

    /// Read permission is always true for a share, hence why it's not here.
    static func getPermissionValue(canRead: Bool = true, canCreate: Bool, canEdit: Bool, canDelete: Bool, canShare: Bool, isDirectory: Bool) -> Int {
        var permission = 0

        if canRead {
            permission = permission + SCKShare.Permission.read.rawValue
        }

        if canCreate && isDirectory {
            permission = permission + SCKShare.Permission.create.rawValue
        }
        if canEdit {
            permission = permission + SCKShare.Permission.update.rawValue
        }
        if canDelete && isDirectory {
            permission = permission + SCKShare.Permission.delete.rawValue
        }
        if canShare {
            permission = permission + SCKShare.Permission.share.rawValue
        }

        return permission
    }
}
