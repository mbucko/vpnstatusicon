# VPNStatusIcon

A lightweight, read-only macOS menu bar app that shows ExpressVPN connection status.

## Features

- Color-coded shield icon in the menu bar (green = connected, white = disconnected, yellow = transitioning)
- Displays current IP address (click to copy) and connection duration
- Optional local/public IP display in the menu bar
- Quick-launch ExpressVPN from menu
- Launch at Login support
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

Polls `scutil --nc status "ExpressVPN Lightway"` every 3 seconds to monitor connection state. Read-only — use ExpressVPN directly to connect/disconnect.

## License

MIT
