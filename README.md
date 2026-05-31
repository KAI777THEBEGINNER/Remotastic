# Siri Remote for macOS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> A fork of [Remotastic](https://github.com/laurentschuermans/Remotastic) by Laurent Schuermans. This project builds upon the original work with additional device support, UI improvements, and enhanced stability.
>
> [中文说明](README_CN.md)

Control your Mac with your Apple TV Siri Remote — a lightweight menu bar app that turns your Siri Remote into a trackpad and media controller.

## Features

- **True Trackpad Experience**: Smooth cursor movement with the Siri Remote touch surface, including clicking, dragging, and two-finger scrolling
- **Customizable Button Mappings**: Remap any remote button to media controls, mouse actions, or keyboard shortcuts
- **Pause / Resume**: Instantly toggle all mappings on/off to avoid interfering with your Magic Trackpad during work
- **Cursor & Scroll Speed**: Adjust trackpad sensitivity directly from the menu bar
- **Multi-Monitor Support**: Cursor works across all displays
- **Auto-Reconnect**: Automatically recovers after remote sleep or Bluetooth reconnection
- **Menu Bar Integration**: Quick access to settings, connection status, and pause toggle

## Supported Devices

Tested with the following Apple TV Siri Remote models:

| Vendor ID | Product ID | Model |
|-----------|------------|-------|
| 0x004C    | 0x0315     | Apple TV Remote (2021 / 3rd gen) |
| 0x004C    | 0x030E     | Siri Remote (2nd gen) |
| 0x004C    | 0x030D     | Siri Remote (2nd gen, alternate) |
| 0x004C    | 0x0269     | Siri Remote (1st gen) |
| 0x004C    | 0x0267     | Siri Remote (1st gen, alternate) |
| 0x004C    | 0x0266     | Siri Remote (1st gen, alternate) |
| 0x004C    | 0x0255     | Apple TV Remote (early model) |
| 0x004C    | 0x0221     | Apple TV Remote (early model) |

Other models may work if they expose compatible HID interfaces.

## Installation

**Prerequisites**: macOS 11.0+, Xcode Command Line Tools, an Apple TV Siri Remote paired via Bluetooth.

```bash
git clone https://github.com/KAI777THEBEGINNER/Remotastic.git
cd Remotastic
./build.sh
./create_app_bundle.sh
cp -R Remotastic.app /Applications/
```

Then double-click **Remotastic** in your Applications folder.

## Required Permissions

Siri Remote for macOS requires two system permissions to function:

1. **Accessibility** (System Settings → Privacy & Security → Accessibility)
   - Required for: cursor movement, mouse clicks, and simulated keyboard shortcuts
2. **Input Monitoring** (System Settings → Privacy & Security → Input Monitoring)
   - Required for: intercepting system media keys to prevent duplicate actions

The app will prompt you automatically when a permission is needed.

## Pairing Your Remote

1. On your Siri Remote, press and hold **Menu + Volume Up** for 5 seconds
2. On your Mac, go to **System Settings → Bluetooth**
3. Select your remote from the list and click **Connect**
4. Open Siri Remote for macOS — it will appear in the menu bar automatically

## Usage

Click the **Siri Remote for macOS** menu bar icon to:

- View Bluetooth connection status
- Configure button mappings per app
- Toggle **Pause / Resume** to temporarily disable all remote inputs
- Adjust **Cursor Speed** and **Scroll Speed**

### Default Button Mappings

| Remote Button | Default Action | Description |
|---------------|----------------|-------------|
| **Menu**      | Escape         | Sends Escape key |
| **Siri**      | Fn             | Sends Function key |
| **Play/Pause**| Play/Pause     | System media play/pause |
| **Volume +**  | Volume Up      | System volume up |
| **Volume −**  | Volume Down    | System volume down |
| **TV**        | None           | Unmapped by default |
| **Select**    | Click          | Left mouse click (hold to drag) |
| **Power**     | None           | Unmapped by default |

### Touch Surface Gestures

| Gesture | Action |
|---------|--------|
| **Single-finger swipe** | Move cursor |
| **Single-finger tap**   | Left click |
| **Two-finger swipe**    | Scroll |
| **Press firmly**        | Left click / start drag (hold and swipe to drag) |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Remote shows "Disconnected" | Check Bluetooth pairing, press any remote button to wake it, then wait a few seconds |
| Cursor does not move | Verify **Accessibility** permission is granted to Siri Remote for macOS in System Settings |
| Touch only moves horizontally/vertically | Quit Siri Remote for macOS completely and reopen; ensure no other instance is running |
| System beeps on button press | This means Siri Remote for macOS does not have exclusive HID access; quit and reopen the app |
| Buttons work but touch doesn't | Make sure your remote is fully paired (showing "Connected" in Bluetooth, not just "Paired") |
| Conflict with Magic Trackpad | Use the **Pause** option in the menu bar to temporarily disable Siri Remote for macOS |

## Technical Notes

- **Touch handling** uses Apple's private `MultitouchSupport.framework` to read absolute coordinates from the Siri Remote touch surface
- **Button handling** uses `IOKit.hid` with device seize to prevent macOS from processing remote button events independently
- **Media keys** are intercepted via `CGEventTap` to avoid double-firing when both HID and system AVRCP paths are active
- Not App Store compatible due to private API usage

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License — see [LICENSE](LICENSE) for details.
