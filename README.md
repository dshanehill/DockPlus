# Dock+

Dock+ keeps related Mac apps together in named folders on your Dock. Open a folder to reveal its app shortcuts, then hover over another folder’s Dock icon to switch between them.

Created by a partially blind Mac user, Dock+ grew out of the need to keep apps easy to find and launch while using full-screen magnification. Its folder bubbles sit above the Dock, leaving room for fully magnified icons, and hover switching makes moving between folders easier.

A native management window lets you create folders, choose their symbols, and manage their apps, with labeled controls for accessibility.

**Status:** Early development. Hover switching and accessibility behavior are still being refined. This is a source release, not a signed and notarized installer.

## Features

- Named Dock folders with a choice of symbols and colors.
- App shortcuts in a bubble above each folder’s Dock icon.
- Hover switching between folders with Dock+ running in the background.
- A native sidebar and app-management window.
- Command–N to create a folder; Command–O to add apps.
- Bubble spacing that accounts for maximum Dock magnification.
- No Add App tile inside folder bubbles: management stays in the main window.

## Requirements

- macOS 13 or later.
- Apple Silicon is the currently tested architecture. The build script also targets Intel when run on an Intel Mac; that configuration has not been tested.
- Apple’s Xcode Command Line Tools and Python 3 to build from source.

## Build and install

Clone this repository, then run:

```sh
./scripts/build.sh
```

The result is `build/Dock+.app`. In Finder, copy it to your Applications folder and open it. Keep one installed copy so macOS associates permissions with the correct app.

The local build uses an ad hoc code signature. It is not signed with an Apple Developer ID or notarized. The build script does not change Gatekeeper settings or install anything automatically.

## Getting started

1. Open Dock+ and choose **New Folder** or press Command–N.
2. Name the folder and choose its symbol. Dock+ creates a folder app in your user Applications folder and pins it to the Dock. Adding a folder briefly restarts the Dock.
3. Select the folder in the sidebar and choose **Add Apps** or press Command–O.
4. Click its Dock icon to open its shortcuts. Move the mouse to another folder icon to switch without clicking again.
5. Close the window or press Command–Q when you are finished managing folders. Dock+ stays in the background to keep hover switching available. To stop it completely, reopen Dock+ and choose **Dock+ → Quit Dock+ and Stop Switching**.

Removing an app from a folder removes only the shortcut. The app stays installed.

## Accessibility and magnification

Dock+ was developed around everyday use with full-screen magnification. Bubbles leave clearance for enlarged Dock icons, and the management window uses native controls and accessibility labels.

Accessibility work is ongoing. VoiceOver, multiple displays, different Dock positions, and different magnification configurations have not all been comprehensively tested. Please report situations where controls are hard to reach or bubbles overlap the Dock.

## Permission and privacy

Hover switching requires **System Settings → Privacy & Security → Accessibility → Dock+**. This lets Dock+ identify the folder icon beneath the pointer. macOS may ask for your login password when enabling access; enter it in the macOS dialog, not in an issue or chat.

Dock+ stores folder membership and preferences locally. This source contains no analytics, network requests, or telemetry. It writes a local diagnostic log at `~/Library/Logs/Dock+.log`. Review logs before sharing them because they can contain app names and local paths.

If macOS shows access enabled but hover switching does not work, remove the old Dock+ entry and add the installed copy again. Rebuilding or moving an app can require permission to be refreshed.

## Known limitations

- Hover switching is experimental; its timing and transitions are still being refined.
- Hover detection stays running in the background when the main window is closed. Use the explicit **Quit Dock+ and Stop Switching** command to exit completely.
- Folder creation changes the Dock’s saved app list and restarts the Dock.
- There is not yet a folder rename or deletion interface. Folder apps are separate `.app` bundles in your user Applications folder.
- This public version uses its own app identifiers. It does not automatically import folders from earlier personal prototypes.
- The app and generated folder apps use local ad hoc signatures.

## Contributing

Bug reports and improvements are welcome. For a hover or layout issue, include your macOS version, Dock position, Dock magnification setting, and whether you use full-screen magnification or multiple displays. Do not include passwords or private information.

## License

MIT. See [LICENSE](LICENSE).
