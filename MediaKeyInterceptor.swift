//
//  MediaKeyInterceptor.swift
//  Remotastic
//
//  Intercepts system media key events to prevent default handling
//

import Cocoa
import CoreGraphics

class MediaKeyInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    var onMediaKey: ((MediaKeyType) -> Bool)?
    
    enum MediaKeyType {
        case playPause, next, previous, volumeUp, volumeDown, mute
    }
    
    func start() {
        let eventMask: CGEventMask = 1 << 14 // NX_SYSDEFINED
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return interceptor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // NX_SYSDEFINED = 14
        guard type.rawValue == 14 else {
            return Unmanaged.passRetained(event)
        }
        
        // Get NSEvent to parse the media key
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passRetained(event)
        }
        
        // Check subtype 8 = media key event
        guard nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(event)
        }
        
        // Parse the key code from data1
        let keyCode = Int32((nsEvent.data1 & 0xFFFF0000) >> 16)
        let keyFlags = nsEvent.data1 & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isKeyDown = keyState == 0x0A
        
        // Only handle key down events
        guard isKeyDown else {
            return Unmanaged.passRetained(event)
        }
        
        // Identify the media key
        var mediaKey: MediaKeyType?
        switch keyCode {
        case NX_KEYTYPE_PLAY:
            mediaKey = .playPause
        case NX_KEYTYPE_NEXT, NX_KEYTYPE_FAST:
            mediaKey = .next
        case NX_KEYTYPE_PREVIOUS, NX_KEYTYPE_REWIND:
            mediaKey = .previous
        case NX_KEYTYPE_SOUND_UP:
            mediaKey = .volumeUp
        case NX_KEYTYPE_SOUND_DOWN:
            mediaKey = .volumeDown
        case NX_KEYTYPE_MUTE:
            mediaKey = .mute
        default:
            break
        }
        
        if let key = mediaKey, let handler = onMediaKey, handler(key) {
            return nil // Consume event
        }
        
        return Unmanaged.passRetained(event)
    }
    
    deinit {
        stop()
    }
}
