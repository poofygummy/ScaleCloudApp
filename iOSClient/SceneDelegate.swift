// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2024 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

// withscalecloud

import Foundation
import UIKit
import ScaleCloudKit
import ScaleCloudRenew
import WidgetKit
import SwiftUI
import CoreLocation
import LucidBanner
import Photos

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var lucidBanner: LucidBanner?

    private let appDelegate = UIApplication.shared.delegate as? AppDelegate
    private var privacyProtectionWindow: UIWindow?
    private let global = NCGlobal.shared
    private let alreadyMigratedMultiDomains = UserDefaults.standard.bool(forKey: NCGlobal.shared.udMigrationMultiDomains)
    // Held as an instance property so the coordinator isn't deallocated before the
    // background debug-channel handoff thread completes (a local var in the closure
    // would be released the moment start() returns, making [weak self] capture nil).
    private var setupCoordinator: SetupCoordinator?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else {
            return
        }
        let versionApp = NCUtility().getVersionMaintenance()
        var lastVersion: String?

        lucidBanner = LucidBannerRegistry.shared.banner(for: windowScene)

        if let groupDefaults = UserDefaults(suiteName: NCBrandOptions.shared.capabilitiesGroup) {
            lastVersion = groupDefaults.string(forKey: NCGlobal.shared.udLastVersion)
            groupDefaults.set(versionApp, forKey: global.udLastVersion)
        }
        UserDefaults.standard.set(true, forKey: global.udMigrationMultiDomains)

        self.window = UIWindow(windowScene: windowScene)
        if !NCPreferences().appearanceAutomatic {
            self.window?.overrideUserInterfaceStyle = NCPreferences().appearanceInterfaceStyle
        }

        // in Debug write all UserDefaults.standard
        #if DEBUG
        print("UserDefaults: ---------------------------")
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            print("\(key) = \(value)")
        }
        print("UserDefaults Group: ---------------------")
        if let groupDefaults = UserDefaults(suiteName: NCBrandOptions.shared.capabilitiesGroup) {
            for (key, value) in groupDefaults.dictionaryRepresentation() {
                print("\(key) = \(value)")
            }
        }
        print("-----------------------------------------")
        #endif

        if lastVersion != versionApp {
            // Suspending Database for blocked the realm access (better be sure 100%)
            isSuspendingDatabaseOperation = true
            maintenanceMode = true
            window?.rootViewController = UIHostingController(rootView: Maintenance(onCompleted: {
                isSuspendingDatabaseOperation = false
                maintenanceMode = false
                // Start App
                self.startNextcloud(scene: scene, withActivateSceneForAccount: true)
            }))
            window?.makeKeyAndVisible()
        } else {
            self.startNextcloud(scene: scene, withActivateSceneForAccount: false)
        }
    }

    private func startNextcloud(scene: UIScene, withActivateSceneForAccount activateSceneForAccount: Bool) {
        // App not in background
        isAppInBackground = false
        // Open Realm
        NCManageDatabase.shared.openRealm()
        // Table account
        var activeTblAccount = NCManageDatabase.shared.getActiveTableAccount()

        // Try to restore accounts
        if activeTblAccount == nil {
            NCManageDatabase.shared.restoreTableAccountFromFile()
            activeTblAccount = NCManageDatabase.shared.getActiveTableAccount()
        }

        // Activation singleton
        _ = NCAppStateManager.shared
        _ = NCNetworking.shared
        _ = NCNetworkingProcess.shared

        if let activeTblAccount, !alreadyMigratedMultiDomains {
            //
            // Migration Multi Domains
            //
            window?.rootViewController = UIHostingController(rootView: MigrationMultiDomains(onCompleted: {
                //
                // Start Main
                //
                self.launchMainInterface(scene: scene, activeTblAccount: activeTblAccount, withActivateSceneForAccount: activateSceneForAccount)
            }))
            window?.makeKeyAndVisible()

        } else if let activeTblAccount {
            //
            // Start Main
            //
            self.launchMainInterface(scene: scene, activeTblAccount: activeTblAccount, withActivateSceneForAccount: activateSceneForAccount)

        } else {
            //
            // NO account found, start with the Login
            //
            NCPreferences().removeAll()

            if let bundleID = Bundle.main.bundleIdentifier {
                // ScaleCloud: preserve all signing-setup state across this wipe.
                // removePersistentDomain resets stale Nextcloud data from a previous
                // install, but must not destroy ScaleCloud keys written by phase 2.
                //
                // TODO: it is not fully understood why this wipe is needed on every
                // no-account launch. It was inherited from Nextcloud upstream and
                // preserved here. It does not appear to cause problems but the
                // exact scenario it guards against has not been identified.
                let ud = UserDefaults.standard
                let savedSignCredentialsInjected  = ud.signCredentialsInjected
                let savedAnisetteList              = ud.array(forKey: "menuAnisetteServersList") as? [String]
                let savedAnisetteURL               = ud.string(forKey: "menuAnisetteURL")
                let savedIpaSourceURL              = ud.string(forKey: "com.scalecloud.ipaSourceURL")
                let savedLastSetupDate             = ud.object(forKey: "com.scalecloud.lastSetupDate") as? Date
                let savedExeModTime                = ud.lastKnownExecutableModTime
                ud.removePersistentDomain(forName: bundleID)
                if savedSignCredentialsInjected       { ud.signCredentialsInjected = true }
                if let v = savedAnisetteList           { ud.set(v, forKey: "menuAnisetteServersList") }
                if let v = savedAnisetteURL            { ud.set(v, forKey: "menuAnisetteURL") }
                if let v = savedIpaSourceURL           { ud.set(v, forKey: "com.scalecloud.ipaSourceURL") }
                if let v = savedLastSetupDate          { ud.set(v, forKey: "com.scalecloud.lastSetupDate") }
                if let v = savedExeModTime             { ud.lastKnownExecutableModTime = v }
                ud.synchronize()
                print("SCALECLOUD_PERSISTENTDOMAIN_WIPED reason=no-account"); fflush(stdout)
            }

            if NCBrandOptions.shared.disable_intro {
                if let viewController = UIStoryboard(name: "NCLogin", bundle: nil).instantiateViewController(withIdentifier: "NCLogin") as? NCLogin {
                    let navigationController = UINavigationController(rootViewController: viewController)
                    window?.rootViewController = navigationController
                    window?.makeKeyAndVisible()
                    // ScaleCloud: on a fresh install the setup flow runs before any
                    // Nextcloud account exists. Present it over the login screen.
                    presentSetupFlowIfNeeded(controller: navigationController)
                }
            } else {
                if let navigationController = UIStoryboard(name: "NCIntro", bundle: nil).instantiateInitialViewController() as? UINavigationController {
                    window?.rootViewController = navigationController
                    window?.makeKeyAndVisible()
                    // ScaleCloud: on a fresh install the setup flow runs before any
                    // Nextcloud account exists. Present it over the intro screen.
                    presentSetupFlowIfNeeded(controller: navigationController)
                }
            }
        }
    }

    private func launchMainInterface(scene: UIScene,
                                     activeTblAccount: tableAccount,
                                     withActivateSceneForAccount activateSceneForAccount: Bool) {
        nkLog(debug: "Account active \(activeTblAccount.account)")

        // Networking Certificate
        NCNetworking.shared.activeAccountCertificate(account: activeTblAccount.account)

        Task {
            if let capabilities = await NCManageDatabase.shared.getCapabilities(account: activeTblAccount.account) {
                // set theming color
                NCBrandColor.shared.settingThemingColor(account: activeTblAccount.account, capabilities: capabilities)
                NotificationCenter.default.postOnMainThread(name: self.global.notificationCenterChangeTheming, userInfo: ["account": activeTblAccount.account])
            }

            // Start Networking Process
            await NCNetworkingProcess.shared.setCurrentAccount(activeTblAccount.account)
            await NCNetworkingProcess.shared.startTimer(interval: NCNetworkingProcess.shared.maxInterval)
        }

        // Set up networking session for all configured accounts
        for tblAccount in NCManageDatabase.shared.getAllTableAccount() {
            // Append account to ScaleCloudKit shared session
            SCKClient.shared.appendSession(account: tblAccount.account,
                                              urlBase: tblAccount.urlBase,
                                              user: tblAccount.user,
                                              userId: tblAccount.userId,
                                              password: NCPreferences().getPassword(account: tblAccount.account),
                                              userAgent: userAgent,
                                              httpMaximumConnectionsPerHost: NCBrandOptions.shared.httpMaximumConnectionsPerHost,
                                              httpMaximumConnectionsPerHostInDownload: NCBrandOptions.shared.httpMaximumConnectionsPerHostInDownload,
                                              httpMaximumConnectionsPerHostInUpload: NCBrandOptions.shared.httpMaximumConnectionsPerHostInUpload,
                                              groupIdentifier: NCBrandOptions.shared.capabilitiesGroup)

            // Perform async setup: restore capabilities and ensure file provider domain
            Task {
                await NCManageDatabase.shared.getCapabilities(account: tblAccount.account)
                try? await FileProviderDomain().ensureDomainRegistered(userId: tblAccount.userId, user: tblAccount.user, urlBase: tblAccount.urlBase)
            }

            // Append session to internal session manager
            NCSession.shared.appendSession(account: tblAccount.account, urlBase: tblAccount.urlBase, user: tblAccount.user, userId: tblAccount.userId)
        }

        // ScaleCloud: Automatically configure auto-upload for Camera/Screenshots on Tailscale accounts.
        // Mirrors Android's initSyncOperations → setupScaleCloudAutoSync (called on every app launch
        // after permission check, but the function itself is idempotent).
        if PHPhotoLibrary.authorizationStatus() == .authorized {
            setupScaleCloudAutoSync()
        }

        // Load Main.storyboard
        if let controller = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController() as? NCMainTabBarController {
            SceneManager.shared.register(scene: scene, withRootViewController: controller)
            // Set the ACCOUNT
            controller.account = activeTblAccount.account
            //
            window?.rootViewController = controller
            window?.makeKeyAndVisible()
            //
            if activateSceneForAccount {
                self.activateSceneForAccount(scene, account: activeTblAccount.account, controller: controller)
            } else {
                // Even when not activating the full scene (normal cold launch),
                // we still need to run the injection flow if a debugger is attached
                // or credentials are missing. presentSetupFlowIfNeeded has all the
                // right guards inside (coordinator-alive check, signCredentialsInjected check).
                self.presentSetupFlowIfNeeded(controller: controller)
            }
        }

        // Clean orphaned FP Domains
        Task {
            await FileProviderDomain().cleanOrphanedFileProviderDomains()
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }

        LucidBannerRegistry.shared.remove(for: windowScene)
        lucidBanner = nil

        print("[DEBUG] Scene did disconnect")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        hidePrivacyProtectionWindow()

        if let rootHostingController = scene.rootHostingController() {
            if rootHostingController.anyRootView is Maintenance {
                return
            }
        }
        let session = SceneManager.shared.getSession(scene: scene)
        let controller = SceneManager.shared.getController(scene: scene)

        activateSceneForAccount(scene, account: session.account, controller: controller)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        hidePrivacyProtectionWindow()

        if !SCKClient.shared.isNetworkReachable(),
           let windowScenee = SceneManager.shared.getWindow(scene: scene)?.windowScene {
            Task {
                await showWarningBanner(windowScene: windowScenee,
                                        subtitle: "_network_not_available_",
                                        systemImage: "wifi.exclamationmark.circle",
                                        imageAnimation: .bounce,
                                        errorCode: NSURLErrorNotConnectedToInternet)
            }
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        nkLog(debug: "Scene will resign active")

        let session = SceneManager.shared.getSession(scene: scene)
        guard !session.account.isEmpty else {
            return
        }

        if NCPreferences().privacyScreenEnabled {
            showPrivacyProtectionWindow()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        let app = UIApplication.shared
        var bgID: UIBackgroundTaskIdentifier = .invalid
        let isBackgroundRefreshStatus = (UIApplication.shared.backgroundRefreshStatus == .available)
        let session = SceneManager.shared.getSession(scene: scene)
        guard let tblAccount = NCManageDatabase.shared.getTableAccount(predicate: NSPredicate(format: "account == %@", session.account)) else {
            return
        }
        bgID = app.beginBackgroundTask(withName: "FlushBeforeSuspend") {
            app.endBackgroundTask(bgID); bgID = .invalid
        }

        Task {
            Task { @MainActor in
                if NCPreferences().presentPasscode {
                    showPrivacyProtectionWindow()
                }
            }
            defer {
                app.endBackgroundTask(bgID); bgID = .invalid
            }
            // Timeout auto
            let didFinish = await withTaskGroup(of: Bool.self) { group -> Bool in
                group.addTask {
                    // QUEUE
                    NCNetworking.shared.cancelAllQueue()
                    // FLUSH TRANSFERS SUCCESS
                    await NCNetworking.shared.metadataTranfersSuccess.flush()
                    // BACKUP
                    await NCManageDatabase.shared.backupTableAccountToFileAsync()
                    // LOG
                    nkLog(info: "Auto upload in background: \(tblAccount.autoUploadStart)")
                    nkLog(info: "Update in background: \(isBackgroundRefreshStatus)")
                    // LOCATION MANAGER
                    if CLLocationManager().authorizationStatus == .authorizedAlways && NCPreferences().location && tblAccount.autoUploadStart {
                        NCBackgroundLocationUploadManager.shared.start()
                    } else {
                        NCBackgroundLocationUploadManager.shared.stop()
                    }
                    // UPDATE SHARE GROUP ACCOUNTS
                    if let error = await NCAccount().updateAppsShareAccounts() {
                        nkLog(error: "Create Apps share accounts \(error.localizedDescription)")
                    }
                    return true
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 25_000_000_000)
                    return false
                }
                return await group.next() ?? false
            }

            if !didFinish {
                nkLog(debug: "Flush timed out, will continue next launch")
            }
        }
    }

    // MARK: - ScaleCloud Auto Sync Setup (mirrors Android MainApp.setupScaleCloudAutoSync)

    /// Configures auto-upload for Camera/Screenshots on Tailscale accounts.
    /// Called on every app launch (after photo permission check), but is idempotent.
    /// Mirrors the structure and intent of the Android implementation in MainApp.java.
    private func setupScaleCloudAutoSync() {
        let database = NCManageDatabase.shared
        let accounts = database.getAllTableAccount()

        var hasScaleCloudAccount = false
        for tblAccount in accounts {
            if isTailscaleAddress(tblAccount.urlBase) {
                hasScaleCloudAccount = true
                configureAutoUploadForAccount(tblAccount)
            }
        }

        // Ensure original filenames are preserved for ScaleCloud auto-uploads
        // (controlled by the existing user preference "Use original file name")
        if hasScaleCloudAccount {
            if !NCPreferences().fileNameOriginal {
                NCPreferences().fileNameOriginal = true
                nkLog(info: "ScaleCloud: Enabled 'Use original file name' preference for auto-uploads")
            }
        }
    }

    private func isTailscaleAddress(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host else { return false }
        if host.hasSuffix(".ts.net") { return true }
        if let ip = IPv4Address(host) {
            let bytes = ip.rawValue
            return bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127
        }
        return false
    }

    private func configureAutoUploadForAccount(_ tblAccount: tableAccount) {
        let cameraRemotePath = "/Saját Fényképek és Videók/"
        
        // 1. Extract values on the Main Thread (Thread A)
        let accountId = tblAccount.account
        let serverUrl = tblAccount.urlBase
        let username = tblAccount.user
        let userId = tblAccount.userId
        let currentFileName = tblAccount.autoUploadFileName
        // 2. Safely hand off pure RAM values to the background cooperative lane (Thread B)
        Task {
            await NCManageDatabase.shared.updateAccountPropertyAsync(\.autoUploadImage, value: true, account: accountId)
            await NCManageDatabase.shared.updateAccountPropertyAsync(\.autoUploadVideo, value: true, account: accountId)
            await NCManageDatabase.shared.updateAccountPropertyAsync(\.autoUploadWWAnPhoto, value: false, account: accountId)
            await NCManageDatabase.shared.updateAccountPropertyAsync(\.autoUploadWWAnVideo, value: false, account: accountId)
            await NCManageDatabase.shared.updateAccountPropertyAsync(\.autoUploadStart, value: true, account: accountId)
            await NCManageDatabase.shared.updateAccountPropertyAsync(\.autoUploadCreateSubfolder, value: true, account: accountId)
            await NCManageDatabase.shared.updateAccountPropertyAsync(\.autoUploadSubfolderGranularity, value: 0, account: accountId) // yearly

            
            let session = NCSession.Session(
                account: accountId,
                urlBase: serverUrl,
                user: username,
                userId: userId
            )
            await NCManageDatabase.shared.setAccountAutoUploadDirectoryAsync(cameraRemotePath, session: session)

            if currentFileName.isEmpty {
                await NCManageDatabase.shared.setAccountAutoUploadFileNameAsync(".")
            }
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        let scheme = url.scheme
        let action = url.host
        
        guard let controller = SceneManager.shared.getController(scene: scene) else { return }
        let versionApp = NCUtility().getVersionMaintenance()

        // Test version
        guard let groupDefaults = UserDefaults(suiteName: NCBrandOptions.shared.capabilitiesGroup),
              let lastVersion = groupDefaults.string(forKey: NCGlobal.shared.udLastVersion),
              lastVersion == versionApp else {
            return
        }

        func getMatchedAccount(user: String, url: String, account: String? = nil) async -> tableAccount? {
            let tblAccounts = await NCManageDatabase.shared.getAllTableAccountAsync()

            for tblAccount in tblAccounts {
                let host = URL(string: tblAccount.urlBase)?.host ?? ""

                if (account == tblAccount.account) || (url.contains(host) && user == tblAccount.userId) {
                    await NCAccount().changeAccount(tblAccount.account, userProfile: nil, controller: controller)
                    // wait switch account
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    return tblAccount
                }
            }
            return nil
        }

        /*
         Example: nextcloud://assistant/shared-text
         */

        if scheme == global.appScheme, action == "assistant", url.path == "/shared-text" {
            guard let text = NCAssistantSharedTextStore.loadAndClear() else {
                return
            }

            Task { @MainActor in
                let capabilities = await SCKCapabilities.shared.getCapabilities(for: controller.account)
                if capabilities.assistantEnabled {
                    let inputModel = NCAssistantInputModel(initialText: text)
                    let assistant = NCAssistant(assistantModel: NCAssistantModel(controller: controller, inputModel: inputModel), chatModel: NCAssistantChatModel(controller: controller, inputModel: inputModel), conversationsModel: NCAssistantChatConversationsModel(controller: controller))
                    let hostingController = UIHostingController(rootView: assistant)
                    controller.present(hostingController, animated: true, completion: nil)
                }
            }

            return
        }

        /*
         Example: nextcloud://open-action?action=create-voice-memo&&user=marinofaggiana&url=https://cloud.nextcloud.com
         */

        if scheme == global.appScheme && action == "open-action" {
            if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                let queryItems = urlComponents.queryItems
                guard let actionScheme = queryItems?.filter({ $0.name == "action" }).first?.value,
                      let userScheme = queryItems?.filter({ $0.name == "user" }).first?.value,
                      let urlScheme = queryItems?.filter({ $0.name == "url" }).first?.value else {
                    return
                }

                Task {
                    if await getMatchedAccount(user: userScheme, url: urlScheme) == nil {
                        let message = String(
                            format: NSLocalizedString("account_does_not_exist", comment: ""),
                            userScheme,
                        )

                        let alertController = UIAlertController(title: NSLocalizedString("_info_", comment: ""), message: message, preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("_ok_", comment: ""), style: .default, handler: { _ in }))

                        controller.present(alertController, animated: true, completion: { })
                        return
                    }

                    switch actionScheme {
                    case self.global.actionUploadAsset:
                        NCAskAuthorization().askAuthorizationPhotoLibrary(controller: controller) { hasPermission in
                            if hasPermission {
                                NCPhotosPickerViewController(controller: controller, maxSelectedAssets: 0, singleSelectedMode: false)
                            }
                        }
                    case self.global.actionScanDocument:
                        NCDocumentCamera.shared.openScannerDocument(viewController: controller)
                    case self.global.actionTextDocument:
                        let session = SceneManager.shared.getSession(scene: scene)
                        let capabilities = await SCKCapabilities.shared.getCapabilities(for: session.account)
                        guard let creator = capabilities.directEditingCreators.first(where: { $0.editor == "text" }) else {
                            return
                        }
                        let serverUrl = controller.currentServerUrl()
                        let fileName = await NCNetworking.shared.createFileName(fileNameBase: NSLocalizedString("_untitled_", comment: "") + "." + creator.ext, account: session.account, serverUrl: serverUrl)
                        let fileNamePath = NCUtilityFileSystem().getRelativeFilePath(String(describing: fileName), serverUrl: serverUrl, session: session)

                        await NCCreate().createDocument(controller: controller, fileNamePath: fileNamePath, fileName: String(describing: fileName), editorId: "text", creatorId: creator.identifier, templateId: "document", account: session.account)
                    case self.global.actionVoiceMemo:
                        NCAskAuthorization().askAuthorizationAudioRecord(controller: controller) { hasPermission in
                            if hasPermission {
                                if let viewController = UIStoryboard(name: "NCAudioRecorderViewController", bundle: nil).instantiateInitialViewController() as? NCAudioRecorderViewController {
                                    viewController.controller = controller
                                    viewController.modalTransitionStyle = .crossDissolve
                                    viewController.modalPresentationStyle = UIModalPresentationStyle.overCurrentContext
                                    controller.present(viewController, animated: true, completion: nil)
                                }
                            }
                        }
                    default:
                        print("No action")
                    }
                }
            }
        }

        /*
         Example: nextcloud://open-file?path=Talk/IMG_0000123.jpg&user=marinofaggiana&link=https://cloud.nextcloud.com/f/123
         */

        else if scheme == self.global.appScheme && action == "open-file" {
            if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                let queryItems = urlComponents.queryItems
                guard let userScheme = queryItems?.filter({ $0.name == "user" }).first?.value,
                      // let pathScheme = queryItems?.filter({ $0.name == "path" }).first?.value,
                      let linkScheme = queryItems?.filter({ $0.name == "link" }).first?.value else {
                    return
                }
                let domain = URL(string: linkScheme)?.host ?? ""
                let accountScheme = queryItems?.filter({ $0.name == "account" }).first?.value

                Task {
                    guard let tblAccount = await getMatchedAccount(user: userScheme, url: linkScheme, account: accountScheme) else {

                        let message = String(format: NSLocalizedString("_account_not_available_", comment: ""), userScheme, domain)
                        let alertController = UIAlertController(title: NSLocalizedString("_info_", comment: ""), message: message, preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("_ok_", comment: ""), style: .default, handler: { _ in }))

                        controller.present(alertController, animated: true)
                        return
                    }

                    let results = await SCKClient.shared.getFileFromFileIdAsync(link: linkScheme,
                                                                                   account: tblAccount.account)
                    if results.error == .success, let file = results.file {
                        let metadata = await NCManageDatabaseCreateMetadata().convertFileToMetadataAsync(file)
                        await NCManageDatabase.shared.addMetadataAsync(metadata)
                        if metadata.hasPreview {
                            let results = await SCKClient.shared.downloadPreviewAsync(fileId: metadata.fileId, etag: metadata.etag, account: metadata.account)
                            if results.error == .success,
                               let data = results.responseData?.data {
                                NCUtility().createImageFileFrom(data: data, metadata: metadata)
                            }
                        }
                        await NCNetworking.shared.openFileView(serverUrl: metadata.serverUrl,
                                                               metadata: metadata,
                                                               sceneIdentifier: controller.sceneIdentifier)
                    }
                }
            }

        /*
         Example: nextcloud://open-and-switch-account?user=marinofaggiana&url=https://cloud.nextcloud.com
         */

        } else if scheme == self.global.appScheme && action == "open-and-switch-account" {
            guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return
            }
            let queryItems = urlComponents.queryItems
            guard let userScheme = queryItems?.filter({ $0.name == "user" }).first?.value,
                  let urlScheme = queryItems?.filter({ $0.name == "url" }).first?.value else {
                return
            }

            Task {
                _ = await getMatchedAccount(user: userScheme, url: urlScheme)
            }
        } else if let action {
            if DeepLink(rawValue: action) != nil {
                NCDeepLinkHandler().parseDeepLink(url, controller: controller)
            }
        } else {
            scene.open(url, options: nil)
        }
    }
    
    private func showPrivacyProtectionWindow() {
        guard let windowScene = self.window?.windowScene else {
            return
        }

        self.privacyProtectionWindow = UIWindow(windowScene: windowScene)
        self.privacyProtectionWindow?.rootViewController = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()
        self.privacyProtectionWindow?.windowLevel = .alert + 1
        self.privacyProtectionWindow?.makeKeyAndVisible()
    }

    private func hidePrivacyProtectionWindow() {
        privacyProtectionWindow?.isHidden = true
        privacyProtectionWindow = nil
    }

    private func activateSceneForAccount(_ scene: UIScene,
                                         account: String,
                                         controller: NCMainTabBarController?) {
        guard !account.isEmpty else {
            return
        }

        if let window = SceneManager.shared.getWindow(scene: scene),
           let controller = SceneManager.shared.getController(scene: scene) {
            window.rootViewController = controller
            if NCPreferences().presentPasscode {
                NCPasscode.shared.presentPasscode(viewController: controller, delegate: self) {
                    NCPasscode.shared.enableTouchFaceID()
                }
            } else if NCPreferences().accountRequest {
                requestedAccount(controller: controller)
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            let num = await NCAutoUpload.shared.initAutoUpload()
            nkLog(start: "Auto upload with \(num) photo")

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await NCService().startRequestServicesServer(account: account, controller: controller)

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await NCNetworking.shared.verifyZombie()
        }

        NotificationCenter.default.postOnMainThread(name: global.notificationCenterRichdocumentGrabFocus)
    }
    
    // MARK: - Setup Flow
    
    /// Detects a fresh install or reinstall by comparing the main executable's
    /// current modification time against the last-seen value stored in UserDefaults.
    /// Every install physically re-extracts the app bundle, giving the executable a
    /// new mod time even if the binary is byte-identical. Normal subsequent launches
    /// never touch the file, so the timestamp is stable across ordinary runs.
    ///
    /// When a mismatch is found this function runs the full reset wipe (identical to
    /// `--scalecloud-reset`) and **immediately** repopulates `lastKnownExecutableModTime`
    /// with the current mod time so subsequent launches don't re-trigger the wipe.
    /// Setup credentials are NOT re-injected here — that is left to the normal
    /// `presentSetupFlowIfNeeded` flow that runs immediately after.
    ///
    /// - Returns: `true` if a fresh install was detected and the wipe was performed.
    @discardableResult
    private func detectFreshInstall() -> Bool {
        guard let execPath = Bundle.main.executablePath,
              let currentModTime = (try? FileManager.default.attributesOfItem(atPath: execPath))?[.modificationDate] as? Date else {
            print("[FreshInstall] WARNING: could not read executable mod time — skipping detection")
            return false
        }

        let ud = UserDefaults.standard
        let lastModTime = ud.lastKnownExecutableModTime

        guard lastModTime != currentModTime else {
            // Mod time unchanged — normal launch, nothing to do.
            return false
        }

        print("[FreshInstall] Executable mod time changed: \(lastModTime?.description ?? "(nil)") → \(currentModTime) — fresh install detected, running full wipe")
        fflush(stdout)

        // Full wipe — same as --scalecloud-reset.
        Keychain.shared.reset()
        NCPreferences().removeAll()
        if let bundleID = Bundle.main.bundleIdentifier {
            ud.removePersistentDomain(forName: bundleID)
        }
        let groupSuite = NCBrandOptions.shared.capabilitiesGroup
        if let groupDefaults = UserDefaults(suiteName: groupSuite) {
            groupDefaults.removePersistentDomain(forName: groupSuite)
            groupDefaults.synchronize()
        }
        // Wipe Realm accounts so the existing-account path is skipped on next launch.
        Task {
            await NCAccount().deleteAllAccounts()
            print("[FreshInstall] Realm accounts deleted"); fflush(stdout)
        }
        // Delete stale tsnet node state.
        let tsnetDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("tailscale", isDirectory: true)
        try? FileManager.default.removeItem(at: tsnetDir)

        // Repopulate mod time immediately so the next launch (before setup completes)
        // doesn't re-trigger the wipe.
        ud.lastKnownExecutableModTime = currentModTime
        ud.synchronize()

        print("[FreshInstall] Wipe complete, lastKnownExecutableModTime set to \(currentModTime)")
        fflush(stdout)
        return true
    }

    private func presentSetupFlowIfNeeded(controller: UIViewController) {
        print("SCALECLOUD_SETUP_FLOW_ENTERED"); fflush(stdout)
        // A coordinator is already alive (e.g. Phase 1 is blocking, or Phase 2 is
        // running validation). sceneWillEnterForeground can fire while injection is
        // in progress — don't create a second coordinator.
        if setupCoordinator != nil {
            return
        }

        // Detect fresh install / reinstall via executable mod time.
        // If detected, runs the full reset wipe before the credential checks below.
        detectFreshInstall()

        // If iloader launched us with --scalecloud-reset, unconditionally wipe keychain
        // and signCredentialsInjected before the guard below. This handles two cases:
        //   1. Reinstall: iOS preserves Keychain across app deletion, so hasValidSignCredentials()
        //      would return true and the guard would short-circuit without this.
        //   2. Apple ID change: the user entered new sign credentials in iloader; old ones
        //      must be overwritten rather than skipped.
        if CommandLine.arguments.contains("--scalecloud-reset") {
            print("[Setup] --scalecloud-reset: wiping all credentials and persistent domains")
            // Wipe all ScaleCloud signing credentials, signing materials, anisette,
            // provisioning profiles, and cert expiry.
            Keychain.shared.reset()
            // Wipe all Nextcloud keychain data (passwords, E2EE keys, push keys, etc.).
            NCPreferences().removeAll()
            // Wipe standard UserDefaults domain.
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            // Wipe app-group UserDefaults domain.
            let groupSuite = NCBrandOptions.shared.capabilitiesGroup
            if let groupDefaults = UserDefaults(suiteName: groupSuite) {
                groupDefaults.removePersistentDomain(forName: groupSuite)
                groupDefaults.synchronize()
            }
            UserDefaults.standard.synchronize()
            print("SCALECLOUD_PERSISTENTDOMAIN_WIPED reason=scalecloud-reset"); fflush(stdout)
            // 3. Wipe all Realm accounts so the existing-account path is not
            //    taken on the next launch (openRealm would find them otherwise).
            Task {
                await NCAccount().deleteAllAccounts()
                print("[Setup] --scalecloud-reset: Realm accounts deleted"); fflush(stdout)
            }

            // 4. Delete stale tsnet node state so a second proxy doesn't start
            //    from old Tailscale credentials and flood stdout during Phase 1.
            let tsnetDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!.appendingPathComponent("tailscale", isDirectory: true)
            try? FileManager.default.removeItem(at: tsnetDir)
            print("[Setup] --scalecloud-reset: tsnet state dir removed"); fflush(stdout)

            DispatchQueue.main.async {
                let alert = UIAlertController(title: "ScaleCloud Debug", message: "UserDefaults persistent domain wiped (--scalecloud-reset)", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alert] _ in
                    alert?.dismiss(animated: true)
                }))
                self.window?.rootViewController?.present(alert, animated: true)
            }
        }

        // If sign credentials are gone (new iloader run, or app reinstall) reset the
        // stored flag so the injection flow starts fresh.
        if !Keychain.shared.hasValidSignCredentials() {
            UserDefaults.standard.signCredentialsInjected = false
        }
        // Skip if sign credentials were already injected and are present.
        guard !UserDefaults.standard.signCredentialsInjected else {
            return
        }
        
        // Present setup flow after a short delay to allow UI to settle.
        // The coordinator is stored as an instance property so it stays alive for
        // the entire debug-channel handoff, which runs on a background thread.
        // A local var would be released the moment start() returns, causing
        // [weak self] inside the background block to capture nil immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            // Double-check: another call may have created a coordinator in the
            // 0.5 s window between this block being scheduled and executing.
            guard self.setupCoordinator == nil else { return }
            let coordinator = SetupCoordinator()
            coordinator.onCompletion = { [weak self] in
                print("[Setup] Setup flow completed successfully")
                self?.setupCoordinator = nil
            }
            self.setupCoordinator = coordinator
            coordinator.start(from: controller)
        }
    }
}

