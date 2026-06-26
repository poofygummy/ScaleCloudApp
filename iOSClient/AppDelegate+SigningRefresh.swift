// SPDX-FileCopyrightText: 2025 ScaleCloud Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import UIKit
import BackgroundTasks
import ScaleCloudKit
import ScaleCloudRenew

extension AppDelegate {
    
    /// Register background task handler for daily signing refresh check
    func registerSigningBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.scalecloud.refresh",
            using: nil
        ) { task in
            self.handleDailyRefreshCheck(task: task as! BGProcessingTask)
        }
        
        nkLog(debug: "[Signing] Registered background task")
        
        // Schedule initial daily check
        scheduleDailyRefreshCheck()
    }
    
    /// Schedule daily refresh check (runs every 24 hours)
    func scheduleDailyRefreshCheck() {
        // Cancel existing request
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.scalecloud.refresh")
        
        // Schedule for 24 hours from now
        let nextCheck = Date(timeIntervalSinceNow: 24 * 60 * 60)
        
        let request = BGProcessingTaskRequest(identifier: "com.scalecloud.refresh")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = nextCheck
        
        do {
            try BGTaskScheduler.shared.submit(request)
            nkLog(debug: "[Signing] Scheduled daily refresh check for \(nextCheck)")
        } catch {
            nkLog(debug: "[Signing] Failed to schedule daily refresh check: \(error)")
        }
    }
    
    /// Handle daily refresh check task
    /// Checks if < 4 days until expiry, executes signing if needed
    private func handleDailyRefreshCheck(task: BGProcessingTask) {
        nkLog(debug: "[Signing] Daily BGProcessingTask fired")
        
        let coordinator = AppOperationCoordinator.shared
        
        // Set expiration handler
        task.expirationHandler = {
            nkLog(debug: "[Signing] BGProcessingTask expired")
            coordinator.attemptTransition(to: .idle)
            task.setTaskCompleted(success: false)
            // Reschedule for next day
            self.scheduleDailyRefreshCheck()
        }
        
        // Check if refresh is needed (< 4 days until expiry)
        guard coordinator.isRefreshNeeded() else {
            nkLog(debug: "[Signing] Refresh not needed (>= 4 days until expiry)")
            task.setTaskCompleted(success: true)
            // Reschedule for next day
            scheduleDailyRefreshCheck()
            return
        }
        
        // Refresh is needed
        nkLog(debug: "[Signing] Refresh needed (< 4 days until expiry)")
        
        // Check if we can start refresh (not syncing)
        guard coordinator.canStartRefresh() else {
            // Sync is active, defer refresh
            nkLog(debug: "[Signing] Sync active, deferring refresh")
            coordinator.deferRefresh { success in
                if success {
                    self.executeSigningOperation(bgTask: task)
                } else {
                    task.setTaskCompleted(success: false)
                    self.scheduleDailyRefreshCheck()
                }
            }
            return
        }
        
        // Start refresh immediately
        coordinator.attemptTransition(to: .refreshing)
        executeSigningOperation(bgTask: task)
    }
    
    /// Execute the actual signing operation.
    /// Fetches installed apps from the signing database (CoreData via DatabaseManager),
    /// then hands them to BackgroundRefreshAppsOperation — exactly as SideStore does.
    func executeSigningOperation(bgTask: BGTask? = nil) {
        nkLog(debug: "[Signing] Executing signing operation")

        DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            let installedApps = InstalledApp.fetchAppsForBackgroundRefresh(in: context)

            guard !installedApps.isEmpty else {
                nkLog(debug: "[Signing] No apps in signing database to refresh")
                AppOperationCoordinator.shared.attemptTransition(to: .idle)
                bgTask?.setTaskCompleted(success: true)
                self.scheduleDailyRefreshCheck()
                return
            }

            nkLog(debug: "[Signing] Refreshing \(installedApps.count) app(s)")

            let operation = BackgroundRefreshAppsOperation(installedApps: installedApps)
            operation.refreshCompletionHandler = { [weak self] success, expiryDate in
                guard let self = self else { return }

                let coordinator = AppOperationCoordinator.shared

                if success, let expiryDate = expiryDate {
                    coordinator.setCertificateExpiry(expiryDate)
                    nkLog(debug: "[Signing] Updated certificate expiry: \(expiryDate)")
                }

                coordinator.attemptTransition(to: .idle)
                bgTask?.setTaskCompleted(success: success)
                self.scheduleDailyRefreshCheck()
            }

            operation.start()
        }
    }
}
