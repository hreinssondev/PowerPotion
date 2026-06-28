# PowerPotion

PowerPotion is a macOS menu bar app that bundles a few focused desktop power tools:

- Picture-in-picture for arbitrary windows
- Dock organization with saved app slots
- Automatic window tiling and focus groups
- Menu bar icon customization

The source is a native SwiftUI/AppKit Xcode project.

## Requirements

- macOS 26.4 SDK or newer
- Xcode 26.5 or newer
- Accessibility and screen recording permissions for the features that move or capture windows

## Building

1. Clone the repository.
2. Open `CoolAeid.xcodeproj` in Xcode.
3. Select the `CoolAeid` target.
4. Choose your own development team/signing settings if you want to run a signed build.
5. Build and run.

For a local unsigned command-line build:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app xcodebuild \
  -project CoolAeid.xcodeproj \
  -scheme CoolAeid \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

## Project Layout

- `CoolAeid/AnyPIP`: arbitrary-window picture-in-picture features
- `CoolAeid/DockMover`: Dock slot and layout management
- `CoolAeid/WindowBuddy`: window tiling and focus-group behavior
- `CoolAeid/Assets.xcassets`: app icon and color assets

## Privacy

PowerPotion uses macOS accessibility and screen capture APIs locally on your Mac. The project does not include network services, analytics, telemetry, or bundled third-party SDKs.

## License

MIT. See `LICENSE`.