// MARK: - Extension

extension SceneDelegate: NCPasscodeDelegate {
    func requestedAccount(controller: UIViewController?) {
        let tblAccounts = NCManageDatabase.shared.getAllTableAccount()
        if tblAccounts.count > 1, let accountRequestVC = UIStoryboard(name: "NCAccountRequest", bundle: nil).instantiateInitialViewController() as? NCAccountRequest {
            accountRequestVC.controller = controller
            accountRequestVC.activeAccount = (controller as? NCMainTabBarController)?.account
            accountRequestVC.accounts = tblAccounts
            accountRequestVC.enableTimerProgress = true
            accountRequestVC.enableAddAccount = false
            accountRequestVC.dismissDidEnterBackground = false
            accountRequestVC.delegate = self
            accountRequestVC.startTimer(nil)

            let screenHeighMax = UIScreen.main.bounds.height - (UIScreen.main.bounds.height / 5)
            let numberCell = tblAccounts.count
            let height = min(CGFloat(numberCell * Int(accountRequestVC.heightCell) + 45), screenHeighMax)

            let popup = NCPopupViewController(contentController: accountRequestVC, popupWidth: 300, popupHeight: height + 20)
            popup.backgroundAlpha = 0.8

            controller?.present(popup, animated: true)
        }
    }

