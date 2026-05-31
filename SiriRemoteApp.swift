//
//  SiriRemoteApp.swift
//  Remotastic
//
//  Menu bar application for controlling Mac with Siri Remote
//

import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import GameController

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem!
    private var menuBarManager: MenuBarManager!
    private var remoteDetector: RemoteDetector?
    private var remoteInputHandler: RemoteInputHandler?
    private var mediaKeyInterceptor: MediaKeyInterceptor?
    private var touchHandler: TouchHandler?
    private var isPaused = false
    private var lastConnectedDevice: IOHIDDevice?
    
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
        menuBarManager.mediaController = mediaController
        
        remoteInputHandler = RemoteInputHandler(
            cursorController: cursorController,
            mediaController: mediaController,
            menuBarManager: menuBarManager
        )
        
        menuBarManager.onTogglePause = { [weak self] in
            self?.togglePause()
        }

        // Start touch handler FIRST (before HID seizure) so MultitouchSupport can initialize
        touchHandler = TouchHandler(cursorController: cursorController)
        touchHandler?.scrollScale = menuBarManager.scrollSpeed.scale
        touchHandler?.cursorScale = menuBarManager.cursorSpeed.scale
        touchHandler?.start()
        remoteInputHandler?.onButtonActivity = { [weak self] in
            self?.touchHandler?.tryReconnectTrackpad()
        }

        // Start remote detection
        remoteDetector = RemoteDetector { [weak self] device in
            DispatchQueue.main.async {
                self?.lastConnectedDevice = device
                if !(self?.isPaused ?? false) {
                    self?.remoteInputHandler?.setRemoteDevice(device)
                }
                self?.menuBarManager.updateConnectionStatus(connected: device != nil)
            }
        }
        remoteDetector?.startDetection()
        menuBarManager.onCursorSpeedChanged = { [weak self] speed in
            self?.touchHandler?.cursorScale = speed.scale
        }
        
        // Request Input Monitoring so media key tap works in both CLI and .app
        if #available(macOS 10.15, *) {
            if !CGPreflightListenEventAccess() {
                CGRequestListenEventAccess()
            }
        }
        
        // Start media key interceptor
        mediaKeyInterceptor = MediaKeyInterceptor()
        mediaKeyInterceptor?.onMediaKey = { [weak self] keyType in
            guard let self = self else { return false }
            return self.handleInterceptedMediaKey(keyType)
        }
        mediaKeyInterceptor?.start()
        
        // Wire up settings changes

        // GameController diagnostic
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { note in
            if let controller = note.object as? GCController {
                print("[GC] Controller connected: \(controller.vendorName ?? "Unknown")")
                print("[GC]   microGamepad: \(controller.microGamepad != nil)")
                print("[GC]   extendedGamepad: \(controller.extendedGamepad != nil)")
                print("[GC]   physicalInputProfile elements: \(controller.physicalInputProfile.elements.count)")
                if let micro = controller.microGamepad {
                    micro.dpad.valueChangedHandler = { dpad, xValue, yValue in
                        print("[GC] dpad x=\(xValue) y=\(yValue)")
                    }
                    micro.buttonA.valueChangedHandler = { button, value, pressed in
                        print("[GC] buttonA pressed=\(pressed) value=\(value)")
                    }
                }
                for (name, element) in controller.physicalInputProfile.elements {
                    print("[GC]   element: \(name) type=\(type(of: element))")
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { note in
            if let controller = note.object as? GCController {
                print("[GC] Controller disconnected: \(controller.vendorName ?? "Unknown")")
            }
        }
        for controller in GCController.controllers() {
            print("[GC] Existing controller: \(controller.vendorName ?? "Unknown")")
        }

        // Attempt to discover Siri Remote as a wireless game controller
        print("[GC] Starting wireless controller discovery...")
        GCController.startWirelessControllerDiscovery {
            print("[GC] Wireless controller discovery completed")
        }

        // Poll for controllers periodically
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            let controllers = GCController.controllers()
            if !controllers.isEmpty {
                print("[GC] Polling found \(controllers.count) controller(s):")
                for c in controllers {
                    print("[GC]   \(c.vendorName ?? "Unknown") micro=\(c.microGamepad != nil) extended=\(c.extendedGamepad != nil)")
                }
            }
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

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            touchHandler?.isEnabled = false
            remoteInputHandler?.isEnabled = false
            menuBarManager.updatePauseStatus(paused: true)
            print("⏸️ Mapping paused")
        } else {
            touchHandler?.isEnabled = true
            remoteInputHandler?.isEnabled = true
            menuBarManager.updatePauseStatus(paused: false)
            print("▶️ Mapping resumed")
        }
    }

    // MARK: - Media Key Handling

    /// Convert mach_absolute_time() delta to seconds (machine ticks vary; use timebase).
    private static let machTimebase: (numer: UInt32, denom: UInt32) = {
        var info = mach_timebase_info_data_t(numer: 0, denom: 0)
        guard mach_timebase_info(&info) == 0 else { return (1, 1) }
        return (info.numer, info.denom)
    }()

    private static func machDeltaToSeconds(from start: UInt64) -> Double {
        guard start > 0 else { return .infinity }
        let now = mach_absolute_time()
        let delta = now >= start ? (now - start) : 0
        let nanos = delta * UInt64(Self.machTimebase.numer) / UInt64(Self.machTimebase.denom)
        return Double(nanos) / 1_000_000_000.0
    }
    
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
        if RemoteInputHandler.lastProcessedButton == buttonName {
            let timeSinceLastProcess = Self.machDeltaToSeconds(from: RemoteInputHandler.lastProcessedTime)
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
            return true // HID path is the single source for all media keys; consume system events
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
