// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2024 Aditya Tyagi
// SPDX-FileCopyrightText: 2024 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import ScaleCloudKit
import ScaleCloudRenew
import FirebaseCrashlytics

/// Settings view for Nextcloud
struct NCSettingsView: View {
    // State to control the visibility of the acknowledgements view
    @State private var showAcknowledgements = false
    // Debug: re-sign status
    @State private var resignStatusMessage: String = ""
    @State private var showResignAlert = false
    // State to control the visibility of the passcode view
    @State private var showPasscode = false
    // State to contorl the visibility of the change passcode view
    @State private var showChangePasscode = false
    // State to control the visibility of the Policy view
    @State private var showBrowser = false
    // State to control the visibility of the Source Code  view
    @State private var showSourceCode = false
    // Object of ViewModel of this view
    @ObservedObject var model: NCSettingsModel

    var capabilities: SCKCapabilities.Capabilities {
        NCNetworking.shared.capabilities[model.controller?.account ?? ""] ?? SCKCapabilities.Capabilities()
    }

    var body: some View {
        Form {
            // `Auto Upload` Section
            Section(content: {
                NavigationLink(destination: LazyView {
                    NCAutoUploadView(model: NCAutoUploadModel(controller: model.controller), albumModel: AlbumModel(controller: model.controller))
                }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.icon())
                            .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                            .frame(width: 39)

                        Text(NSLocalizedString("_settings_autoupload_", comment: ""))
                            .font(.body)
                    }
                }
            }, footer: {
                Text(NSLocalizedString("_autoupload_description_", comment: ""))
                    .font(.footnote)
            })

            // `Privacy` Section
            Section(content: {
                Button(action: {
                    showPasscode.toggle()
                }, label: {
                    HStack {
                        Image(systemName: model.isLockActive ? "lock" : "lock.open")
                            .font(.icon())
                            .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                            .opacity(NCBrandOptions.shared.enforce_passcode_lock ? 0.5 : 1)
                            .frame(width: 39)

                        Text(model.isLockActive ? NSLocalizedString("_lock_active_", comment: "") : NSLocalizedString("_lock_not_active_", comment: ""))
                            .font(.body)
                    }
                })
                .tint(Color(NCBrandColor.shared.textColor))
                .disabled(NCBrandOptions.shared.enforce_passcode_lock)
            }, header: {
                Text(NSLocalizedString("_privacy_", comment: ""))
                    .font(.headline)
            }, footer: {
                if NCBrandOptions.shared.enforce_passcode_lock {
                    Text(NSLocalizedString("_lock_cannot_disable_mdm_", comment: ""))
                        .font(.footnote)
                }
            })

            if model.isLockActive {
                Section(content: {
                    Group {
                        // Change passcode
                        Button(action: {
                            showChangePasscode.toggle()
                        }, label: {
                            VStack {
                                Text(NSLocalizedString("_change_lock_passcode_", comment: ""))
                                    .font(.body)
                                    .tint(Color(NCBrandColor.shared.textColor))
                            }
                        })
                        // Enable Touch ID
                        Toggle(NSLocalizedString("_enable_touch_face_id_", comment: ""), isOn: $model.enableTouchFaceID)
                            .font(.body)
                            .onChange(of: model.enableTouchFaceID) { _ in
                                model.updateTouchIDSetting()
                            }

                        if !NCBrandOptions.shared.enforce_passcode_lock {
                            // Do not ask for passcode on startup
                            Toggle(NSLocalizedString("_lock_protection_no_screen_", comment: ""), isOn: $model.lockScreen)
                                .font(.body)
                                .onChange(of: model.lockScreen) { _ in
                                    model.updateLockScreenSetting()
                                }
                        }

                        // Reset app wrong attempts
                        Toggle(NSLocalizedString("_reset_wrong_passcode_option_", comment: ""), isOn: $model.resetWrongAttempts)
                            .font(.body)
                            .onChange(of: model.resetWrongAttempts) { _ in
                                model.updateResetWrongAttemptsSetting()
                            }
                    }
                }, footer: {
                    Text(String(format: NSLocalizedString("_reset_wrong_passcode_desc_", comment: ""), NCBrandOptions.shared.resetAppPasscodeAttempts))
                        .font(.footnote)

                })
                .tint(Color(NCBrandColor.shared.getElement(account: model.session.account)))
            }

            if !NCBrandOptions.shared.enforce_privacyScreenEnabled {
                Section(content: {
                    // Splash screen when app inactive
                    Toggle(NSLocalizedString("_privacy_screen_", comment: ""), isOn: $model.privacyScreen)
                        .font(.body)
                        .onChange(of: model.privacyScreen) { _ in
                            model.updatePrivacyScreenSetting()
                        }
                }, footer: {
                    Text(NSLocalizedString("_privacy_screen_footer_", comment: ""))
                        .font(.footnote)
                })
                .tint(Color(NCBrandColor.shared.getElement(account: model.session.account)))
            }

