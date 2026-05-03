# PhotoEditor

A SwiftUI iOS photo editor app with photo import, live adjustments, preset filters, rotation, and save-to-library support.

## Features

- Import a photo from the iOS photo library
- Apply preset Core Image filters
- Adjust brightness, contrast, and saturation
- Rotate left or right in 90-degree steps
- Reset edits without losing the selected source photo
- Save the edited image back to Photos

## Requirements

- Xcode 16 or newer
- iOS 17 simulator or device target
- macOS with Apple development tooling

## Open and Run

1. Open `PhotoEditor.xcodeproj` in Xcode.
2. Select the `PhotoEditor` scheme.
3. Choose an iPhone simulator or connected device.
4. Build and run.

## Notes

- The app requests photo library access for both picking and saving images.
- `AppIcon` is currently a placeholder asset set without icon image files.
- Update the bundle identifier in Xcode before shipping.
