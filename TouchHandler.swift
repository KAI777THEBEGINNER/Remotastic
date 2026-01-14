//
//  TouchHandler.swift
//  Remotastic
//
//  Handles Siri Remote trackpad input using Apple's private MultitouchSupport.framework
//

import Foundation
import CoreGraphics
import AppKit

private func touchCallback(device: MTDevice?,
                           touches: UnsafeMutablePointer<MTTouch>?,
                           numTouches: Int,
                           timestamp: Double,
                           frame: Int,
                           refcon: UnsafeMutableRawPointer?) {
    guard let refcon = refcon else { return }
    let handler = Unmanaged<TouchHandler>.fromOpaque(refcon).takeUnretainedValue()
    handler.handleTouches(touches: touches, count: numTouches, timestamp: timestamp)
}

class TouchHandler {
    
    private let cursorController: CursorController
    private var device: MTDevice?
    private var reconnectTimer: Timer?
    
    var trackpadMode: TrackpadMode = .cursor
    var scrollScale: CGFloat = 150.0
    
    private var lastTouchPosition: CGPoint?
    private var lastTouchCount = 0
    private var lastTouchTime: UInt64 = 0
    private var touchStartTime: UInt64 = 0
    private var touchStartPosition: CGPoint = .zero
    
    private let cursorScale: CGFloat = 500.0
    private let tapMaxDuration: Double = 0.25
    private let tapMaxDistance: CGFloat = 0.05
    private let reconnectInterval: TimeInterval = 2.0
    private let idleTimeout: TimeInterval = 90.0
    
    init(cursorController: CursorController) {
        self.cursorController = cursorController
    }
    
    deinit {
        stop()
    }
    
    func start() {
        findAndStartDevice()
        startReconnectTimer()
    }
    