            // Display
            Section(header: Text(NSLocalizedString("_display_", comment: "")).font(.headline), content: {
                NavigationLink(destination: LazyView {
                    NCDisplayView(model: NCDisplayModel(controller: model.controller))
                }) {
                    HStack {
                        Image(systemName: "sun.max.circle")
                            .font(.icon())
                            .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                            .frame(width: 39)

                        Text(NSLocalizedString("_display_", comment: ""))
                            .font(.body)
                    }
                }
            })
            // Calender & Contacts
            if !NCBrandOptions.shared.disable_mobileconfig {
                Section(content: {
                    Button(action: {
                        model.getConfigFiles()
                    }, label: {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .font(.icon())
                                .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                                .frame(width: 39)

                            Text(NSLocalizedString("_mobile_config_", comment: ""))
                                .font(.body)
                        }
                    })
                    .tint(Color(NCBrandColor.shared.textColor))
                }, header: {
                    Text(NSLocalizedString("_calendar_contacts_", comment: ""))
                        .font(.headline)
                }, footer: {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("_calendar_contacts_footer_warning_", comment: ""))
                            .font(.footnote)

                        Spacer()
                        Text(NSLocalizedString("_calendar_contacts_footer_", comment: ""))
                            .font(.footnote)
                    }
                })
            }
            // Users
            Section(content: {
                Toggle(NSLocalizedString("_settings_account_request_", comment: ""), isOn: $model.accountRequest)
                    .font(.body)
                    .tint(Color(NCBrandColor.shared.getElement(account: model.session.account)))
                    .onChange(of: model.accountRequest) { _ in
                        model.updateAccountRequest()
                    }
            }, header: {
                Text(NSLocalizedString("_users_", comment: ""))
                    .font(.headline)
            }, footer: {
                Text(NSLocalizedString("_users_footer_", comment: ""))
                    .font(.footnote)
            })
            // E2EEncryption` Section
            if capabilities.e2EEEnabled {
                E2EESection(model: model)
            }
            // `Advanced` Section
            Section {
                NavigationLink(destination: LazyView {
                    NCSettingsAdvancedView(model: NCSettingsAdvancedModel(controller: model.controller), showExitAlert: false, showCacheAlert: false)
                }) {
                    HStack {
                        Image(systemName: "gear")
                            .font(.icon())
                            .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                            .frame(width: 39)

                        Text(NSLocalizedString("_advanced_", comment: ""))
                            .font(.body)
                    }
                }
            }
            // `Information` Section
            Section(header: Text(NSLocalizedString("_information_", comment: "")).font(.headline), content: {
                // Acknowledgements
                Button(action: {
                    showAcknowledgements.toggle()
                }, label: {
                    HStack {
                        Image(systemName: "figure.2.circle")
                            .font(.icon())
                            .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                            .frame(width: 39)

                        Text(NSLocalizedString("_acknowledgements_", comment: ""))
                            .font(.body)
                    }
                })
                .tint(Color(NCBrandColor.shared.textColor))
                .sheet(isPresented: $showAcknowledgements) {
                    NCAcknowledgementsView(browserTitle: NSLocalizedString("_acknowledgements_", comment: ""))
                }
                // Terms & Privacy Conditions
                Button(action: {
                    showBrowser.toggle()
                }, label: {
                    HStack {
                        Image(systemName: "shield.checkerboard")
                            .font(.icon())
                            .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                            .frame(width: 39)

                        Text(NSLocalizedString("_privacy_legal_", comment: ""))
                            .font(.body)
                    }
                })
                .tint(Color(NCBrandColor.shared.textColor))
                .sheet(isPresented: $showBrowser) {
                    NCBrowserWebView(urlBase: URL(string: NCBrandOptions.shared.privacy)!, browserTitle: NSLocalizedString("_privacy_legal_", comment: ""))
                }
                // Source Code Nextcloud App
                if !NCBrandOptions.shared.disable_source_code_in_settings {
                    Button(action: {
                        showSourceCode.toggle()
                    }, label: {
                        HStack {
                            Image(systemName: "network")
                                .font(.icon())
                                .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                                .frame(width: 39)

                            Text(NSLocalizedString("_source_code_", comment: ""))
                                .font(.body)
                        }
                    })
                    .tint(Color(NCBrandColor.shared.textColor))
                    .sheet(isPresented: $showSourceCode) {
                        NCBrowserWebView(urlBase: URL(string: NCBrandOptions.shared.sourceCode)!, browserTitle: NSLocalizedString("_source_code_", comment: ""))
                    }
                }
            })
