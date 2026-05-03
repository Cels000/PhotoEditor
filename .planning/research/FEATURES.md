# Feature Research

**Domain:** Premium iOS photo editor (VSCO Pro-style, editor + recipes + library, no social)
**Researched:** 2026-05-03
**Confidence:** HIGH (competitive apps verified via official sources and recent reviews)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Missing any of these makes the app feel cheap, amateur, or broken. Users do not give credit for having them — they only penalize their absence.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Filter strip with live preview thumbnails | Every premium editor has this; generic tile grids feel dated | M | Thumbnails render the actual photo with each filter applied — not static swatches |
| Filter strength slider (0–100%) | VSCO established this as table stakes in 2013; users expect it | S | Slider appears inline below the active filter tile; drag or tap to adjust |
| Before/after compare (press-and-hold) | Standard in Darkroom, VSCO, Lightroom — users check before exiting | S | Long-press on preview shows original; release restores edited. Must feel instant |
| Full light adjustment panel: exposure, contrast, highlights, shadows, whites, blacks | Lightroom Mobile made 6-control light editing the baseline expectation | M | Users who've used Lightroom are lost without highlights/shadows/whites/blacks split |
| Color panel: saturation, temperature/tint, vibrance | Standard; omitting tint or vibrance reads as "basic app" | S | Temperature/tint together required; vibrance (smart saturation) is expected |
| Crop with aspect ratio lock list | iOS Photos, VSCO, Lightroom all have this; free crop alone feels incomplete | M | Common ratios: free, original, square, 4:3, 16:9, 3:2, 5:4, 9:16. Custom entry is a nice-to-have |
| Straighten / horizon correction within crop | Lightroom Mobile's rotate-dial UI is the benchmark; wobbled horizons are painful | M | Rotation dial at bottom of crop, distinct from the 90° rotate buttons |
| Undo/redo across full session | Non-negotiable — accidental moves need to be reversible | M | Full edit stack, not just one step back. Shake-to-undo is not sufficient alone |
| Non-destructive editing (source preserved) | Darkroom makes this central; VSCO's destructive model is a known complaint | L | Store adjustment parameters, render to preview; original never modified |
| Save / export to Photos | Primary output path; anything less feels incomplete | S | Always "save copy" (never replace original); PHPhotoLibrary add-only permission |
| Share sheet integration | Users expect to share directly to Messages, Instagram, etc. | S | UIActivityViewController; no custom share UI needed |
| In-app library of edited photos | Re-editability is a premium marker — users return to refine | M | Grid of thumbnails, "edited" badge, tap to re-enter edit session |
| Tap-to-reset individual adjustment to zero | Universal in Lightroom Mobile and Darkroom; users expect it | S | Double-tap on slider label or slider handle resets to 0. Tactile + visual feedback |
| Dark mode | System expectation on iOS 17+; photo editors especially — dark UI shows photo accurately | S | Full support via SwiftUI colorScheme; all surfaces adapt |
| Dynamic Type support | iOS system expectation; accessibility labeling; labels/buttons must scale | S | Use SwiftUI text styles (not fixed font sizes) throughout |

---

### Differentiators (What Makes It Feel Premium)

