# Camera Preset UI — Category Signage + Scrub Labels

**Date:** 2026-05-04
**Scope:** UI/UX of the in-camera preset carousel (`CameraView.bottomDeck`).
**Out of scope:** preset data model, recipe seeding, render pipeline, capture path.

## Problem

The camera carousel renders live-preview thumbnails of every preset, but only
the *currently selected* preset's name is shown (in a label below the row).
Non-selected thumbnails are unlabeled, so the user can't tell which preset is
which without selecting each one in turn — they're guessing.

## Goals

- User can identify any preset without selecting it.
- The deck stays visually quiet; no extra rows, no layout shift, no permanent
  visual noise per cell.
- Categories give scannable structure ("I'm in Color Film now") so the
  preset namespace feels organized rather than a flat list of 18+ items.
- Reuse existing data: `RecipeCategory` enum, `BuiltInPresets.category(forName:)`.

## Non-goals

- Renaming, regrouping, or reseeding presets.
- Per-cell always-on labels (rejected: too noisy, shrinks thumbnails).
- A separate category pill strip above the carousel (rejected: adds vertical
  height and competes with the carousel for attention).

## Design

### Label area — collapsed two-tone single row

The existing label slot below the carousel (currently shows the selected
preset's name only) becomes a **two-part live label**:

```
        COLOR FILM ›   ·   PORTRA 400
        └ category, secondary tone, tappable ┘   └ name, primary tone ┘
```

- **Category half** (left): `RecipeCategory.displayName.uppercased()` of the
  centered preset's category. Rendered in `Theme.Colors.secondary` (or text @
  ~50% opacity) using the existing `Theme.Typography.label` style with
  tracking 2 — same treatment as the current label.
- **Separator:** a middle dot `·` in the same secondary tone.
- **Name half** (right): the centered preset's `displayName.uppercased()`,
  primary text color — visually identical to today's label.
- **Chevron `›`** appended after the category text indicates the category half
  is tappable.
- Both halves update **live** as the carousel scrubs (driven by the existing
  `viewModel.selectedSlotID` change path, since `.scrollTargetBehavior(.viewAligned)`
  already snaps selection to the centered cell).

#### Special cases

- **Original** slot: no category. Render as `ORIGINAL` only (no `·`, no chevron),
  centered in the row.
- **My Recipes** (user-saved recipes, no built-in category): show category text
  `MY RECIPES ›` — same treatment as built-in categories.
- If a preset is somehow uncategorized AND not in `RecipeStore.items` as a
  user recipe (shouldn't happen, defensive): render name only, no category.

### Category jump — tap-to-advance

Tapping the **category half** of the label (including the chevron) advances
the carousel to the **first preset of the next category** in carousel order,
wrapping back to Original after the last category.

- Implemented by adding a `Button` (or `.onTapGesture`) zone over the category
  text + chevron only — the name half remains non-interactive.
- Jump uses the same `ScrollViewReader.proxy.scrollTo(id, anchor: .center)`
  primitive already used in `carousel`'s `onAppear`.
- Light haptic on jump (`UIImpactFeedbackGenerator(style: .light)`) — matches
  the existing capture haptic style.

### Scrub neighbor labels

To support quick scanning while flicking through the carousel, ghost-labels
appear under the **immediate left and right neighbors** of the centered cell
during active scrolling.

- Ghost label = preset `displayName.uppercased()` only, **no category**, at
  ~40% opacity, same font/tracking as the main label but smaller (e.g.
  `Theme.Typography.label` scaled 0.85, or a dedicated `caption2` size — pick
  whichever already exists in `Theme.Typography`; do not introduce a new size).
- Positioned **horizontally aligned with the neighbor cell**, on the same
  vertical baseline as the main label — so the row reads as `‹ name · CAT · NAME · name ›`
  without the deck growing taller.
- Driven by iOS 17's `ScrollPhaseChangeObserver` (or equivalent
  `onScrollPhaseChange`) on the existing `ScrollView`:
  - Phase becomes `.tracking` / `.interacting` / `.decelerating` → fade ghosts
    in over ~120 ms.
  - Phase becomes `.idle` → fade ghosts out over ~250 ms.
- If only one neighbor exists (centered cell is at an edge), only that side's
  ghost renders.

### Visual category boundary in the carousel

A 1-point vertical separator line between cells from **different categories**
in the carousel itself.

- Color: `Theme.Colors.secondary` at ~30% opacity.
- Height: matches the thumbnail edge.
- Drawn as a leading overlay on the first cell of each category (skip Original
  since it's the first slot and has no left neighbor).
- This is the *only* per-cell category indicator inside the carousel — no
  background tints, no group labels, no separators inside a category.

## Data flow

```
viewModel.selectedSlotID           ── changes on scroll snap ─→  label re-renders
                                                                  (category + name)

ScrollView phase                    ── tracking/decelerating ─→  ghost labels fade in
                                    ── idle ──────────────────→  ghost labels fade out

Category-jump tap                   ── computes next category ─→  proxy.scrollTo(firstID)
                                                                  selectedSlotID updates via snap
```

No new state on the view model; everything derives from `selectedSlotID`,
`slots`, and a tiny computed helper that maps `CameraSlot → RecipeCategory?`.

## New helper

Add a single derived helper on `CameraSlot` (or a free function in
`CameraView.swift` if cleaner):

```swift
extension CameraSlot {
    /// nil for .original, the recipe's category for .recipe(...).
    /// "My Recipes" pseudo-category is represented by `nil` paired with a
    /// recipe whose name has no entry in BuiltInPresets.nameToCategory.
    var category: RecipeCategory? { ... }

    /// "ORIGINAL" / "COLOR FILM" / "MY RECIPES" / etc.
    /// Returns nil for .original (caller renders no category half).
    var categoryDisplayName: String? { ... }
}
```

Plus one helper on `CameraViewModel` (or local to the view) for jump nav:

```swift
/// Returns the slot ID of the first slot in the next category after the
/// currently centered one, wrapping to .original after the last.
func firstSlotIDOfNextCategory(after slotID: String) -> String?
```

## Components touched

- `PhotoEditor/Camera/CameraView.swift` — `bottomDeck`, `carousel`, label
  rendering, scroll phase observation, jump-tap handling.
- `PhotoEditor/Camera/CameraSlot.swift` — add `category` / `categoryDisplayName`
  computed properties.
- `PhotoEditor/Camera/CameraViewModel.swift` — add jump-nav helper (or keep
  in the view if it stays small).

No changes to: `CameraSession`, `CameraPreviewRenderer`, `CameraCarouselThumbnailer`,
`RecipeStore`, `RecipeCategory`, `BuiltInPresets`.

## Testing

The image processing pipeline is pure and unrelated; this is purely view-layer.
Manual on-device verification covers:

- Scrolling through all 18+ presets — category half updates as you cross
  boundaries, name half updates on every snap.
- Tapping the category half advances to the next category; wraps from last
  back to Original.
- Tapping the name half does nothing.
- Neighbor ghost labels appear during scroll, vanish ~250 ms after release.
- Edge cases: Original slot (no category half), single-recipe category
  (jump still works), user with no recipes (My Recipes pill never appears).
- Layout: deck height is unchanged vs. current build; no jitter when category
  text length changes (e.g. "ERA & CAMERA" vs. "B&W FILM").

No unit tests required — view-only, no pure logic worth isolating beyond the
`category` helper, which is trivial.

## Open questions

None — design is concrete enough to plan tasks against.
