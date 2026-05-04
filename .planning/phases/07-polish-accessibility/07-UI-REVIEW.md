---
phase: 7
slug: polish-accessibility
audit_date: 2026-05-04
overall_score: 17
max_score: 24
peer_set: VSCO, Darkroom, Lightroom Mobile, Halide, Afterlight
---

# Phase 7 — UI Review

**Overall:** 17/24

| Pillar | Score |
|--------|-------|
| Copywriting | 3/4 |
| Visuals | 2/4 |
| Color | 3/4 |
| Typography | 3/4 |
| Spacing | 3/4 |
| Experience Design | 3/4 |

## Top 3 Fixes

1. **Intrusive alert for every success action.** Every save, recipe apply, and library save fires a modal `.alert("Saved", ...)` requiring "OK". Premium peers (VSCO, Darkroom) use brief non-blocking toasts. Replace with auto-dismissing `.overlay` toast (~2s). `ContentView.swift:194–196` and `EditorViewModel` success flow.

2. **Curves canvas is a piecewise-linear polygon, not a spline.** `CurvesPanelView.swift:85–89` uses `path.addLine()` between 5 control points — visibly jagged corners where every pro app shows smooth curves. Single most "unfinished" signal in the app. Replace with Catmull-Rom cubic spline (compute bezier handles per segment, use `path.addCurve`).

3. **CropPanelView leaks system-token color.** `CropPanelView.swift:31` uses `Color.accentColor` and `Color(.tertiarySystemBackground)` instead of Theme tokens — exact pattern Phase 7 was supposed to eliminate. Replace with `Theme.Colors.accent.opacity(0.2)` / `Theme.Colors.separator`.

---

## Detailed Findings

### Copywriting (3/4)

**Works:** Specific CTAs ("Save to Photos", "Save as Recipe"), contextual error/success copy, descriptive empty states.