These are not expected — users give credit for them. They tip the experience from "fine app" to "I'm telling friends about this."

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Hand-curated LUT-based film filters (20–30, named) | Distinctive film-look character unavailable in stock CIPhotoEffect filters; this is the core identity | L | 512x512 or 64x64 LUTs per filter, loaded via CIColorCube. Categories: film, portrait, B&W, cinematic. Named evocatively (not "Filter 7") |
| Per-filter default adjustment tweaks embedded in filter definition | VSCO does this; each filter ships with a "tuned" starting point for exposure/contrast/etc. | M | Filter model carries optional default adjustments; applied on top of LUT. User can override |
| HSL panel (hue/saturation/luminance per color channel) | Separates serious editors from casual apps. Missing = can't target specific color range | M | 6–8 color channels: red, orange, yellow, green, aqua, blue, purple, magenta |
| Tone curves (RGB + per-channel) | True pro tool; Darkroom and Lightroom have it; satisfies users who outgrew basic sliders | L | Cubic bezier curve editor, channel switcher (RGB/R/G/B), reset-curve button |
| Split toning / color grading (highlights + shadows hue + saturation) | Creates moody, cinematic looks impossible with flat saturation; used in every film-emulation filter | M | Hue wheel + saturation slider for highlights and shadows independently |
| Grain control (size + intensity) | Analogue film look; Afterlight and RNI Films make this a centerpiece; users expect analog toolset | S | Two sliders: size (fine→coarse) and intensity (0–100). Applied last in render stack |
| Vignette (amount + feather radius) | Film-look finishing touch; most premium editors include it | S | Amount (0–100, negative = brighten), feather (soft→hard). Renders as radial gradient mask |
| Sharpen / clarity | Darkroom's Clarity tool is a noted differentiator; sharpening distinguishes edited photos on export | S | Sharpening: simple radius+amount. Clarity: midtone contrast (skip if performance risk) |
| Recipes: save/apply/export named adjustment stacks | VSCO Recipes are a defining feature; power users build "looks" they reuse across shoots | M | Recipe = named JSON/struct of all adjustment values + filter reference. Apply in one tap |
| Recipe sharing (export/import via Files or share sheet) | Enables sharing between users; adds social value without building a social layer | M | Export as .photorecipe file (custom UTI). Share via AirDrop, Files, iMessage |
| Value indicator on sliders (shows numeric value while dragging) | Darkroom and Lightroom both show the numeric value while dragging; gives expert-user control | S | Show value label above thumb while gesture is active; hide on gesture end |
| Fine-adjustment mode (slow-drag on slider) | Lightroom Mobile uses a "precision scrubber" metaphor; critical for tone curve / HSL fine work | S | Drag downward/upward from slider to enter 5x precision mode. Industry standard gesture |
| Haptic feedback at strategic moments | Darkroom 7 specifically added haptics "on opening tools, using sliders"; tactile = premium | S | Light impact: slider reaches min/max. Selection: filter applied. Rigid: reset to zero. Use UIImpactFeedbackGenerator / UISelectionFeedbackGenerator |
| Spring / physics animations on panel transitions | Distinguishes custom SwiftUI work from default; "feels alive" | S | Spring easing on tool panel slide-up, filter strip scroll deceleration, before/after toggle |
| Filter favorites and recently-used row | Darkroom and VSCO both have this; reduces scroll friction for power users | S | Heart/star tap on filter tile adds to favorites section; recently-used auto-updated |
| Crop grid overlays (rule of thirds, etc.) | Darkroom emphasizes this; helps composition, not just geometry | S | Rule of thirds (default during drag), golden ratio, diagonal. Auto-hide when idle |
| Auto-straighten / horizon detection | Lightroom Mobile has this as a tap-to-level button; reduces friction for landscape shots | M | Use CIPerspectiveCorrection or CoreImage horizon detection; one-tap apply |
| Multi-select in library for batch delete / batch export | Darkroom supports batch adjustments; batch delete at minimum needed for house-cleaning | S | Long-press to enter selection mode; checkmarks on thumbnails; action bar appears |
| "Edited" badge on library thumbnails | Visual confirmation of edit state; missing feels like a bug | S | Small dot/badge overlay in corner; also show recipe name if one was applied |
| Export format/size choice (JPEG/HEIC/PNG + size presets) | Lightroom Mobile export dialog is the benchmark; users expect at minimum JPEG quality control | M | Format: JPEG, HEIC, PNG. Size presets: Full, Web (2048px), Story (1080px). Custom long-edge |
| JPEG quality slider | Every export dialog has this; omitting it reads as "basic" | S | Range 60–100%; show estimated file size in real-time. Only visible when lossy format selected |

---

### Anti-Features (Explicitly NOT Building)

These seem like additions but create harm — scope creep, identity dilution, or UX friction that outweighs benefit.

