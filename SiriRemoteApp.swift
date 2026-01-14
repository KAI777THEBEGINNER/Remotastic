//
//  SiriRemoteApp.swift
//  Remotastic
//
//  Menu bar application for controlling Mac with Siri Remote
//

import AppKit
import ApplicationServices
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem!
    private var menuBarManager: MenuBarManager!
    private var remoteDetector: RemoteDetector?
    private var remoteInputHandler: RemoteInputHandler?
    private var mediaKeyInterceptor: MediaKeyInterceptor?
    private var touchHandler: TouchHandler?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Remotastic starting...")
        
        // Run as menu bar app (no dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let statusItem = statusItem else {
            NSApp.terminate(nil)
            return
        }
        statusItem.isVisible = true
        
        // Initialize menu bar manager
        menuBarManager = MenuBarManager(statusItem: statusItem)
        
        // Check accessibility permissions
        checkAccessibilityPermissions()
        
        // Initialize controllers
        let cursorController = CursorController()
        let mediaController = MediaController()
        
        remoteInputHandler = RemoteInputHandler(
            cursorController: cursorController,
            mediaController: mediaController,
            menuBarManager: menuBarManager
        )
        
        // Start remote detection
        remoteDetector = RemoteDetector { [weak self] device in
            DispatchQueue.main.async {
                self?.remoteInputHandler?.setRemoteDevice(device)
                self?.menuBarManager.updateConnectionStatus(connected: device != nil)
            }
        }
        remoteDetector?.startDetection()
        
        // Start media key interceptor
        mediaKeyInterceptor = MediaKeyInterceptor()
        mediaKeyInterceptor?.onMediaKey = { [weak self] keyType in
            guard let self = self else { return false }
            return self.handleInterceptedMediaKey(keyType)
        }
        mediaKeyInterceptor?.start()
        
        // Start touch handler for trackpad
        touchHandler = TouchHandler(cursorController: cursorController)
        touchHandler?.trackpadMode = menuBarManager.trackpadMode
        touchHandler?.scrollScale = menuBarManager.scrollSpeed.scale
        touchHandler?.start()
        
        // Wire up settings changes
        menuBarManager.onTrackpadModeChanged = { [weak self] mode in
            self?.touchHandler?.trackpadMode = mode
        }
        menuBarManager.onScrollSpeedChanged = { [weak self] speed in
            self?.touchHandler?.scrollScale = speed.scale
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cleanup()
        return .terminateNow
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }
    
    private func cleanup() {
        touchHandler?.stop()
        remoteDetector?.stopDetection()
        mediaKeyInterceptor?.stop()
    }
    
    // MARK: - Media Key Handling
    
    private func handleInterceptedMediaKey(_ keyType: MediaKeyInterceptor.MediaKeyType) -> Bool {
        let buttonName: String
        let defaultAction: String
        
        switch keyType {
        case .playPause:
            buttonName = "playPause"
            defaultAction = "Play/Pause"
        case .next:
            buttonName = "nextTrack"
            defaultAction = "Next Track"
        case .previous:
            buttonName = "prevTrack"
            defaultAction = "Previous Track"
        case .volumeUp:
            buttonName = "volumeUp"
            defaultAction = "Volume Up"
        case .volumeDown:
            buttonName = "volumeDown"
            defaultAction = "Volume Down"
        case .mute:
            return false
        }
        
        // Check if RemoteInputHandler just processed this button (prevent double-processing)
        let currentTime = mach_absolute_time()
        if RemoteInputHandler.lastProcessedButton == buttonName {
            let timeSinceLastProcess = Double(currentTime - RemoteInputHandler.lastProcessedTime) / 1_000_000_000.0
            if timeSinceLastProcess < 0.2 { // Within 200ms debounce window
                // RemoteInputHandler already handled this, consume the event but don't process again
                return true
            }
        }
        
        let action = menuBarManager.getMapping(for: buttonName)
        
        if action == .none {
            return true // Consume but do nothing
        }
        
        if action.rawValue == defaultAction {
            return false // Let system handle default
        }
        
        menuBarManager.executeAction(action.rawValue)
        return true
    }
    
    // MARK: - Permissions
    
    private func checkAccessibilityPermissions() {
        // macOS will show its own prompt when needed
        // No need for redundant custom alert
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
