//
//  AutomaticBackupsView.swift
//  Aidoku
//
//  Created by Skitty on 11/13/25.
//

import AuthenticationServices
import SwiftUI

struct AutomaticBackupsView: View {
    @StateObject private var enabled = UserDefaultsBool(key: AppSettings.backups.autoBackups.enabled.key)

    @StateObject private var driveUploadEnabled = UserDefaultsBool(key: GoogleDriveClient.enabledKey)

    @State private var driveSignedIn = false
    @State private var driveAccount: String?
    @State private var driveLastUpload: Double = 0
    @State private var driveLoading = false
    @State private var driveSyncing = false
    @State private var showDriveLoginFailAlert = false
    @State private var showDriveSyncFailAlert = false

    @Environment(\.dismiss) private var dismiss

    // empty view controller to support login view presentation
    private static var loginShimController = LoginShimViewController()

    var body: some View {
        PlatformNavigationStack {
            List {
                Section {
                    toggle(key: AppSettings.backups.autoBackups.enabled.key, title: NSLocalizedString("AUTOMATIC_BACKUPS"))

                    if enabled.value {
                        SettingView(
                            setting: .init(
                                key: AppSettings.backups.autoBackups.interval.key,
                                title: NSLocalizedString("BACKUP_INTERVAL"),
                                value: .select(.init(
                                    values: ["6hours", "12hours", "daily", "2days", "weekly"],
                                    titles: [
                                        NSLocalizedString("EVERY_6_HOURS"),
                                        NSLocalizedString("EVERY_12_HOURS"),
                                        NSLocalizedString("DAILY"),
                                        NSLocalizedString("EVERY_2_DAYS"),
                                        NSLocalizedString("WEEKLY")
                                    ]
                                ))
                            )
                        )
                    }
                } footer: {
                    let date = AppSettings.backups.autoBackups.lastBackup.get()
                    if date > Date.distantPast {
                        Text(String(format: NSLocalizedString("LAST_BACKED_UP_%@"), date.formatted(.relative(presentation: .named))))
                    }
                }

                if enabled.value {
                    Section(NSLocalizedString("LIBRARY")) {
                        toggle(key: AppSettings.backups.autoBackups.libraryEntries.key, title: NSLocalizedString("LIBRARY_ENTRIES"))
                        toggle(key: AppSettings.backups.autoBackups.chapters.key, title: NSLocalizedString("CHAPTERS"))
                        toggle(key: AppSettings.backups.autoBackups.tracking.key, title: NSLocalizedString("TRACKING"))
                        toggle(key: AppSettings.backups.autoBackups.history.key, title: NSLocalizedString("HISTORY"))
                        toggle(key: AppSettings.backups.autoBackups.categories.key, title: NSLocalizedString("CATEGORIES"))
                        toggle(key: AppSettings.backups.autoBackups.readingSessions.key, title: NSLocalizedString("READING_SESSIONS"))
                        toggle(key: AppSettings.backups.autoBackups.updates.key, title: NSLocalizedString("MANGA_UPDATES"))
                    }
                    Section(NSLocalizedString("SETTINGS")) {
                        toggle(key: AppSettings.backups.autoBackups.settings.key, title: NSLocalizedString("SETTINGS"))
                        toggle(key: AppSettings.backups.autoBackups.sourceLists.key, title: NSLocalizedString("SOURCE_LISTS"))
                        toggle(key: AppSettings.backups.autoBackups.sensitiveSettings.key, title: NSLocalizedString("SENSITIVE_SETTINGS"))
                    }
                }

                // stays visible while signed in, so drive access can always be revoked here
                googleDriveSection
            }
            .animation(.default, value: enabled.value)
            .animation(.default, value: driveSignedIn)
            .navigationTitle(NSLocalizedString("AUTOMATIC_BACKUPS"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .onChange(of: enabled.value) { _ in
                Task {
                    await BackupManager.shared.scheduleAutoBackup()
                }
            }
            .onChange(of: driveUploadEnabled.value) { _ in
                // the scheduled task's network requirement depends on this
                Task {
                    await BackupManager.shared.scheduleAutoBackup()
                }
            }
            .alert(NSLocalizedString("LOGIN_FAILED"), isPresented: $showDriveLoginFailAlert) {
                Button(NSLocalizedString("OK"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("GOOGLE_DRIVE_LOGIN_FAILED_TEXT"))
            }
            .alert(NSLocalizedString("SYNC_FAILED"), isPresented: $showDriveSyncFailAlert) {
                Button(NSLocalizedString("OK"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("GOOGLE_DRIVE_SYNC_FAILED_TEXT"))
            }
            .task {
                await refreshGoogleDriveState()
            }
        }
    }

    func toggle(key: String, title: String) -> some View {
        SettingView(
            setting: .init(
                key: key,
                title: title,
                value: .toggle(.init())
            )
        )
    }
}

// MARK: - Google Drive
extension AutomaticBackupsView {
    @ViewBuilder
    var googleDriveSection: some View {
        // still shown while signed in with backups off, so access can be revoked
        if GoogleDriveClient.isConfigured && (enabled.value || driveSignedIn) {
            Section {
                if driveSignedIn {
                    if let driveAccount {
                        HStack {
                            Text(NSLocalizedString("ACCOUNT"))
                            Spacer()
                            Text(driveAccount)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    toggle(key: GoogleDriveClient.enabledKey, title: NSLocalizedString("UPLOAD_BACKUPS"))

                    if driveUploadEnabled.value {
                        Button {
                            syncToGoogleDrive()
                        } label: {
                            HStack {
                                Text(NSLocalizedString("SYNC_NOW"))
                                Spacer()
                                if driveSyncing {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                }
                            }
                        }
                        .disabled(driveSyncing)
                    }

                    Button(role: .destructive) {
                        Task {
                            await GoogleDriveClient.shared.signOut()
                            await BackupManager.shared.scheduleAutoBackup()
                            await refreshGoogleDriveState()
                        }
                    } label: {
                        Text(NSLocalizedString("LOGOUT"))
                    }
                } else {
                    Button {
                        signInToGoogleDrive()
                    } label: {
                        HStack {
                            Text(NSLocalizedString("LOGIN"))
                            Spacer()
                            if driveLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                        }
                    }
                    .disabled(driveLoading)
                }
            } header: {
                Text(NSLocalizedString("GOOGLE_DRIVE"))
            } footer: {
                if driveSignedIn && driveLastUpload > 0 {
                    Text(String(
                        format: NSLocalizedString("LAST_UPLOADED_%@"),
                        Date(timeIntervalSince1970: driveLastUpload).formatted(.relative(presentation: .named))
                    ))
                } else {
                    Text(String(format: NSLocalizedString("GOOGLE_DRIVE_INFO_%@"), GoogleDriveClient.folderName))
                }
            }
        }
    }

    private func refreshGoogleDriveState() async {
        driveSignedIn = await GoogleDriveClient.shared.isSignedIn
        driveAccount = await GoogleDriveClient.shared.account
        driveLastUpload = UserDefaults.standard.double(forKey: GoogleDriveClient.lastUploadKey)
    }

    private func syncToGoogleDrive() {
        driveSyncing = true
        Task {
            defer { driveSyncing = false }
            let success = await BackupManager.shared.syncToGoogleDrive()
            if !success {
                showDriveSyncFailAlert = true
            }
            await refreshGoogleDriveState()
        }
    }

    private func signInToGoogleDrive() {
        // set before starting, so a second tap can't overwrite the pkce verifier mid-flow
        driveLoading = true
        Task {
            guard let url = await GoogleDriveClient.shared.authenticationUrl() else {
                driveLoading = false
                return
            }
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GoogleDriveClient.callbackScheme
            ) { callbackUrl, error in
                Task { @MainActor in
                    defer { driveLoading = false }

                    if let error {
                        // the user cancelling isn't worth logging
                        if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                            LogManager.logger.error("Google Drive authentication error: \(error.localizedDescription)")
                        }
                        return
                    }
                    guard let callbackUrl else { return }

                    do {
                        try await GoogleDriveClient.shared.handleAuthenticationCallback(url: callbackUrl)
                        // uploading is the point of signing in, so turn it on
                        UserDefaults.standard.set(true, forKey: GoogleDriveClient.enabledKey)
                        await BackupManager.shared.scheduleAutoBackup()
                    } catch {
                        LogManager.logger.error("Google Drive authentication error: \(error)")
                        showDriveLoginFailAlert = true
                    }
                    await refreshGoogleDriveState()
                }
            }
            session.presentationContextProvider = Self.loginShimController
            if !session.start() {
                LogManager.logger.error("Could not start the Google Drive login session")
                driveLoading = false
            }
        }
    }
}
