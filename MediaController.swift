//
//  MediaController.swift
//  Remotastic
//
//  Sends system media key events
//

import AppKit

enum MediaKey {
    case playPause, next, previous, volumeUp, volumeDown, mute
    
    var keyCode: Int32 {
        switch self {
        case .playPause: return NX_KEYTYPE_PLAY
        case .next: return NX_KEYTYPE_NEXT
        case .previous: return NX_KEYTYPE_PREVIOUS
        case .volumeUp: return NX_KEYTYPE_SOUND_UP
        case .volumeDown: return NX_KEYTYPE_SOUND_DOWN
        case .mute: return NX_KEYTYPE_MUTE
        }
    }
}

class MediaController {
    
    func sendMediaKey(_ key: MediaKey) {
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key.keyCode << 16) | (0xa << 8)),
            data2: -1
        )
        
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key.keyCode << 16) | (0xb << 8)),
            data2: -1
        )
        
        keyDown?.cgEvent?.post(tap: .cghidEventTap)
        usleep(30000)
        keyUp?.cgEvent?.post(tap: .cghidEventTap)
    }
}