| Anti-Feature | Why It's Requested | Why NOT to Build | What to Do Instead |
|---|---|---|---|
| AI auto-enhance / Smart enhance | Users ask "can you just make it look better?" | Directly contradicts the hand-curated film-look identity. Auto-enhance produces a homogenized look antithetical to the product. Adds ML model payload and maintenance burden | Ship great default filter starting points + per-filter adjustment defaults. The filter IS the auto-enhance |
| Sky replacement / generative fill | Viral in competitor demos; users ask | Requires multimodal ML models (CoreML segmentation + generation); adds 50–200MB payload. Produces uncanny results on anything but blue sky. Orthogonal to film-emulation identity | Stay in the adjustment lane; sky replacement is a separate product category |
| Social feed / discovery / follows | VSCO has it; users may expect social proof | This is explicitly out of scope and the product's differentiator IS that it lacks this. Social requires backend, moderation, legal, and ongoing ops. TestFlight friends don't need a feed | Recipe sharing via share sheet provides social-adjacent value without the infrastructure |
| In-app camera (manual / RAW) | VSCO and Halide both have cameras | A serious manual+RAW camera is a distinct 6-month project. Half-implemented camera is worse than no camera. iOS 17 ProRAW pipeline alone is complex | Defer to v2; make the editor excellent first. Import from Photos (which already captures ProRAW) |
| Accounts / sign-in / cloud sync | Users expect "save my edits across devices" eventually | No backend, no accounts is a constraint AND a simplification. iCloud sync requires CloudKit schema, conflict resolution, migration — not a side-project feature | Library is local-only; frame this as "your edits stay on your device, always" |
| Unlimited undo history persisted between sessions | Sounds premium; "I came back to undo" | Persisting full undo stack requires serializing every intermediate state. Non-destructive editing solves the real need (re-edit from scratch). Full history persistence is engineering complexity with little real-world use | Non-destructive re-editing is the correct answer to "I want to go back" |
| Batch adjustment apply to all photos | Recipes + multi-select covers this | Without Lightroom's catalog model, batch processing all library photos is a performance and UX anti-pattern. Users will accidentally apply looks globally | Recipes applied one-at-a-time per photo, or via explicit multi-select action |
| Subscription / IAP paywalls | Standard monetization | Explicitly out of scope. Paywalls for a TestFlight app alienate the exact friends it's distributed to | Free, no monetization; scope cut on features rather than monetization |
| Portrait mode / depth effects | Present in iOS Photos natively | Requires depth data, separate rendering pipeline, significant complexity. Adds no value for the film-look identity | Users who want depth blur use native iOS Photos tools |
| Video editing | Some editors add it | Entirely separate rendering pipeline (AVFoundation vs Core Image still path). Different UX paradigm. Out of scope | Photos only, stated explicitly |
| Object removal / healing | Present in Lightroom's 2025 AI tools | Requires ML inpainting model; large payload; not aligned with analog film aesthetic (film doesn't heal your ex out of photos) | Keep editor tools in the analog toolset lane |

---

## Feature Dependencies

```
LUT Filter Pipeline
    └──requires──> Core Image CIColorCube setup + LUT asset bundling
                       └──required by──> Per-filter default adjustments
                       └──required by──> Filter strength slider (blend original + LUT)
                       └──required by──> Before/after compare (need base layer)

Adjustment Stack (non-destructive model)
    └──required by──> Recipes (save = serialize stack)
    └──required by──> Re-edit from Library (load = deserialize stack)
    └──required by──> Undo/redo (stack is the history)
    └──required by──> Before/after compare (original = empty stack)

Recipes
    └──requires──> Adjustment Stack model
    └──requires──> Named filter reference (LUT pipeline must be stable)
    └──enhances──> Library (show recipe name on thumbnail badge)
    └──enables──> Recipe sharing (export serialized stack as file)

Library
    └──requires──> Persistence (SwiftData/CoreData storing photo refs + edit stacks)
    └──requires──> Non-destructive model (source photo must be preserved)
    └──enhances──> Multi-select (batch delete/export)

Export
    └──requires──> Full-res render pipeline (downsample for preview, full-res for export)
    └──requires──> Photos framework write permission
    └──depends on──> Format/quality choices (JPEG/HEIC/PNG + quality slider)

Crop + Straighten
    └──requires──> Separate from adjustment stack (geometry applied pre-adjustment or as separate transform)
    └──conflicts with──> "Non-destructive crop stored in stack" if not designed carefully

HSL Panel
    └──requires──> Adjustment Stack model
    └──independent of──> LUT pipeline (HSL applied after LUT in render order)

Tone Curves
    └──requires──> Adjustment Stack model
    └──requires──> Cubic bezier evaluation math (CIToneCurve or custom CIKernel)
    └──is complex, phase-appropriate──> Later phase than basic sliders

Haptics
    └──enhances──> All interactive controls (sliders, filter selection, crop snapping)
    └──no hard dependencies──> Can be added as a polish pass

Recipe Sharing
    └──requires──> Recipes feature (fully working)
    └──requires──> Custom UTI registration in Info.plist
    └──requires──> Document interaction controller or share sheet integration
```