    func passcodeReset(_ passcodeViewController: TOPasscodeViewController) {
        appDelegate?.resetApplication()
    }
}

extension SceneDelegate: NCAccountRequestDelegate {
    func accountRequestAddAccount() { }

    func accountRequestChangeAccount(account: String, controller: UIViewController?) {
        Task {
            await NCAccount().changeAccount(account, userProfile: nil, controller: controller as? NCMainTabBarController)
        }
    }
}

// MARK: - Scene Manager

@MainActor
final class SceneManager {
    static let shared = SceneManager()
    private var sceneController: [NCMainTabBarController: UIScene] = [:]

    func register(scene: UIScene, withRootViewController rootViewController: NCMainTabBarController) {
        sceneController[rootViewController] = scene
    }

    func getController(scene: UIScene?) -> NCMainTabBarController? {
        for controller in sceneController.keys {
            if sceneController[controller] == scene {
                return controller
            }
        }
        return nil
    }

    func getController(sceneIdentifier: String?) -> NCMainTabBarController? {
        if let sceneIdentifier {
            for controller in sceneController.keys {
                if sceneIdentifier == controller.sceneIdentifier {
                    return controller
                }
            }
        }
        return nil
    }

    func getControllers() -> [NCMainTabBarController] {
        return Array(sceneController.keys)
    }

