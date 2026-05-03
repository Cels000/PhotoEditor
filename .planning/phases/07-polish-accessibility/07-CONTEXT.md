# Phase 7: Polish + Accessibility - Context

**Gathered:** 2026-05-03
**Status:** Ready for planning

<domain>
## Phase Boundary

The interface earns the "premium feel" claim. Motion, haptics, accessibility, and visual design are at the level of a paid pro app.

Specifically:
- **Distinctive visual identity** beyond stock SwiftUI: typography hierarchy, spacing rhythm, deliberate color (not just system tokens), subtle texture/depth, polished iconography
- **Haptics:** zero-crossing tick on slider, end-stop bump, value-snap on filter strength, filter-selection light tap, recipe-apply success haptic, undo/redo haptic
- **Spring animations** on all panel transitions; no canvas layout shift (already enforced in Phase 3 panel container)
- **Reduce Motion:** disables non-essential animations, gestures still work
- **Dynamic Type:** all text scales gracefully up to XL without truncation
- **VoiceOver:** every adjustment slider uses `accessibilityAdjustableAction`, every button has correct trait/label, custom controls (curve points, color swatches) are accessible
- **Light/Dark mode:** deliberate per-mode color choices — not default system colors
- **First-run flow:** explains photo permission rationale before iOS prompt, handles `.limited` access gracefully
- **iPad behavior:** runs the iPhone layout without crashing or clipping (no iPad optimization, but no broken layout either)

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

- **Design system module:** Add `PhotoEditor/Design/` directory with:
  - `Theme.swift` — color tokens (light + dark), typography, corner radii, spacing, shadows
  - `Haptics.swift` — wrapper around `UIImpactFeedbackGenerator`, `UISelectionFeedbackGenerator`, `UINotificationFeedbackGenerator` with named events (sliderZero, sliderEnd, filterSelect, recipeApply, undo)
  - `Motion.swift` — spring presets (standard, snappy, smooth) honoring `accessibilityReduceMotion`
- **Color palette:** Warm neutrals — off-black canvas, soft cream highlights, accent: a single deep amber (close to film-orange #D97A2B). Avoid Apple-blue defaults. Tint the app per-mode:
  - Dark: canvas #0E0D0C, panel #1B1916, accent #E89A52, text #F5EFE8, secondary #8A8378
  - Light: canvas #F5EFE8, panel #FFFFFF, accent #B66A2A, text #1A1816, secondary #6E6961
- **Typography:** Use `SF Pro Display` for titles (rounded), `SF Mono` for value bubbles (numeric clarity), `SF Pro Text` for body. Establish a small type scale: Title (28/SemiBold), Subtitle (17/Medium), Body (15/Regular), Caption (12/Regular).
- **Haptics enum:**
  ```
  enum Haptic {
      case sliderZeroCross
      case sliderEnd
      case filterSelect
      case recipeApply
      case undoRedo
      case panelOpen
      case errorAlert
      static func play(_ event: Haptic) { ... }  // honors UIAccessibility.isReduceMotionEnabled? No — haptics aren't motion. But does provide a global toggle.
  }
  ```
- **AdjustmentSlider polish:** Already has `accessibilityAdjustableAction`. Add: Haptic.play(.sliderZeroCross) when value crosses 0, Haptic.play(.sliderEnd) when binding clamps. Tighten value-bubble animation timing.
- **Filter strip polish:** Selected ring uses `Theme.accent`. Filter selection plays `Haptic.filterSelect`. Long-press favorite plays `.success` notification haptic.
- **Recipe apply:** Plays `Haptic.recipeApply` (notification.success). Brief "applied: [name]" toast.
- **Undo/redo toolbar:** Each tap plays `Haptic.undoRedo`. Disabled state respects opacity 0.4.
- **Spring tokens:**
  ```
  enum Motion {
      static let panel: Animation = .interpolatingSpring(stiffness: 240, damping: 28)  // ~0.4s
      static let snappy: Animation = .interpolatingSpring(stiffness: 380, damping: 24) // ~0.25s
      static let smooth: Animation = .easeInOut(duration: 0.18)
      static func adaptive(_ a: Animation) -> Animation? {
          UIAccessibility.isReduceMotionEnabled ? nil : a
      }
  }
  ```
- **First-run:** A simple sheet on first launch explaining: "Pick a photo to edit", "Save to Photos when done", with a "Get Started" button that launches the photo picker. Track `hasSeenFirstRun` in UserDefaults.
- **Limited access handling:** When `PHPhotoLibrary.authorizationStatus(for: .readWrite)` is `.limited`, show a banner "Photo Editor has limited access. Tap to manage." → opens `PHPhotoLibrary.shared().presentLimitedLibraryPicker(from:)`.
- **iPad:** Already runs iPhone layout (Phase 1+). Audit for any specific breakage — text truncation in landscape, sheet presentation, etc. Patch as needed but no iPad-specific layout work.
- **VoiceOver pass:** Audit every custom view (FilterStripView, AdjustmentSlider, CurvesPanelView, HSL color swatch, CropPanelView). Each needs label + value + hint where non-obvious. Curves' draggable points get `accessibilityAdjustableAction` for screen-reader adjustment.
- **Dynamic Type pass:** Replace any fixed `.font(.caption)` `.font(.body)` etc. with proper text styles via `Theme.swift`. Test up to `.accessibilityExtraLarge` (XL).
- **Onboarding asset:** AppIcon — Phase 7 ships a placeholder gradient icon (better than the empty asset slot but not the final brand). Document that final brand work is out of scope for v1.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
Almost everything: this phase touches existing files to apply polish, doesn't add many new ones. Theme/Haptics/Motion are net-new modules.

### Patterns
- Existing `AdjustmentSlider` is the focal accessibility/haptic surface
- All panels need a Theme audit
- All animations need Motion.adaptive wrapping

### Integration Points
- Every view file under `PhotoEditor/Editor/Panels/*`, `PhotoEditor/Filters/`, `PhotoEditor/Library/` *RecipesSheetView*, `ContentView`
- `PhotoEditorApp` for first-run sheet presentation
- AppIcon asset

</code_context>

<specifics>
## Specific Ideas

- **The single highest-leverage change:** the `Theme` module + replacing every `Color.blue` / system-default tint. Once that lands, the app reads as "designed."
- **Second-highest:** haptics on every interactive surface. Cheap to implement, dramatic perceived quality difference.
- **Don't over-animate.** Spring panel transitions, value-bubble crossfade, filter-strip selection ring fade — that's it. No sliding cards, no parallax, no entrance choreography. Less is more for premium tools.
- **Reduce Motion:** test by enabling iOS Settings → Accessibility → Reduce Motion in simulator and confirming animations bypass.
- **VoiceOver:** test by enabling VoiceOver in simulator and tab-tabbing through every screen. Confirm each control speaks its label + value.

</specifics>

<deferred>
## Deferred Ideas

- Custom SF Symbol-style brand iconography — v2
- Final AppIcon brand work — v2
- Localization beyond English — v2
- Sound design (UI sounds) — out of scope (premium tools usually mute by default)
- iPad-optimized split-view layout — v2 (IPAD-01)

</deferred>
