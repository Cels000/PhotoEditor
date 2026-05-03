# PhotoEditor

## What This Is

A free, premium-feeling iOS photo editor for iPhone — a "VSCO Pro for free." Users import a photo, apply hand-curated film-style LUT filters with strength control, then refine with a full set of pro adjustments (light, color, HSL, curves, grain, vignette, crop), save the look as a reusable Recipe, and export to Photos or share. Edits are non-destructive and re-editable from an in-app library.

## Core Value

A photo editor that *feels* like a paid pro tool — distinctive filters, deep controls, and a polished interface — given away free, with edits you can come back to and refine.

## Requirements

### Validated

<!-- Existing implementation as of init -->

- ✓ Pick a photo from the iOS photo library — existing
- ✓ Apply a Core Image preset filter (10 built-in) — existing (will be replaced by LUT pipeline)
- ✓ Adjust brightness / contrast / saturation — existing (will be expanded)
- ✓ Rotate left/right in 90° steps — existing
- ✓ Reset edits without losing source — existing
- ✓ Save the edited image to Photos — existing

### Active

**Editor depth**

- [ ] Filter library: 20–30 hand-curated LUT-based filters (film/portrait/B&W/cinematic) with per-filter default adjustment tweaks
- [ ] Filter strength slider (0–100%)
- [ ] Light: exposure, contrast, highlights, shadows, whites, blacks
- [ ] Color: saturation, temperature, tint, vibrance
- [ ] HSL: hue/saturation/luminance per color channel
- [ ] Tone curves (RGB + per-channel)
- [ ] Split toning (highlights/shadows hue+saturation)
- [ ] Grain (size + intensity)
- [ ] Vignette (amount + feather)
- [ ] Sharpen
- [ ] Crop + straighten + free rotate
- [ ] Undo / redo through full edit session
- [ ] Before/after compare (press-and-hold)

**Recipes**

- [ ] Save current adjustment stack as a named Recipe
- [ ] Apply a Recipe to any photo
- [ ] Organize Recipes (rename, reorder, delete)
- [ ] Share a Recipe (export/import via file or link)

**Library**

- [ ] In-app library of edited photos with thumbnails
- [ ] Non-destructive edits — adjustments stored separately from source
- [ ] Re-open any library item and continue editing
- [ ] Delete library items

**Export**

- [ ] Save full-resolution edit to Photos
- [ ] Share-sheet to any iOS destination
- [ ] Format choice: JPEG / HEIC / PNG
- [ ] Size choice: full / web / story (presets) + custom long-edge
- [ ] Quality slider for lossy formats

**UI / UX**

- [ ] Distinctive, premium SwiftUI interface (not template-y) — visual hierarchy, motion, theming, accessibility (Dynamic Type, VoiceOver, Reduce Motion)
- [ ] iPhone-first responsive layout (works on iPad but not optimized for it)

### Out of Scope

- In-app camera (manual / RAW capture) — deferred to v2; out of scope for initial release
- Social feed, profiles, discovery, follows — VSCO's social side is explicitly not part of this product
- iCloud sync of library or recipes — local-only by design for v1
- iPad-optimized layout — iPhone-first; iPad runs the iPhone layout
- Accounts / sign-in — no auth, no backend
- Monetization (subscriptions, IAP, paid filter packs) — free, no monetization
- Video editing — photos only
- AI features (auto-enhance, sky replacement, generative fill) — not aligned with the "human-curated film look" identity

## Context

**Existing code:** Small SwiftUI/MVVM app — `ContentView.swift`, `PhotoEditorApp.swift`, `PhotoEditorViewModel.swift`, `Info.plist`, `Assets.xcassets`. Renders via Core Image, uses `PhotosPicker`, saves via `PHAssetChangeRequest`. Downsamples imports to 2048px max long edge. AppIcon is a placeholder. The current 10 built-in `CIPhotoEffect*` filters are functional but generic — they will be replaced (or relegated to a "basics" group) by the curated LUT pipeline.

**Audience:** Side-project, distributed to friends via TestFlight. Quality bar is real (it should feel premium) but scope can be ruthlessly cut where invisible.

**Build environment:** macOS + Xcode 16+, iOS 17+ target. The current dev session is on Linux — Claude cannot build/run; verification happens on the user's Mac in Xcode.

## Constraints

- **Tech stack:** SwiftUI, Core Image (CIFilter, CIColorCube for LUTs), Photos framework. Persistence likely SwiftData or Core Data. iOS 17+.
- **Platform:** iPhone-first; iPad must launch and not crash, but layout isn't tuned for it.
- **Performance:** Live preview must stay responsive while sliders are dragged (downsampled preview render, full-res only on export).
- **No backend:** Local-only. No accounts, no servers, no analytics dependencies.
- **Distribution:** TestFlight → friends. Not chasing App Store featuring; not chasing scale.
- **Free:** No paywalls or IAP — including no "Pro" tier later in v1 scope.
- **Privacy:** Add-only Photos permission already requested; nothing else leaves the device.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| LUT + per-filter adjustment hybrid for filters | LUTs give a distinctive film-look, layered tweaks make each filter feel hand-tuned — the most VSCO-like approach | — Pending |
| In-app library with non-destructive edits | Re-editability is a premium-feel marker; keeps source untouched | — Pending |
| Local-only (no iCloud/CloudKit) for v1 | Avoids account/sync complexity; matches "side-project" scope | — Pending |
| Defer camera to v2 | A serious manual+RAW camera is a project of its own; editor must be excellent first | — Pending |
| iPhone-first, not iPhone+iPad | Doubles design surface for limited audience benefit | — Pending |
| Free, no monetization | Stated goal: "free version of VSCO Pro" | — Pending |

---
*Last updated: 2026-05-03 after initialization*
