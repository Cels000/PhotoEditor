# PhotoEditorTests — Manual Setup Required

These XCTest files will not compile or run until a test target is added to
`PhotoEditor.xcodeproj`. The Linux dev environment cannot safely edit
`project.pbxproj`, so this step must be done in Xcode on a Mac.

## Steps (one-time)

1. Open `PhotoEditor.xcodeproj` in Xcode.
2. File → New → Target… → iOS → Unit Testing Bundle.
3. Product Name: `PhotoEditorTests`. Target to be Tested: `PhotoEditor`. Language: Swift.
4. Click Finish. Xcode will create a `PhotoEditorTests/` group with a default
   `PhotoEditorTests.swift` file. Delete that default file.
5. In the Project navigator, right-click the `PhotoEditorTests` group →
   "Add Files to PhotoEditor…". Select the existing files in
   `PhotoEditorTests/` on disk (`AdjustmentStackTests.swift`,
   `PipelineBuilderTests.swift`). Add them to the `PhotoEditorTests` target only.
6. Run with ⌘U or `xcodebuild test -project PhotoEditor.xcodeproj -scheme PhotoEditor -destination 'platform=iOS Simulator,name=iPhone 15'`.

## Expected Result

- `AdjustmentStackTests` passes after Plan 01-01 lands.
- `PipelineBuilderTests` passes after Plan 01-03 lands `PipelineBuilder.build`.
