//
//  RemoteInputHandler.swift
//  Remotastic
//
//  Processes HID input events from Siri Remote
//

import IOKit
import IOKit.hid
import Foundation
import Carbon.HIToolbox
import AppKit

class RemoteInputHandler {
    private let cursorController: CursorController
    private let mediaController: MediaController
    private weak var menuBarManager: MenuBarManager?
    private var devices: [IOHIDDevice] = []
    
    /// Called on any button activity; use to trigger trackpad re-scan after remote wake.
    var onButtonActivity: (() -> Void)?
    
    // First press after connection: do not perform action (sound already played at connect).
    private var isFirstPressAfterConnection = false
    
    // Click/drag state
    private var isSelectPressed = false
    private var selectPressTime: UInt64 = 0
    private var isDragging = false
    private let clickThreshold: Double = 0.25
    
    // Prevent double-processing with MediaKeyInterceptor
    static var lastProcessedButton: String?
    static var lastProcessedTime: UInt64 = 0

    var isEnabled = true {
        didSet {
            if !isEnabled {
                activeDirections.removeAll()
                directionTimer?.invalidate()
                directionTimer = nil
            }
        }
    }

    private var activeDirections: Set<String> = []
    private var directionTimer: Timer?
    private let directionMoveSpeed: CGFloat = 15.0

    init(cursorController: CursorController, mediaController: MediaController, menuBarManager: MenuBarManager) {
        self.cursorController = cursorController
        self.mediaController = mediaController
        self.menuBarManager = menuBarManager
    }
    
    func setRemoteDevice(_ device: IOHIDDevice?) {
        guard let device = device else {
            print("[RemoteInputHandler] setRemoteDevice: disconnecting all")
            for d in devices {
                IOHIDDeviceRegisterInputValueCallback(d, nil, nil)
                IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
                IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            devices.removeAll()
            isFirstPressAfterConnection = false
            return
        }

        guard !devices.contains(where: { $0 == device }) else {
            print("[RemoteInputHandler] setRemoteDevice: device already registered, skipping")
            return
        }

        // Seize device to prevent system from handling events
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        print("[RemoteInputHandler] IOHIDDeviceOpen(seize) result: \(openResult)")

        if openResult == kIOReturnSuccess {
            IOHIDDeviceRegisterInputValueCallback(device, inputValueCallback, Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            devices.append(device)
            isFirstPressAfterConnection = true
            print("[RemoteInputHandler] Callback registered and scheduled (seize). Total devices: \(devices.count)")
            CursorController.playKeyPressFeedback()
        } else {
            // Fallback: open without seize
            let openResult2 = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            print("[RemoteInputHandler] IOHIDDeviceOpen(none) result: \(openResult2)")
            if openResult2 == kIOReturnSuccess {
                IOHIDDeviceRegisterInputValueCallback(device, inputValueCallback, Unmanaged.passUnretained(self).toOpaque())
                IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
                devices.append(device)
                isFirstPressAfterConnection = true
                print("[RemoteInputHandler] Callback registered and scheduled (no seize). Total devices: \(devices.count)")
                CursorController.playKeyPressFeedback()
            } else {
                print("[RemoteInputHandler] Failed to open device (seize and none both failed)")
            }
        }
    }
    
    func handleInputValue(_ value: IOHIDValue) {
        guard isEnabled else { return }
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        print("[RemoteInputHandler] Raw HID event: page=0x\(String(usagePage, radix: 16, uppercase: true)) usage=0x\(String(usage, radix: 16, uppercase: true)) value=\(intValue)")

        guard let buttonName = identifyButton(page: usagePage, usage: usage) else { return }
        
        // Any button activity may cause the remote to re-enumerate; re-scan MT so trackpad can reconnect.
        onButtonActivity?()
        
        // First key-down after connection: do not perform action (sound already played at connect).
        if intValue == 1 && isFirstPressAfterConnection {
            isFirstPressAfterConnection = false
            return
        }
        
        // Handle select button (trackpad click) - distinguish click vs drag
        if buttonName == "select" {
            handleSelectButton(pressed: intValue == 1)
            return
        }

        // Directional buttons: track press and release for continuous cursor movement
        let directionalButtons = ["menuUp", "menuDown", "menuLeft", "menuRight"]
        if directionalButtons.contains(buttonName) {
            handleDirectionButton(buttonName, pressed: intValue == 1)
            return
        }

        // Other buttons: only process on key down
        guard intValue == 1 else { return }
        
        // Mark this button as processed to prevent MediaKeyInterceptor from double-processing
        let currentTime = mach_absolute_time()
        RemoteInputHandler.lastProcessedButton = buttonName
        RemoteInputHandler.lastProcessedTime = currentTime
        
        let action = menuBarManager?.getMapping(for: buttonName) ?? .none
        print("🔘 Button pressed: \(buttonName) → \(action.rawValue)")
        if action != .none {
            CursorController.playKeyPressFeedback()
        }
        executeAction(action)
    }
    
    private func handleSelectButton(pressed: Bool) {
        if pressed && !isSelectPressed {
            isSelectPressed = true
            isDragging = false
            selectPressTime = mach_absolute_time()
            cursorController.isClickActive = true
            
            // Start drag after threshold
            DispatchQueue.main.asyncAfter(deadline: .now() + clickThreshold) { [weak self] in
                guard let self = self, self.isSelectPressed && !self.isDragging else { return }
                print("🔘 Select button: Drag started")
                self.isDragging = true
                self.cursorController.isDragging = true
                self.cursorController.mouseDown()
            }
        } else if !pressed && isSelectPressed {
            isSelectPressed = false
            
            if isDragging {
                print("🔘 Select button: Drag ended")
                cursorController.isDragging = false
                cursorController.mouseUp()
            } else {
                print("🔘 Select button: Click")
                CursorController.playKeyPressFeedback()
                cursorController.performClick()
            }
            isDragging = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.cursorController.isClickActive = false
            }
        }
    }

    // MARK: - Directional Movement

    private func handleDirectionButton(_ direction: String, pressed: Bool) {
        if pressed {
            activeDirections.insert(direction)
        } else {
            activeDirections.remove(direction)
        }

        if !activeDirections.isEmpty && directionTimer == nil {
            directionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.updateDirectionalMovement()
            }
        } else if activeDirections.isEmpty {
            directionTimer?.invalidate()
            directionTimer = nil
        }
    }

