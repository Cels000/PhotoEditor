---
phase: 02-lut-filter-pipeline
verified: 2026-05-03T00:00:00Z
status: human_needed
score: 6/6 must-haves verified
human_verification:
  - test: "Launch app on Mac/device, open a photo — confirm 5 filter thumbnails render in the strip (identity, Warm Fade, Cool Cine, Noir B&W, Sepia)"
    expected: "Horizontal scroll strip appears below the adjustment area; each cell shows a photo-derived thumbnail with the filter applied"
    why_human: "UIKit/CoreImage render path and SwiftUI layout can only be verified at runtime on macOS/iOS"
  - test: "Tap a non-identity filter, then drag the strength slider from 100% to 0%"
    expected: "Preview updates live; slider label shows percentage; at 0% the image matches unfiltered"
    why_human: "Blend correctness and live-preview responsiveness require runtime rendering"
  - test: "Long-press 'Warm Fade' to favorite it; quit and relaunch the app"
    expected: "After long-press, a star badge appears and Warm Fade moves to the front of the strip. After relaunch, it remains favorited and first"
    why_human: "UserDefaults persistence and @Observable re-ordering can only be confirmed at runtime"
  - test: "Run CubeParserTests and PipelineBuilderTests in Xcode after adding the new files to the correct targets"
    expected: "All 6 CubeParserTests methods pass; testIdentityLUTProducesPixelIdenticalOutput, testStrengthZeroReturnsOriginal, testNilCubeResolverReturnsInput pass"
    why_human: "XCTest execution requires Xcode on macOS — cannot run on Linux"
  - test: "Drop a real artist .cube file into Resources/LUTs/ in the app bundle and rebuild"
    expected: "The new filter appears at the end of the strip with a thumbnail derived from its filename as the display name"
    why_human: "Auto-discovery of bundle files requires runtime bundle enumeration"
---

# Phase 2: LUT Filter Pipeline Verification Report

