# VPNStatusIcon

A lightweight, modern macOS menu bar app that shows VPN connection status for ExpressVPN.

## Features

- **Efficient Monitoring**: Uses `NWPathMonitor` for instant updates without constant polling.
- **Modern Tech**: Built with Swift 5.9, targeting macOS 14+, using the `Observation` framework and `async/await`.
- **Dynamic Icons**: Color-coded shield icon (Green = Connected, Yellow = Transitioning, White = Disconnected).
- **Network Info**: Choose to show ExpressVPN Tunnel (10.x), Local IP (en0), or Public VPN IP in the menu bar.
- **Copy IP**: Click the Public VPN IP in the menu to copy it to your clipboard.
- **Launch at Login**: Easily enable auto-start via a simple toggle.
- **Stealthy**: Menu-bar only — no Dock icon.

## Requirements

- macOS 14.0 or later

## Build & Install

```bash
# Build the release binary
swift build -c release

# Create a proper App Bundle
mkdir -p ~/Applications/VPNStatusIcon.app/Contents/MacOS
mkdir -p ~/Applications/VPNStatusIcon.app/Contents/Resources
cp .build/release/VPNStatusIcon ~/Applications/VPNStatusIcon.app/Contents/MacOS/
cp VPNStatusIcon/Info.plist ~/Applications/VPNStatusIcon.app/Contents/

# Open the app
open ~/Applications/VPNStatusIcon.app
```

## How It Works

- **Trigger**: When your network path changes, the app uses `scutil --nc status` to check the current state of ExpressVPN.
- **Process**: Status checks are performed asynchronously to prevent UI hitches.
- **Network**: Local IP is detected by scanning all active network interfaces (not just `en0`). Public IP is fetched from `api.ipify.org` with a 60-second TTL cache.

## Troubleshooting

If "Launch at Login" doesn't work, ensure you have built the `.app` bundle as described above and moved it to your `/Applications` or `~/Applications` folder. The `SMAppService` requires the app to have a valid bundle identifier (`com.mbucko.VPNStatusIcon`) and be located in a standard application directory.

## License

MIT
