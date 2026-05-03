//
//  AppDelegate.swift
//  Fluid
//
//  Created by Barathwaj Anandan on 9/22/25.
//

import AppKit
import PromiseKit
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var updateCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bring up file logging + crash handlers immediately during launch.
        _ = FileLogger.shared
        DebugLogger.shared.info("Application launched", source: "AppDelegate")
        UNUserNotificationCenter.current().delegate = self

        // Initialize app settings (dock visibility, etc.)
        SettingsStore.shared.initializeAppSettings()

        // Record first-open synchronously before async analytics bootstrap so
        // onboarding initialization is deterministic on brand-new installs.
        let isTrueFirstOpen = AnalyticsIdentityStore.shared.ensureFirstOpenRecorded()
        SettingsStore.shared.bootstrapOnboardingState(isTrueFirstOpen: isTrueFirstOpen)

        AnalyticsService.shared.bootstrap()

        if SettingsStore.shared.shouldPromptAccessibilityOnLaunch {
            self.requestAccessibilityPermissions()
        }

        if isTrueFirstOpen {
            AnalyticsService.shared.capture(.appFirstOpen)
        }
        AnalyticsService.shared.capture(
            .appOpen,
            properties: ["accessibility_trusted": AXIsProcessTrusted()]
        )

        // ── Update checks DISABLED for private build ──
        // To re-enable: un-comment the two lines below.
        // self.checkForUpdatesAutomatically()
        // self.schedulePeriodicUpdateChecks()

        // Bring the app to front on initial launch.
        // Use a few delayed retries because SwiftUI window creation can lag app launch callbacks.
        self.forceFrontOnLaunch()

        // Note: App UI is designed with dark color scheme in mind
        // All gradients and effects are optimized for dark mode
    }

    func applicationWillTerminate(_ notification: Notification) {
        DebugLogger.shared.info("Application will terminate", source: "AppDelegate")
        // Clean up the update check timer
        self.updateCheckTimer?.invalidate()
        self.updateCheckTimer = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Ensure dock-icon reopen always foregrounds FluidVoice.
        sender.activate(ignoringOtherApps: true)

        if let mainWindow = sender.windows.first(where: { win in
            guard win.level == .normal else { return false }
            guard win.styleMask.contains(.titled) else { return false }
            return win.title == "FluidVoice" || win.title.contains("FluidVoice")
        }) {
            mainWindow.orderFrontRegardless()
            mainWindow.makeKeyAndOrderFront(nil)
        }

        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if userInfo[NotificationService.UserInfoKey.kind] as? String == NotificationService.Kind.aiProcessingFallback {
            DispatchQueue.main.async {
                AppNavigationRouter.shared.request(.history)
                self.bringMainWindowToFront()
            }
        }

        completionHandler()
    }

    private func forceFrontOnLaunch() {
        // Login-item launches can take longer before SwiftUI's main window exists.
        // Keep retrying while FluidVoice is still foregrounded, but stop if the user switches away.
        for delay in [0.0, 0.12, 0.35, 1.0, 2.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard delay == 0.0 || self.shouldContinueLaunchForegroundRetry() else {
                    DebugLogger.shared.debug("Skipped launch-front retry because another app is active", source: "AppDelegate")
                    return
                }
                self.bringMainWindowToFront()
            }
        }
    }

    private func shouldContinueLaunchForegroundRetry() -> Bool {
        if NSApp.isActive { return true }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)

        if let mainWindow = NSApp.windows.first(where: { win in
            guard win.level == .normal else { return false }
            guard win.styleMask.contains(.titled) else { return false }
            return win.title == "FluidVoice" || win.title.contains("FluidVoice")
        }) {
            mainWindow.orderFrontRegardless()
            mainWindow.makeKeyAndOrderFront(nil)
            DebugLogger.shared.debug("Brought main window to front", source: "AppDelegate")
        } else {
            DebugLogger.shared.debug("Main window not ready yet during launch-front retry", source: "AppDelegate")
        }
    }

    // MARK: - Periodic Update Checks

    private func schedulePeriodicUpdateChecks() {
        // ── DISABLED for private build: periodic update checks ──
        // To re-enable, remove this comment and restore the Timer block below:
        // self.updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
        //     self?.checkForUpdatesAutomatically()
        // }
    }

    // MARK: - Manual Update Check

    @objc func checkForUpdatesManually() {
        // ── DISABLED for private build ──
        // Auto-update and manual-update features are disabled.
        // Version display is retained in Preferences → App Updates.
        DebugLogger.shared.info("checkForUpdatesManually() called but update is disabled for this build.", source: "AppDelegate")
    }

    // MARK: - Automatic Update Check

    private func checkForUpdatesAutomatically() {
        // ── DISABLED for private build ──
        DebugLogger.shared.debug("Automatic update check is disabled for this build.", source: "AppDelegate")
    }

    @MainActor
    private func showUpdateNotification(version: String) {
        DebugLogger.shared.info("Showing update notification for version \(version)", source: "AppDelegate")

        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "FluidVoice \(version) is now available. Would you like to install it now?\n\nThe app will restart automatically after installation."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Now")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            DebugLogger.shared.info("User chose to install update now", source: "AppDelegate")
            SettingsStore.shared.clearUpdateSnooze() // Clear snooze since they're installing
            self.checkForUpdatesManually()
        } else {
            DebugLogger.shared.info("User postponed update for 24 hours", source: "AppDelegate")
            SettingsStore.shared.snoozeUpdatePrompt(forVersion: version)
        }
    }

    @MainActor
    private func showUpdateAlert(title: String, message: String) {
        DebugLogger.shared.info("🔔 Showing alert: \(title)", source: "AppDelegate")
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func requestAccessibilityPermissions() {
        // Never show if already trusted
        guard !AXIsProcessTrusted() else { return }

        // Per-session debounce
        if AXPromptState.hasPromptedThisSession { return }

        // Cooldown: avoid re-prompting too often across launches
        let cooldownKey = "AXLastPromptAt"
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: cooldownKey)
        let oneDay: Double = 24 * 60 * 60
        if last > 0, (now - last) < oneDay {
            return
        }

        DebugLogger.shared.warning("Accessibility permissions required for global hotkeys.", source: "AppDelegate")
        DebugLogger.shared.info("Prompting for Accessibility permission…", source: "AppDelegate")

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        AXPromptState.hasPromptedThisSession = true
        UserDefaults.standard.set(now, forKey: cooldownKey)

        // If still not trusted shortly after, deep-link to the Accessibility pane for convenience
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard !AXIsProcessTrusted(),
                  let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            else { return }
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Session Debounce State

private enum AXPromptState {
    static var hasPromptedThisSession: Bool = false
}