**Phase Goal:** The product's visual identity is established — 5 starter (procedurally-generated) film-look filters with stable IDs are selectable from a live-preview strip, blend strength is controllable, and favorites are persisted. The architecture auto-discovers `.cube` files, supporting future expansion to 20–30 filters. (Scope delta from ROADMAP documented in 02-CONTEXT.md and is intentional.)
**Verified:** 2026-05-03
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | 64-point `ColorCubeData` value type exists with validated init | ✓ VERIFIED | `struct ColorCubeData`, `static let dimension: Int = 64`, `init?(floats:)`, `init?(rgbTriplets:)`, `static func identity()` all present; no `import CoreImage` |
| 2  | `.cube` text parser converts Resolve format → `ColorCubeData`, resampling 33-pt to 64-pt | ✓ VERIFIED | `enum CubeParser` with `parse(text:)`, `resampleTrilinear`, `LUT_3D_SIZE`, `DOMAIN_MIN` parsing; constructs via `ColorCubeData(rgbTriplets:)` |
| 3  | Five procedurally-generated starter LUTs exist with stable string IDs | ✓ VERIFIED | `enum BuiltInLUTs` with `identity`, `warmFade`, `cinematicCool`, `noir`, `sepia` factories; all in `static let all`; IDs like `builtin.identity` locked in source |
| 4  | `FilterLibrary` catalogs filters, puts favorites first, persists to UserDefaults | ✓ VERIFIED | `@Observable final class FilterLibrary`; `orderedFilters`; `toggleFavorite` writes `filter.favorites` key; merges `BuiltInLUTs.all` with bundle `.cube` scan |
| 5  | `PipelineBuilder.applyLUT` applies `CIColorCubeWithColorSpace` in linear sRGB with strength blending | ✓ VERIFIED | `typealias CubeResolver`; `CIFilter.colorCubeWithColorSpace`; `extendedLinearSRGB`; `cubeData = cube.rawData`; `sourceOverCompositing` for partial strength |
| 6  | Filter strip is wired into ContentView; tapping selects filter; long-press toggles favorite; strength slider present | ✓ VERIFIED | `FilterStripView(viewModel: viewModel)` in ContentView; "Coming in Phase 2" placeholder removed; `selectFilter`, `toggleFavorite`, `setFilterStrength`, `onLongPressGesture` all wired |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact | Provides | Status | Details |
|----------|----------|--------|---------|
| `PhotoEditor/Filters/ColorCubeData.swift` | Validated 64-point cube data | ✓ VERIFIED | All required symbols present; pure Foundation |
| `PhotoEditor/Filters/CubeParser.swift` | `.cube` text parser | ✓ VERIFIED | `enum CubeParser`, `resampleTrilinear`, DOMAIN support |
| `PhotoEditor/Filters/BuiltInLUTs.swift` | 5 starter LUT factories + stable IDs | ✓ VERIFIED | All 5 factories, `Descriptor`, `static let all` present |
| `PhotoEditor/Filters/Filter.swift` | Filter model — Identifiable, Equatable | ✓ VERIFIED | `struct Filter: Identifiable, Equatable`; `let id: String`; `func cube()` lazy-loads |
| `PhotoEditor/Filters/FilterLibrary.swift` | @Observable filter catalog + favorites | ✓ VERIFIED | `@Observable final class FilterLibrary`; all required methods present |
| `PhotoEditor/RenderEngine/PipelineBuilder.swift` | Filled-in applyLUT with strength blend | ✓ VERIFIED | `CubeResolver` typealias; full CIColorCubeWithColorSpace impl; strength blend via CISourceOverCompositing |
| `PhotoEditor/Editor/FilterThumbnailCache.swift` | NSCache-backed thumbnail cache | ✓ VERIFIED | `final class FilterThumbnailCache`; NSCache; `renderThumbnail`; `extendedLinearSRGB` |
| `PhotoEditor/Editor/FilterStripView.swift` | Horizontal filter strip + strength slider | ✓ VERIFIED | All required bindings, gestures, and thumbnail rendering present |
| `PhotoEditorTests/CubeParserTests.swift` | 6 parser test methods | ✓ VERIFIED | `testIdentity64Roundtrip`, `test33To64Resample`, `testRejectsInvalidSize` + 3 more |
| `PhotoEditorTests/PipelineBuilderTests.swift` | Identity-LUT pixel test + 2 more | ✓ VERIFIED | `testIdentityLUTProducesPixelIdenticalOutput`, `testStrengthZeroReturnsOriginal`, `testNilCubeResolverReturnsInput` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ColorCubeData` | `CIColorCubeWithColorSpace` | `rawData + dimension` consumed by PipelineBuilder | ✓ WIRED | `cubeData = cube.rawData` in PipelineBuilder |
| `CubeParser.parse(text:)` | `ColorCubeData(rgbTriplets:)` | constructs validated cube | ✓ WIRED | Uses `rgbTriplets:` variant (not `floats:` as plan pattern stated — both are valid inits; this is correct) |
| `BuiltInLUTs` | `ColorCubeData(rgbTriplets:)` | each factory builds 64³×3 float array | ✓ WIRED | `ColorCubeData(rgbTriplets: triplets)!` in `build()` helper |
| `FilterLibrary.init` | `BuiltInLUTs.all` + Bundle scan | merge built-ins with `.cube` files | ✓ WIRED | `for d in BuiltInLUTs.all` then `bundle.url(forResource:)` scan |
| `FilterLibrary.toggleFavorite` | `UserDefaults` | `filter.favorites` key | ✓ WIRED | `userDefaults.set(Array(favorites), forKey: Self.favoritesUserDefaultsKey)` |
| `PipelineBuilder.applyLUT` | `CIColorCubeWithColorSpace` | `rawData + extendedLinearSRGB` | ✓ WIRED | Present in impl; color space explicit |
| `EditorViewModel.stackDidChange` | `RenderEngine.renderPreview(...cubeResolver:)` | resolver closure captures `filterLibrary` | ✓ WIRED | `makeCubeResolver()` called at 2 sites |
| `ContentView.filterStrip` | `FilterStripView(viewModel:)` | replaces Phase 1 placeholder | ✓ WIRED | "Coming in Phase 2" removed; `FilterStripView(viewModel: viewModel)` at line 107 |
| `FilterStripView` long-press | `FilterLibrary.toggleFavorite` | `.onLongPressGesture` | ✓ WIRED | `viewModel.filterLibrary.toggleFavorite(filter.id)` present |

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| FILTER-01 | App ships with film-style LUT filters (5 starters; architecture supports 20–30 via `.cube` auto-discovery) | ✓ SATISFIED | `BuiltInLUTs.all` (5 entries); `FilterLibrary.loadFilters` scans `Resources/LUTs/` |
| FILTER-02 | Horizontal strip with photo-derived thumbnails | ✓ SATISFIED | `FilterStripView` renders `FilterThumbnailCache.renderThumbnail` per filter |
| FILTER-03 | Strength slider 0–100% blends unfiltered → full | ✓ SATISFIED | `setFilterStrength` + `strengthSection` Slider; CISourceOverCompositing blend in PipelineBuilder |
| FILTER-04 | Favorites appear first; persisted | ✓ SATISFIED | `orderedFilters` + `toggleFavorite` + UserDefaults `filter.favorites` |
| FILTER-05 | Stable UUIDs (String IDs) survive library updates | ✓ SATISFIED | `builtin.*` IDs hard-coded; `cube.<lowercased-filename>` for files |
| FILTER-06 | 64-point `CIColorCubeWithColorSpace` in linear sRGB | ✓ SATISFIED | `ColorCubeData.dimension == 64`; `extendedLinearSRGB` explicit in both PipelineBuilder and FilterThumbnailCache |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `ContentView.swift` | 76, 85 | `// TODO: Phase 3 — wire to AdjustmentStack.crop.clockwiseRotations` | ℹ️ Info | Phase 3 work, not Phase 2 scope |
| `BuiltInLUTs.swift` | 4 | `PLACEHOLDERS for visual variety` comment | ℹ️ Info | Intentional documentation per 02-CONTEXT.md |
| `FilterLibrary.swift` | 74 | `return []` in `loadFavorites` guard-else | ℹ️ Info | Correct default-empty-favorites behavior, not a stub |

