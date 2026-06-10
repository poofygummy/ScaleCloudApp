// SPDX-FileCopyrightText: 2025 ScaleCloud Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security

/// App-wide operation state to prevent sync/signing collisions
enum AppOperationState: String, Codable {
    case idle
    case syncing          // Nextcloud file operations active
    case refreshPending   // BGTask fired during sync, deferred
    case refreshing       // Signing operation running
}

/// Notification posted when state changes
extension Notification.Name {
    static let appOperationStateChanged = Notification.Name("AppOperationStateChanged")
}

/// Singleton coordinator preventing sync/signing collisions in background
final class AppOperationCoordinator {
    static let shared = AppOperationCoordinator()
    
    // MARK: - Properties
    
    private let lock = NSLock()
    private var _state: AppOperationState = .idle
    private var deferredRefreshCompletion: ((Bool) -> Void)?
    
    private let stateKey = "appOperationState"
    private let certExpiryKeychainKey = "com.scalecloud.cert.expiry"
    
    /// Current operation state (thread-safe read)
    var currentState: AppOperationState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }
    
    // MARK: - Initialization
    
    private init() {
        restoreState()
        nkLog(debug: "[AppOperationCoordinator] Initialized with state: \(_state)")
    }
    
    // MARK: - State Transitions
    
    /// Attempt state transition with validation
    /// Returns true if transition succeeded
    @discardableResult
    func attemptTransition(to newState: AppOperationState) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let oldState = _state
        
        // Validate transition
        guard isValidTransition(from: oldState, to: newState) else {
            nkLog(debug: "[AppOperationCoordinator] Invalid transition: \(oldState) → \(newState)")
            return false
        }
        
        _state = newState
        persistState()
        
        nkLog(debug: "[AppOperationCoordinator] State transition: \(oldState) → \(newState)")
        
        // Post notification on main thread
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .appOperationStateChanged,
                object: self,
                userInfo: ["oldState": oldState, "newState": newState]
            )
        }
        
        // Execute deferred refresh if transitioning from refreshPending
        if newState == .refreshing && oldState == .refreshPending {
            executeDeferredRefreshLocked()
        }
        
        return true
    }
    
    /// Check if refresh can start immediately
    func canStartRefresh() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _state == .idle
    }
    
    /// Defer refresh operation (called when BGTask fires during sync)
    func deferRefresh(completion: @escaping (Bool) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        
        guard _state == .syncing else {
            nkLog(debug: "[AppOperationCoordinator] deferRefresh called but state is \(_state), not syncing")
            completion(false)
            return
        }
        
        deferredRefreshCompletion = completion
        _ = attemptTransitionLocked(to: .refreshPending)
        nkLog(debug: "[AppOperationCoordinator] Refresh deferred until sync completes")
    }
    
    /// Execute deferred refresh (called when sync completes)
    func executeDeferredRefresh() {
        lock.lock()
        defer { lock.unlock() }
        executeDeferredRefreshLocked()
    }
    
    private func executeDeferredRefreshLocked() {
        guard let completion = deferredRefreshCompletion else { return }
        deferredRefreshCompletion = nil
        
        nkLog(debug: "[AppOperationCoordinator] Executing deferred refresh")
        
        // Call completion async to avoid deadlock
        DispatchQueue.global(qos: .userInitiated).async {
            completion(true)
        }
    }
    
    // MARK: - Certificate Expiry Tracking
    
    /// Store certificate expiry date in Keychain
    func setCertificateExpiry(_ date: Date) {
        let iso8601 = ISO8601DateFormatter().string(from: date)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certExpiryKeychainKey,
            kSecValueData as String: iso8601.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete existing
        SecItemDelete(query as CFDictionary)
        
        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            nkLog(debug: "[AppOperationCoordinator] Stored certificate expiry: \(iso8601)")
        } else {
            nkLog(debug: "[AppOperationCoordinator] Failed to store certificate expiry: \(status)")
        }
    }
    
    /// Retrieve certificate expiry date from Keychain
    func getCertificateExpiry() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certExpiryKeychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let iso8601 = String(data: data, encoding: .utf8),
              let date = ISO8601DateFormatter().date(from: iso8601) else {
            return nil
        }
        
        return date
    }
    
    /// Days until certificate expires (nil if no expiry stored)
    func daysUntilExpiry() -> Int? {
        guard let expiry = getCertificateExpiry() else { return nil }
        let now = Date()
        let interval = expiry.timeIntervalSince(now)
        return Int(interval / 86400) // seconds to days
    }
    
    /// Check if refresh is needed (< 4 days until expiry)
    func isRefreshNeeded() -> Bool {
        guard let days = daysUntilExpiry() else { return false }
        return days < 4
    }
    
    // MARK: - State Persistence
    
    private func persistState() {
        UserDefaults.standard.set(_state.rawValue, forKey: stateKey)
    }
    
    private func restoreState() {
        guard let rawValue = UserDefaults.standard.string(forKey: stateKey),
              let state = AppOperationState(rawValue: rawValue) else {
            return
        }
        
        // Handle stale states from crash
        switch state {
        case .idle:
            _state = .idle
        case .syncing, .refreshing, .refreshPending:
            // App crashed during operation, reset to idle
            nkLog(debug: "[AppOperationCoordinator] Recovered from stale state: \(state), resetting to idle")
            _state = .idle
            persistState()
        }
    }
    
    // MARK: - Validation
    
    private func isValidTransition(from old: AppOperationState, to new: AppOperationState) -> Bool {
        switch (old, new) {
        case (.idle, .syncing),
             (.idle, .refreshing),
             (.syncing, .refreshPending),
             (.syncing, .idle),
             (.refreshPending, .refreshing),
             (.refreshPending, .idle),
             (.refreshing, .idle):
            return true
        default:
            return false
        }
    }
    
    private func attemptTransitionLocked(to newState: AppOperationState) -> Bool {
        let oldState = _state
        
        guard isValidTransition(from: oldState, to: newState) else {
            return false
        }
        
        _state = newState
        persistState()
        
        nkLog(debug: "[AppOperationCoordinator] State transition (locked): \(oldState) → \(newState)")
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .appOperationStateChanged,
                object: self,
                userInfo: ["oldState": oldState, "newState": newState]
            )
        }
        
        return true
    }
}
