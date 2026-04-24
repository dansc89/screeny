# Screeny

Screeny is a free, open source macOS screenshot utility written in Swift.

It behaves like the built-in screenshot flow, but always pauses in a fast markup editor before save, and always copies the final marked-up image to your clipboard.

## Features

- Menu bar app built with SwiftUI + AppKit
- Global hotkeys for:
- `Cmd + Shift + 3` for full screen capture
- `Cmd + Shift + 4` for interactive area capture
- `Cmd + Shift + 4`, then `Space`, for window capture
- Built-in markup tools before save:
- Pen
- Rectangle
- Arrow
- `Copy` button for clipboard-only output
- `Save + Copy` for file output plus clipboard
- Closing the preview window auto-copies the current markup to clipboard
- Saves PNG files to your chosen location (defaults to Pictures)
- Automatically registers itself to launch at login (run once and it stays enabled)

## Requirements

- macOS 14+
- Swift 6.2+

## Build and run

```bash
swift build
swift run Screeny
```

After first launch, Screeny installs a user LaunchAgent so it starts automatically each login.

## Ship a signed `.app` and `.dmg`

Build a signed app bundle, install it to `~/Applications`, and create a signed DMG:

```bash
./Scripts/package-release.sh
```

Artifacts:

- `dist/Screeny.app`
- `dist/Screeny-v0.1.0.dmg` (version derives from your latest git tag)

Optional notarization (required for full Gatekeeper trust on other Macs):

```bash
SCREENY_NOTARIZE=1 ./Scripts/package-release.sh
```

`Scripts/notarize-release.sh` defaults to keychain profile `drawbridge-notary`. Override with:

- `SCREENY_NOTARY_PROFILE`
- or `SCREENY_NOTARY_APPLE_ID`, `SCREENY_NOTARY_TEAM_ID`, `SCREENY_NOTARY_APP_PASSWORD`

## Permissions

On first use, macOS may request:

- Screen Recording permission (for capturing screen content)

Grant permission in `System Settings > Privacy & Security > Screen Recording` if prompted.

If macOS still reports Screeny as unauthorized after you already enabled it, toggle Screeny off/on in that panel and fully relaunch Screeny.

## Important shortcut note

macOS system screenshot shortcuts may take precedence over third-party hotkeys.

If you want Screeny to own `Cmd + Shift + 3/4`, disable or remap Apple's screenshot shortcuts in:

`System Settings > Keyboard > Keyboard Shortcuts > Screenshots`

## License

MIT