No blockers or warnings found.

### Human Verification Required

#### 1. Filter Strip Renders Photo-Derived Thumbnails

**Test:** Launch app on Mac/device, import a photo, observe the filter strip
**Expected:** 5 filter cells appear (identity "Original", Warm Fade, Cool Cine, Noir B&W, Sepia), each showing the imported photo rendered through that LUT
**Why human:** UIKit/CoreImage render path and SwiftUI layout require runtime on macOS/iOS

#### 2. Strength Slider Blends Preview Live

**Test:** Select "Warm Fade", drag the strength slider from 100% to 0% and back
**Expected:** Preview canvas updates continuously; at 0% the image is indistinguishable from unfiltered; at 100% full warm-fade color grade is applied
**Why human:** Live-preview responsiveness and blend correctness require runtime rendering

#### 3. Favorites Persist Across App Restart

**Test:** Long-press "Noir B&W" to mark it favorite (star badge appears, it moves to front of strip). Force-quit and relaunch.
**Expected:** After relaunch Noir B&W still has the star badge and still appears first after "Original"
**Why human:** UserDefaults persistence requires running app on device

#### 4. XCTest Suite Passes

**Test:** Add `CubeParserTests.swift` to `PhotoEditorTests` target and `PipelineBuilderTests.swift` extensions to the same target in Xcode, then run the test suite
**Expected:** All 6 `CubeParserTests` methods pass; `testIdentityLUTProducesPixelIdenticalOutput` confirms identity LUT produces pixel-equal output within ±1/255 tolerance
**Why human:** XCTest execution requires Xcode on macOS — cannot run on Linux

#### 5. Auto-Discovery of Dropped `.cube` Files

**Test:** Place a valid 64-point `.cube` file in `Resources/LUTs/` within the app bundle and rebuild
**Expected:** The new filter appears at the end of the strip with a thumbnail derived from the LUT and its filename as the display name
**Why human:** Bundle resource enumeration at runtime

### Gaps Summary

No gaps found. All 6 phase truths are VERIFIED by code evidence. All 10 artifacts pass all three levels (exists, substantive, wired). All 9 key links are confirmed. All 6 requirement IDs (FILTER-01 through FILTER-06) are satisfied by the implementation.

The one plan-level discrepancy noted: Plan 02-02's `key_links` pattern specified `ColorCubeData\\(floats:` but the implementation uses `ColorCubeData(rgbTriplets:)`. This is not a gap — `rgbTriplets:` is the correct and more ergonomic path for the parser's RGB-only output, and is fully defined in `ColorCubeData.swift`. The PLAN pattern was an approximation; the wiring is real.

Remaining work is Mac-side UAT (items 1–5 above) and adding new Swift files to the Xcode project target as noted in Plan 02-06's `user_setup` block.

---
_Verified: 2026-05-03_
_Verifier: Claude (gsd-verifier)_