    func getWindow(scene: UIScene?) -> UIWindow? {
        guard let windowScene = scene as? UIWindowScene else { return nil }

        return windowScene.keyWindow
    }

    func getWindow(controller: UITabBarController?) -> UIWindow? {
        guard let controller = controller as? NCMainTabBarController,
              let scene = sceneController[controller] else { return nil }
        return getWindow(scene: scene)
    }

    func getWindowScene(controller: UIViewController?) -> UIWindowScene? {
        if let windowScene = controller?.viewIfLoaded?.window?.windowScene {
            return windowScene
        }

        // Fallback: if the controller is a registered NCMainTabBarController.
        if let mainTabBarController = controller as? NCMainTabBarController,
           let scene = sceneController[mainTabBarController] as? UIWindowScene {
            return scene
        }

        // Fallback: any foregroundActive scene.
        if let active = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            return active
        }

        // Last resort: literally the first connected window scene.
        return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
    }

    func getWindow(sceneIdentifier: String?) -> UIWindow? {
        // Try exact match via your registry
        if let sceneIdentifier,
           let controller = sceneController.keys.first(where: { $0.sceneIdentifier == sceneIdentifier }),
           let scene = sceneController[controller] {
            return getWindow(scene: scene)
        }

        // Fallback: prefer a foregroundActive window scene
        if let active = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let w = active.keyWindow {
            return w
        }

        // Last resort: first connected window scene
        if let any = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let w = any.keyWindow {
            return w
        }

        // Absolute last resort (if you keep it)
        return UIApplication.shared.mainAppWindow
    }

    func getSceneIdentifier() -> [String] {
        var results: [String] = []
        for controller in sceneController.keys {
            results.append(controller.sceneIdentifier)
        }
        return results
    }

    func getSession(scene: UIScene?) -> NCSession.Session {
        let controller = SceneManager.shared.getController(scene: scene)
        return NCSession.shared.getSession(controller: controller)
    }
}