    func stop() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        stopDevice()
    }
    
    private func findAndStartDevice() {
        guard let cfArray = MTDeviceCreateList()?.takeRetainedValue() else { return }
        let deviceList = cfArray as [MTDevice]
        
        // Find non-built-in device (Siri Remote)
        for dev in deviceList {
            if !MTDeviceIsBuiltIn(dev) {
                startDevice(dev)
                return
            }
        }
        
        // Fallback: use second device if available
        if deviceList.count > 1 {
            startDevice(deviceList[1])
        }
    }
    
    private func startDevice(_ dev: MTDevice) {
        stopDevice()
        device = dev
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        MTRegisterContactFrameCallbackWithRefcon(dev, touchCallback, refcon)
        MTDeviceStart(dev, 0)
        print("📱 Trackpad device connected and started")
    }
    
    private func stopDevice() {
        guard let dev = device else { return }
        MTUnregisterContactFrameCallback(dev, touchCallback)
        MTDeviceStop(dev)
        device = nil
        
        print("📱 Trackpad device disconnected")
        lastTouchPosition = nil
        lastTouchCount = 0
    }
    
    private func startReconnectTimer() {
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectInterval, repeats: true) { [weak self] _ in
            self?.checkAndReconnect()
        }
    }
    
    private func checkAndReconnect() {
        let timeSinceLastTouch = Double(mach_absolute_time() - lastTouchTime) / 1_000_000_000.0
        
        guard let cfArray = MTDeviceCreateList()?.takeRetainedValue() else { return }
        let deviceCount = CFArrayGetCount(cfArray)
        
        let shouldReconnect = device == nil || (timeSinceLastTouch > idleTimeout && deviceCount > 1)
        
        if shouldReconnect && deviceCount > 1 {
            findAndStartDevice()
        }
    }
    
    func handleTouches(touches: UnsafeMutablePointer<MTTouch>?, count: Int, timestamp: Double) {
        lastTouchTime = mach_absolute_time()
        
        guard count > 0, let touchPtr = touches else {
            // Touch ended
            handleTouchEnd()
            lastTouchPosition = nil
            lastTouchCount = 0
            return
        }
        
        // Calculate average position of all active touches
        var avgX: Float = 0
        var avgY: Float = 0
        var activeTouchCount = 0
        
        for i in 0..<count {
            let touch = touchPtr[i]
            
            // Only process active touches
            if touch.state == MTTouchStateTouching || touch.state == MTTouchStateMakeTouch {
                avgX += touch.normalizedVector.position.x
                avgY += touch.normalizedVector.position.y
                activeTouchCount += 1
            }
        }
        
        guard activeTouchCount > 0 else {
            handleTouchEnd()
            lastTouchPosition = nil
            lastTouchCount = 0
            return
        }
        
        avgX /= Float(activeTouchCount)
        avgY /= Float(activeTouchCount)
        
        let currentPos = CGPoint(x: CGFloat(avgX), y: CGFloat(avgY))
        
        // Handle touch start
        if lastTouchPosition == nil {
            touchStartTime = mach_absolute_time()
            touchStartPosition = currentPos
            lastTouchPosition = currentPos
            lastTouchCount = activeTouchCount
            return
        }
        
        // Calculate delta
        let deltaX = currentPos.x - (lastTouchPosition?.x ?? currentPos.x)
        let deltaY = currentPos.y - (lastTouchPosition?.y ?? currentPos.y)
        
        // Process based on finger count and trackpad mode
        if activeTouchCount == 1 && lastTouchCount == 1 {
            // Single finger behavior depends on mode
            if trackpadMode == .cursor {
                let clamped = moveCursor(deltaX: deltaX, deltaY: deltaY)
                
                // Only advance touch tracking if cursor wasn't clamped in that direction
                // This prevents desync when cursor hits screen edge
                if let lastPos = lastTouchPosition {
                    let adjustedDeltaX = clamped.clampedX ? 0 : deltaX
                    let adjustedDeltaY = clamped.clampedY ? 0 : deltaY
                    lastTouchPosition = CGPoint(
                        x: lastPos.x + adjustedDeltaX,
                        y: lastPos.y + adjustedDeltaY
                    )
                } else {
                    lastTouchPosition = currentPos
                }
            } else {
                performScroll(deltaX: deltaX, deltaY: deltaY)
                lastTouchPosition = currentPos
            }
        } else if activeTouchCount == 2 && lastTouchCount == 2 {
            // Two fingers: always scroll regardless of mode
            performScroll(deltaX: deltaX, deltaY: deltaY)
            lastTouchPosition = currentPos
        } else {
            lastTouchPosition = currentPos
        }
        
        lastTouchCount = activeTouchCount
    }
    
    private func handleTouchEnd() {
        guard lastTouchPosition != nil else { return }
        
        // Don't trigger tap if physical click button is active
        if cursorController.isClickActive {
            return
        }
        
        // Check for tap gesture (quick touch with minimal movement)
        let duration = Double(mach_absolute_time() - touchStartTime) / 1_000_000_000.0
        let movement = hypot(
            (lastTouchPosition?.x ?? 0) - touchStartPosition.x,
            (lastTouchPosition?.y ?? 0) - touchStartPosition.y
        )
        
        if duration < tapMaxDuration && movement < tapMaxDistance {
            DispatchQueue.main.async { [weak self] in
                self?.cursorController.performClick()
            }
        }
    }
    
    private func moveCursor(deltaX: CGFloat, deltaY: CGFloat) -> (clampedX: Bool, clampedY: Bool) {
        let scaledX = deltaX * cursorScale
        let scaledY = -deltaY * cursorScale
        
        var clamped = (clampedX: false, clampedY: false)
        
        if Thread.isMainThread {
            clamped = cursorController.moveCursor(deltaX: scaledX, deltaY: scaledY)
        } else {
            DispatchQueue.main.sync {
                clamped = cursorController.moveCursor(deltaX: scaledX, deltaY: scaledY)
            }
        }
        
        return clamped
    }
    
    private func performScroll(deltaX: CGFloat, deltaY: CGFloat) {
        let scrollX = Int32(-deltaX * scrollScale)
        let scrollY = Int32(deltaY * scrollScale)
        
        DispatchQueue.main.async { [weak self] in
            self?.cursorController.scroll(deltaX: scrollX, deltaY: scrollY)
        }
    }
}
