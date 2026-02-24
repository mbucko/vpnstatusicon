# VPNStatusIcon

A lightweight macOS menu bar app that shows ExpressVPN connection status and provides quick connect/disconnect controls.

## Features

- Color-coded shield icon in the menu bar (green = connected, white = disconnected, yellow = transitioning)
- Displays current IP address (click to copy) and connection duration
- One-click connect/disconnect
- Handles ExpressVPN's on-demand auto-reconnect — disconnect actually stays disconnected
- Launch at Login support via LaunchAgent
- Menu-bar only (no Dock icon)

## Requirements

- macOS 14+
- ExpressVPN with the "ExpressVPN Lightway" network service configured

## Build & Install

```bash
swift build -c release

# Create app bundle
mkdir -p ~/Applications/VPNStatusIcon.app/Contents/MacOS
cp .build/release/VPNStatusIcon ~/Applications/VPNStatusIcon.app/Contents/MacOS/
cp VPNStatusIcon/Info.plist ~/Applications/VPNStatusIcon.app/Contents/

# Launch
open ~/Applications/VPNStatusIcon.app
```

Or open in Xcode:

```bash
open Package.swift
```

## Auto-Start on Login

Create `~/Library/LaunchAgents/com.mbucko.vpnstatusicon.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mbucko.vpnstatusicon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>/Users/YOUR_USERNAME/Applications/VPNStatusIcon.app</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

Then load it:

```bash
launchctl load ~/Library/LaunchAgents/com.mbucko.vpnstatusicon.plist
```

## How It Works

Polls `scutil --nc status "ExpressVPN Lightway"` every 3 seconds and uses `scutil --nc start/stop` for connection control.

When disconnecting, a rapid 0.5-second enforcer timer prevents ExpressVPN's VPN On Demand from auto-reconnecting. This is necessary because ExpressVPN sets `OnDemandEnabled: TRUE` with an unconditional connect rule, and there's no public API to toggle another app's on-demand configuration.

## License

MIT
