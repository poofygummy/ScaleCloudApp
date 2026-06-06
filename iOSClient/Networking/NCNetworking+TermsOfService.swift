// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2025 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import UIKit
import SwiftUI
import ScaleCloudKit

extension NCNetworking {
    @MainActor
    func termsOfService(account: String) async {
        let capabilities = await SCKCapabilities.shared.getCapabilities(for: account)
        guard capabilities.termsOfService,
              let groupDefaults = UserDefaults(suiteName: ScaleCloudKit.shared.nkCommonInstance.groupIdentifier),
              let controller = SceneManager.shared.getControllers().first(where: { $0.account == account }),
              controller.presentedViewController as? UIHostingController<NCTermOfServiceModelView> == nil
        else {
            return
        }

        var tosArray = groupDefaults.array(forKey: ScaleCloudKit.shared.nkCommonInstance.groupDefaultsToS) as? [String] ?? []
        let options = SCKRequestOptions(checkInterceptor: false)

        let resultsGetToS = await ScaleCloudKit.shared.getTermsOfServiceAsync(account: account, options: options, taskHandler: { task in
            Task {
                let identifier = await NCNetworking.shared.networkingTasks.createIdentifier(account: account,
                                                                                            name: "getTermsOfService")
                await NCNetworking.shared.networkingTasks.track(identifier: identifier, task: task)
            }
        })
        guard resultsGetToS.error == .success, let tos = resultsGetToS.tos, !tos.hasUserSigned() else {
            tosArray.removeAll { $0 == account }
            groupDefaults.set(tosArray, forKey: ScaleCloudKit.shared.nkCommonInstance.groupDefaultsToS)
            return
        }

        let termOfServiceModel = NCTermOfServiceModel(controller: controller, tos: tos)
        let termOfServiceView = NCTermOfServiceModelView(model: termOfServiceModel)
        let termOfServiceController = UIHostingController(rootView: termOfServiceView)

        controller.present(termOfServiceController, animated: true)
    }

    func signTermsOfService(account: String, termId: Int) async -> SCKError? {
        let capabilities = await SCKCapabilities.shared.getCapabilities(for: account)
        guard capabilities.termsOfService,
              let groupDefaults = UserDefaults(suiteName: ScaleCloudKit.shared.nkCommonInstance.groupIdentifier)
        else {
            return nil
        }
        var tosArray = groupDefaults.array(forKey: ScaleCloudKit.shared.nkCommonInstance.groupDefaultsToS) as? [String] ?? []
        let options = SCKRequestOptions(checkInterceptor: false)

        let resultsSignToS = await  ScaleCloudKit.shared.signTermsOfServiceAsync(termId: "\(termId)", account: account, options: options) { task in
            Task {
                let identifier = await NCNetworking.shared.networkingTasks.createIdentifier(account: account,
                                                                                            path: "\(termId)",
                                                                                            name: "signTermsOfService")
                await NCNetworking.shared.networkingTasks.track(identifier: identifier, task: task)
            }
        }
        if resultsSignToS.error == .success {
            tosArray.removeAll { $0 == account }
            groupDefaults.set(tosArray, forKey: ScaleCloudKit.shared.nkCommonInstance.groupDefaultsToS)
        }

        return resultsSignToS.error
    }
}