    private func updateDirectionalMovement() {
        var deltaX: CGFloat = 0
        var deltaY: CGFloat = 0
        let step = directionMoveSpeed

        if activeDirections.contains("menuRight") { deltaX += step }
        if activeDirections.contains("menuLeft")  { deltaX -= step }
        if activeDirections.contains("menuUp")    { deltaY -= step }
        if activeDirections.contains("menuDown")  { deltaY += step }

        guard deltaX != 0 || deltaY != 0 else { return }

        let work = { [weak self] in
            guard let self = self else { return }
            _ = self.cursorController.moveCursor(deltaX: deltaX, deltaY: deltaY)
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    // MARK: - Button Identification
    
    private func identifyButton(page: UInt32, usage: UInt32) -> String? {
        switch (page, usage) {
        // Generic Desktop Page (0x01)
        case (0x01, 0x86): return "menu"          // System Menu Main
        case (0x01, 0x40): return "menu"          // Menu (alternative)
        
        // Consumer Page (0x0C)  
        case (0x0C, 0x04): return "siri"          // Siri button (actual)
        case (0x0C, 0x60): return "tv"            // TV button (actual)
        case (0x0C, 0x80): return "select"        // Selection
        case (0x0C, 0x41): return "select"        // Menu Select (alternative)
        case (0x0C, 0xCD): return "playPause"     // Play/Pause
        case (0x0C, 0xE9): return "volumeUp"      // Volume Increment
        case (0x0C, 0xEA): return "volumeDown"    // Volume Decrement
        case (0x0C, 0xB5): return "nextTrack"     // Scan Next Track
        case (0x0C, 0xB6): return "prevTrack"     // Scan Previous Track
        case (0x0C, 0x223): return "tv"           // AC Home (TV button alternative)
        case (0x0C, 0x224): return "back"         // AC Back
        case (0x0C, 0x40): return "menu"          // Menu
        case (0x0C, 0x42): return "menuUp"        // Touchpad up (directional)
        case (0x0C, 0x43): return "menuDown"      // Touchpad down (directional)
        case (0x0C, 0x44): return "menuLeft"      // Touchpad left (directional)
        case (0x0C, 0x45): return "menuRight"     // Touchpad right (directional)
        case (0x0C, 0x30): return "power"         // Power
        case (0x0C, 0x20): return "mute"          // Mute (some remotes)
        
        // Button Page (0x09)
        case (0x09, 0x01): return "select"        // Button 1
        
        // Apple Vendor Page (0xFF00) - Siri button
        case (0xFF00, 0x01): return "siri"        // Siri button
        case (0xFF00, 0x02): return "siri"        // Siri button (alternative)
        case (0xFF00, 0x03): return "siri"        // Siri button (alternative)
        case (0xFF00, _): return "siri"           // Any Apple vendor usage = likely Siri
        
        // Telephony Page (0x0B) - sometimes used for Siri
        case (0x0B, 0x21): return "siri"          // Flash
        case (0x0B, 0x2F): return "siri"          // Phone Mute
        
        default: return nil
        }
    }
    
    // MARK: - Action Execution
    
    private func executeAction(_ action: ButtonAction) {
        switch action {
        case .none:
            break
        case .playPause:
            mediaController.sendMediaKey(.playPause)
        case .nextTrack:
            mediaController.sendMediaKey(.next)
        case .previousTrack:
            mediaController.sendMediaKey(.previous)
        case .volumeUp:
            mediaController.sendMediaKey(.volumeUp)
        case .volumeDown:
            mediaController.sendMediaKey(.volumeDown)
        case .mute:
            mediaController.sendMediaKey(.mute)
        case .click:
            cursorController.performClick()
        case .rightClick:
            cursorController.performRightClick()
        case .escape:
            sendKey(kVK_Escape)
        case .space:
            sendKey(kVK_Space)
        case .enter:
            sendKey(kVK_Return)
        case .missionControl:
            sendMissionControlKey()
        case .rightCommand:
            sendRightCommand()
        case .fn:
            sendKey(kVK_Function)
        }
    }

    private func sendRightCommand() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        usleep(80000)
        up?.post(tap: .cghidEventTap)
    }
    
    private func sendMissionControlKey() {
        openMissionControl()
    }
    
    private func sendKey(_ keyCode: Int) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true)?.post(tap: .cghidEventTap)
        usleep(10000)
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: false)?.post(tap: .cghidEventTap)
    }
}

/// Opens Mission Control (one path for CLI and app).
func openMissionControl() {
    let bundleID = "com.apple.exposelauncher"
    if Bundle.main.bundlePath.hasSuffix(".app"),
       let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        return
    }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    proc.arguments = ["-b", bundleID]
    try? proc.run()
}

// C callback
private func inputValueCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
    guard let context = context else { return }
    Unmanaged<RemoteInputHandler>.fromOpaque(context).takeUnretainedValue().handleInputValue(value)
}