### Dependency Notes

- **Adjustment Stack model is the keystone:** Recipes, undo/redo, re-editing, and before/after all hang off the same underlying data model. Get this right in Phase 1 — it cannot be refactored cheaply later.
- **LUT pipeline stability before Recipes:** A Recipe saves a reference to a filter by ID. If filter IDs or the LUT loading mechanism changes after Recipes are built, saved recipes break.
- **Crop geometry is architecturally separate:** Crop/rotate/straighten is a geometric transform applied as a distinct step, not an adjustment parameter. Do not fold it into the CIFilter chain or export gets complicated.
- **Tone Curves depends on per-channel CIFilter:** CIToneCurve exists in Core Image but curve editing UI is complex. This is a Phase 2+ feature — do not block Phase 1 on it.
- **Haptics have no hard dependencies** — add as a polish pass after interaction patterns are stable, or risk the haptic calls becoming stale when UI is refactored.

---

## MVP Definition

### Launch With (v1)

Core editing loop that makes the app feel worth using. Missing any of these = app is not ready.

- [ ] LUT filter strip with live thumbnails and strength slider — this is the product's identity
- [ ] Full light panel (exposure, contrast, highlights, shadows, whites, blacks)
- [ ] Color panel (saturation, temperature, tint, vibrance)
- [ ] Crop with aspect ratio lock list + straighten dial
- [ ] Undo/redo (full session, in-memory)
- [ ] Before/after compare (long-press)
- [ ] Non-destructive edit model (source preserved, adjustments serialized)
- [ ] In-app library with re-edit and "edited" badge
- [ ] Save copy to Photos + share sheet
- [ ] Dark mode + Dynamic Type
- [ ] Double-tap to reset individual adjustments
- [ ] Filter favorites

### Add After Validation (v1.x)

- [ ] Recipes (save/apply/rename/delete) — triggers: users ask "how do I reuse this look?"
- [ ] HSL panel — triggers: power users want selective color control
- [ ] Grain + vignette tools — triggers: film-look identity is established, add finishing tools
- [ ] Haptic feedback polish pass — triggers: core interactions are stable
- [ ] Export format/size/quality chooser — triggers: users complain about file size or want HEIC
- [ ] Recipe sharing (export/import file) — triggers: friends want to share looks

### Future Consideration (v2+)

- [ ] Tone curves — high complexity, defer until core stack is proven
- [ ] Split toning / color grading panel — layered on top of stable color model
- [ ] Auto-straighten / horizon detection — nice-to-have, defer
- [ ] Manual camera (ProRAW) — separate project, v2 milestone
- [ ] Multi-select batch export — defer until library has significant content

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| LUT filter pipeline + strip | HIGH | HIGH | P1 |
| Filter strength slider | HIGH | LOW | P1 |
| Light panel (6 controls) | HIGH | MEDIUM | P1 |
| Color panel (4 controls) | HIGH | LOW | P1 |
| Non-destructive edit model | HIGH | HIGH | P1 |
| Before/after compare | HIGH | LOW | P1 |
| Crop + straighten | HIGH | MEDIUM | P1 |
| Undo/redo | HIGH | MEDIUM | P1 |
| In-app library + re-edit | HIGH | MEDIUM | P1 |
| Save to Photos + share sheet | HIGH | LOW | P1 |
| Double-tap to reset | MEDIUM | LOW | P1 |
| Dark mode + Dynamic Type | MEDIUM | LOW | P1 |
| Filter favorites | MEDIUM | LOW | P1 |
| Recipes (save/apply) | HIGH | MEDIUM | P2 |
| HSL panel | HIGH | MEDIUM | P2 |
| Grain + vignette | MEDIUM | LOW | P2 |
| Haptics polish | MEDIUM | LOW | P2 |
| Export format/size/quality | MEDIUM | MEDIUM | P2 |
| Recipe sharing | MEDIUM | MEDIUM | P2 |
| Value indicators on sliders | MEDIUM | LOW | P2 |
| Tone curves | HIGH | HIGH | P3 |
| Split toning panel | MEDIUM | MEDIUM | P3 |
| Auto-straighten | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for v1 launch
- P2: Add in v1.x after core loop is working
- P3: Future consideration (v2+)

