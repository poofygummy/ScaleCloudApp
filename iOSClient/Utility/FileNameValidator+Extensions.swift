// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2024 Milen Pivchev
// SPDX-FileCopyrightText: 2024 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import ScaleCloudKit

extension FileNameValidator {
    static func checkFileName(_ filename: String, account: String?, capabilities: SCKCapabilities.Capabilities) -> SCKError? {
        let fileNameValidator = FileNameValidator(capabilities: capabilities)
        return fileNameValidator.checkFileName(filename)
    }

    static func checkFolderPath(_ folderPath: String, account: String?, capabilities: SCKCapabilities.Capabilities) -> Bool {
        let fileNameValidator = FileNameValidator(capabilities: capabilities)
        return fileNameValidator.checkFolderPath(folderPath)
    }
}
