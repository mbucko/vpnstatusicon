# VPNStatusIcon

A lightweight macOS menu bar app that shows ExpressVPN connection status and provides quick connect/disconnect controls.

## Features

- Shield icon in the menu bar showing connection status at a glance
- Displays current IP address and connection duration
- One-click connect/disconnect
- Launch at Login support
- Menu-bar only (no Dock icon)

## Requirements

- macOS 14+
- ExpressVPN with the "ExpressVPN Lightway" network service configured

## Build

```bash
swift build
```

Or open the package in Xcode:

```bash
open Package.swift
```

## Install

```bash
swift build -c release
cp .build/release/VPNStatusIcon /usr/local/bin/
```

## How It Works

Polls `scutil --nc status "ExpressVPN Lightway"` every 3 seconds and uses `scutil --nc start/stop` for connection control.

## License

MIT