---

## Polish and Accessibility Features

These are what separate a TestFlight app friends recommend from one they quietly delete. They are not features users describe when asked what they want — but they are why apps feel premium.

### Haptics (Confidence: HIGH — Darkroom 7 verified)

- **Slider min/max end-stop:** `UIImpactFeedbackGenerator(.rigid)` when slider reaches 0 or 100. This is the iOS Control Center brightness pattern.
- **Filter selection:** `UISelectionFeedbackGenerator` when a new filter tile is tapped.
- **Reset to zero:** `UIImpactFeedbackGenerator(.medium)` on double-tap reset. Confirms the action.
- **Crop snap to ratio:** `UIImpactFeedbackGenerator(.light)` when aspect ratio snaps to nearest lock.
- **Recipe applied:** `UINotificationFeedbackGenerator(.success)` — satisfying confirmation.
- **Do NOT fire haptics:** During passive scroll, thumbnail load, or any background task.

### Motion and Animation

- **Filter strip scroll:** Deceleration matching iOS spring physics — do not use linear scroll.
- **Adjustment panel slide-up:** Spring animation (damping ~0.85, response ~0.35s). Not a flat translate.
- **Before/after toggle:** Instant (< 1 frame) — any delay breaks the comparison usefulness. Use `.transaction { $0.animation = nil }` for the image swap.
- **Slider thumb:** Subtle scale-up (1.0 → 1.15) on drag start to indicate grab state.
- **Reduce Motion compliance:** Any animation that moves content spatially (panel slide, filter strip) must use `.opacity` transition instead when `@Environment(\.accessibilityReduceMotion)` is true.

### VoiceOver and Accessibility

- **All sliders must have accessibility labels AND values:** `accessibilityLabel("Exposure")`, `accessibilityValue("\(Int(value))")`. SwiftUI Slider provides value but not label by default.
- **Filter tiles:** Label includes filter name AND current state: "Kodachrome filter, currently selected, strength 70%"
- **Before/after button:** Describe state — "Showing original. Release to return to edited."
- **Crop handles:** `accessibilityAdjustableAction` to move handles via VoiceOver swipe-up/down.
- **Library grid items:** "Photo edited with Kodachrome recipe, taken June 2025."
- **All icon-only buttons (reset, favorites heart, delete):** Must have `accessibilityLabel`. No unlabeled tap targets.

### Color Contrast and Display