**Issues:**
- "Photo Editor" navigation title (`ContentView.swift:60`) — literal Xcode-default project name. Premium peers show wordmark or no title. Remove or replace with brand name.
- "OK" buttons on every alert (`ContentView.swift:192–196`) — "OK" is the system-default generic dismiss. For errors use "Dismiss". For success → toast (Fix #1).
- "Reset All" subtitle "You can undo this" (`UndoToolbar.swift:50`) is ambiguous — undo only restores the reset commit. Tighten copy.

### Visuals (2/4)

**Works:** Theme palette, canvas rounded rect, consistent 72×72 filter cells with 3pt amber selection ring.

**Issues:**
- **Curves jagged polyline** (Fix #2 — highest-severity).
- **No "rendering" state** between photo import and first preview render. ~100–500 ms gap shows empty panel-color rounded rect that looks broken. Add `ProgressView` or `.redacted(.placeholder)` while `importedImage != nil && previewImage == nil`.
- **Wasted nav title area.** "Photo Editor" centered alongside 5 toolbar buttons competes visually. Remove.
- **Tab bar selection is color-only.** `PanelContainerView.swift:63` — 7 tabs at 64pt each, active tab is amber text vs gray. Peers use pill background or underline. Add `Capsule()` background on active tab.
- **RecipeRow stock list chrome.** `RecipesSheetView.swift:170–197` — default grouped-list separators run full-bleed against neutral panel. Use `.listRowBackground(Theme.Colors.canvas)` and themed separator.

### Color (3/4)

**Works:** Theme module correct, dynamic light/dark via `UIColor { traits in }`, accent applied consistently across sliders/rings/icons. No hardcoded `Color.blue`/`Color.purple` in panels.

**Issues:**
- **`CropPanelView.swift:31`** — only remaining system-token leak (Fix #3).
- **`HSLPanelView.swift:57`** — selected channel swatch uses `Color.primary` ring instead of `Theme.Colors.accent` — bypasses Theme.
- **`FilterStripView.swift:71`** — favorite star is hardcoded `.yellow`. Semantically OK but bypasses Theme. Minor.

### Typography (3/4)

**Works:** Theme.Typography used in panels + onboarding. Most sizes use system text styles → Dynamic Type compliant. Monospaced `valueBubble` is a strong premium detail. 5 type roles — appropriate, no font explosion.

**Issues:**
- **`RecipesSheetView.swift:175–177`** — `RecipeRow` uses `.body.weight(.medium)` and `.caption` (stock fonts). Switch to `Theme.Typography.body`/`.caption`.
- **`ContentView.swift:214`** — "Original" compare badge uses `.caption.weight(.semibold)` not Theme token.
- **`Theme.Typography.title`** is fixed 28pt — does NOT scale under Dynamic Type. At Accessibility XL the title looks tiny next to scaled body text. Consider `.system(.largeTitle, design: .rounded).weight(.semibold)`.

### Spacing (3/4)

**Works:** Coherent spacing scale (xs:4, sm:8, md:12, lg:16, xl:24). Most panels consistent.

**Issues:**
- **Magic numbers vs tokens.** `ContentView.swift` uses raw `16`, `8`, `12`, `4` literals instead of `Theme.Spacing.lg/sm/md/xs`. Same in `PanelContainerView.swift:29` and `FilterStripView.swift:27,72`. Values match the scale today but bypass it.
- **No scroll affordance on overflowing panels.** Effects panel has 10+ sliders inside fixed 280pt height — `ScrollView` works but no visible scroll hint. Users may not discover Grain/Vignette/Split Toning. Add bottom fade gradient mask.

### Experience Design (3/4)

**Works:** Loading state on export, error boundaries, empty states, destructive confirmations, semantic disabled states, all Haptic events wired (incl. new `sliderSnap`), `Motion.adaptive()` on all animations.

**Issues:**
- **Blocking modal alerts for success** (Fix #1) — biggest UX departure from peers.
- **Mantis "Open Crop Tool" button is visibly broken.** `CropPanelView.swift:100–116` — full-width prominent amber button, always disabled, with a developer-facing "Add SPM dep" message. End users see a broken-looking primary CTA. Hide button when `!mantisAvailable` or change copy to "Interactive crop coming soon".
- **Library grid context-menu delete has no VoiceOver action.** `LibraryGridView.swift:39` — context menu only path; no `.accessibilityAction(named: "Delete")` on the cell.
- **RecipeNamePromptView has no themed background** — inherits system grouped gray instead of `Theme.Colors.canvas`.
- **No skeleton for filter thumbnails generating.** `FilterStripView.swift:140–172` — empty rounded rects for ~200ms on first photo load. Could shimmer or `.redacted`.

---

## Recommended Fix Order

| Priority | Fix | Effort | Impact |
|---|---|---|---|
| P0 | Replace success alerts with toast | S | High — fixes biggest "feels off" complaint |
| P0 | Catmull-Rom spline for curves canvas | S | High — single most visible "unfinished" signal |
| P0 | Hide Mantis disabled button | XS | High — visible regression |
| P1 | Remove "Photo Editor" nav title | XS | Medium |
| P1 | Add panel tab Capsule selection background | S | Medium |
| P1 | Add rendering state to canvas | S | Medium |
| P1 | Theme `CropPanelView` chips | XS | Medium |
| P2 | Dynamic-Type-scale `Theme.Typography.title` | XS | Low (only affects FirstRunView at XL) |
| P2 | Replace remaining magic-number spacings with tokens | S | Low |
| P2 | Bottom fade on long panels | XS | Low |
| P2 | Filter thumbnail skeleton | M | Low |
| P3 | Themed RecipeNamePromptView background | XS | Low |
| P3 | VoiceOver action on library cells | XS | Low |
| P3 | Theme `HSLPanelView` swatch ring | XS | Low |
| P3 | `RecipeRow` Theme typography | XS | Low |
| P3 | "OK" → "Dismiss" on error alerts | XS | Low |

---

*Audit by gsd-ui-auditor (sonnet) · 2026-05-04*