#if DEBUG
            Section(header: Text("Debug").font(.headline), content: {
                Button(action: {
                    Crashlytics.crashlytics().log("Test crash triggered")
                    fatalError("🔥 Crash test")
                }, label: {
                    HStack {
                        Image(systemName: "flame.fill")
                            .font(.icon())
                            .foregroundColor(.red)
                            .frame(width: 39)

                        Text("Test crash triggered")
                            .font(.body)
                    }
                })
                .tint(Color(NCBrandColor.shared.textColor))

                // Signing diagnostics row
                HStack {
                    Image(systemName: "signature")
                        .font(.icon())
                        .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                        .frame(width: 39)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signing status")
                            .font(.body)
                        Text(signingDiagnostics())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Force re-sign button
                Button(action: {
                    forceResign()
                }, label: {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.icon())
                            .foregroundColor(.orange)
                            .frame(width: 39)

                        Text("Force Re-sign Now")
                            .font(.body)
                    }
                })
                .tint(Color(NCBrandColor.shared.textColor))
                .alert("Re-sign Result", isPresented: $showResignAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(resignStatusMessage)
                }
            })
#endif

            // `Watermark` Section
            Section(content: {
            }, footer: {
                Text(model.footerApp + model.footerServer + model.footerSlogan)
                    .font(.footnote)
            })
        }
        .sheet(isPresented: $showPasscode) {
            SetupPasscodeView(isLockActive: $model.isLockActive, controller: model.controller)
        }
        .sheet(isPresented: $showChangePasscode) {
            SetupPasscodeView(isLockActive: $model.isLockActive, controller: model.controller, changePasscode: true)
        }
        .navigationBarTitle(NSLocalizedString("_settings_", comment: ""))
        .defaultViewModifier(model)
    }
}

struct E2EESection: View {
    @ObservedObject var model: NCSettingsModel

    var body: some View {
        Section(header: Text(NSLocalizedString("_e2e_settings_title_", comment: "")).font(.headline), content: {
            NavigationLink(destination: LazyView {
                NCManageE2EEView(model: NCManageE2EE(controller: model.controller))
            }) {
                HStack {
                    Image(systemName: "lock")
                        .font(.icon())
                        .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                        .frame(width: 39)

                    Text(NSLocalizedString("_e2e_settings_", comment: ""))
                        .font(.body)
                }
            }
        })
    }
}

// MARK: - Debug helpers

#if DEBUG
private extension NCSettingsView {
    /// Returns a one-line summary of signing prerequisites for the diagnostics row.
    func signingDiagnostics() -> String {
        let coordinator = AppOperationCoordinator.shared
        var parts: [String] = []

        // Certificate expiry
        if let days = coordinator.daysUntilExpiry() {
            parts.append("cert \(days)d")
        } else {
            parts.append("cert: none")
        }

        // Minimuxer
        parts.append(isMinimuxerReady ? "mux:✓" : "mux:✗")

        // Anisette
        let hasAnisette = !UserDefaults.standard.menuAnisetteServersList.isEmpty
        parts.append(hasAnisette ? "anisette:✓" : "anisette:✗")

        // State
        parts.append(coordinator.currentState.rawValue)

        return parts.joined(separator: "  ")
    }

    /// Bypasses all gates and fires the signing engine directly.
    /// Reads installed apps from CoreData, hands them to BackgroundRefreshAppsOperation.
    func forceResign() {
        nkLog(debug: "[Debug] Force re-sign triggered from Settings")
        let coordinator = AppOperationCoordinator.shared

        // Force state to refreshing regardless of current state
        // (reset to idle first if needed so the transition is valid)
        if coordinator.currentState != .idle {
            coordinator.attemptTransition(to: .idle)
        }
        guard coordinator.attemptTransition(to: .refreshing) else {
            resignStatusMessage = "Could not start: state is \(coordinator.currentState.rawValue)"
            showResignAlert = true
            return
        }

        DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            // Use fetchAppsForRefreshingAll (no 6h cooldown) so a force-trigger always works
            let apps = InstalledApp.fetchAppsForRefreshingAll(in: context)
            guard !apps.isEmpty else {
                DispatchQueue.main.async {
                    coordinator.attemptTransition(to: .idle)
                    self.resignStatusMessage = "No apps in signing database.\nRun setup/install first so an InstalledApp record exists."
                    self.showResignAlert = true
                }
                return
            }

            nkLog(debug: "[Debug] Force re-sign: \(apps.count) app(s) found")
            let operation = BackgroundRefreshAppsOperation(installedApps: apps)
            operation.refreshCompletionHandler = { success, expiryDate in
                DispatchQueue.main.async {
                    coordinator.attemptTransition(to: .idle)
                    if success, let expiry = expiryDate {
                        coordinator.setCertificateExpiry(expiry)
                        let fmt = DateFormatter()
                        fmt.dateStyle = .medium
                        fmt.timeStyle = .short
                        self.resignStatusMessage = "✅ Re-sign succeeded!\nCert expires: \(fmt.string(from: expiry))"
                    } else {
                        self.resignStatusMessage = "❌ Re-sign failed.\nCheck Xcode console / os_log for details."
                    }
                    self.showResignAlert = true
                }
            }
            operation.start()
        }
    }
}
#endif

#Preview {
    NCSettingsView(model: NCSettingsModel(controller: nil))
}