- Dark mode is the primary editing mode — light-on-dark is correct for photo editing (reduces eye adaptation lag).
- All UI chrome (slider tracks, panel backgrounds, labels) must meet WCAG AA 4.5:1 contrast ratio in both light and dark mode.
- Do not use pure black (#000000) backgrounds — use a near-black with slight warm or cool tint (e.g., `Color(white: 0.08)`) for a less harsh feel.
- Slider tracks: use system `tintColor` or a branded accent that clears 3:1 against track background.

### First-Run / Onboarding

- **Permission priming:** Do NOT ask for Photos permission on app launch without context. Trigger permission only when user taps "Import Photo" or similar — the system permission dialog has context when the user just requested the action.
- **No forced tutorial:** Drop users directly into a sample/placeholder image in the editor, or the library (empty state with a clear CTA). No swipeable tutorial screens — they are skipped universally.
- **Empty library empty state:** Show a large, friendly "Import your first photo" button with a brief one-line descriptor. Not a blank gray grid.
- **Sample photo option:** Optionally bundle one sample photo so users can immediately try the editor without granting Photos access. This is the "try before you trust" pattern.

### Performance-Related UX

- **Downsampled preview during editing:** Render to 1080p max during live slider drag; upgrade to full-res only on drag-end or export. This keeps sliders feeling instant.
- **Progress indicator on export:** Full-res render of a 12MP photo with curves + HSL takes 200–600ms. Show a non-blocking progress indicator (not a blocking spinner) during export.
- **Thumbnail generation:** Generate library thumbnails asynchronously; never block the main thread. Show a placeholder shimmer while loading.

---

## Competitor Feature Reference

| Feature | VSCO | Darkroom | Lightroom Mobile | Our Approach |
|---------|------|----------|------------------|--------------|
| Filter strip | Horizontal scroll, preview thumbnails, strength slider | Horizontal scroll, preview thumbnails | Presets panel (vertical scroll on iPhone) | Horizontal scroll strip, thumbnails, strength slider |
| Adjustment panels | Scrolling single-column list | Tabbed panels (Light, Color, Details, etc.) | Bottom tab bar → panel slides up | Scrolling grouped sections (Light, Color, HSL, Effects) |
| Before/after | Long-press on image | Dedicated compare button + long-press | Long-press | Long-press (VSCO pattern, lower friction) |
| Non-destructive | No (destructive) | Yes | Yes | Yes — core design principle |
| Recipes/Presets | Yes (VSCO Recipes) | Yes (custom filters) | Yes (Lr presets) | Yes, named recipes, save/apply/share |
| Library | Separate from Photos | Integrated with Apple Photos | Lightroom cloud catalog | In-app local library, separate from Photos |
| Export | Save to Photos, share | Save to Photos, share, batch | Save to device, share | Save copy to Photos + share sheet + format/quality |
| Haptics | Minimal | Explicit (Darkroom 7 launch note) | Minimal | Strategic (slider ends, selection, reset) |
| Tone curves | No | Yes | Yes | v2+ |
| HSL | No | Yes | Yes | v1.x |
| Social | Yes (core feature) | No | No | Explicitly not built |
| AI tools | Pro tier (object removal, upscale) | Pro tier (smart masks) | Yes (Generative Remove) | Explicitly not built |

---

## Sources

- Darkroom vs VSCO comparison (official Darkroom blog, 2024): https://darkroom.co/blog/2024-02-28-darkroom-vs-vsco
- Darkroom 7 rebuild announcement: https://petapixel.com/2025/12/10/darkroom-7-photo-editor-on-mac-iphone-and-ipad-has-been-rebuilt-from-the-ground-up/
- Darkroom update history (haptics, crop, slider notes): https://darkroom.co/updates
- Darkroom iPhone Photography School review: https://iphonephotographyschool.com/darkroom-app/
- VSCO 2026 review (filter/recipe/UI details): https://theeditingstudio.co/blog/vsco-app-review-2026
- VSCO 2025 review (worth $5/month): https://www.fahimai.com/vsco
- Lightroom Mobile crop/straighten docs: https://helpx.adobe.com/lightroom-cc/using/crop-geometry-ios.html
- Lightroom Mobile October 2025 release notes: https://helpx.adobe.com/lightroom-cc/using/whats-new.html
- Afterlight App Store listing + reviews: https://apps.apple.com/us/app/afterlight-film-photo-editor/id1293122457
- RNI Films feature overview: https://appshunter.io/ios/app/1017098672
- Apple HIG — Photo Editing: https://developer.apple.com/design/human-interface-guidelines/photo-editing
- iOS Haptic design — WWDC21: https://developer.apple.com/videos/play/wwdc2021/10278/
- Reduce Motion accessibility: https://medium.com/@amosgyamfi/reduce-motion-how-to-make-your-ios-app-animations-accessible-and-inclusive-92b9de1304fb
- iOS accessibility best practices 2025: https://medium.com/@david-auerbach/ios-accessibility-guidelines-best-practices-for-2025-6ed0d256200e
- Haptic Teardown #1 — Volume Slider (slider end-stop haptic pattern): https://bootcamp.uxdesign.cc/haptic-teardown-1-volume-slider-398145eea264
- Permission priming UX: https://www.useronboard.com/onboarding-ux-patterns/permission-priming/

---

*Feature research for: Premium iOS photo editor (VSCO Pro-style, iPhone-first)*
*Researched: 2026-05-03*
