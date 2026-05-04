# AI Subject Mask — Manual Device Tests

Run these on a real iOS 17+ device after CI green and IPA installed.
The dev/CI loop is on Linux + GitHub Actions per CLAUDE.md, so this is the
only place where the actual UX gets exercised.

## Setup

- iPhone with iOS 17+
- Developer Mode ON (Settings → Privacy & Security → Developer Mode)
- IPA installed via `ideviceinstaller -i PhotoEditor.ipa`
- Library has a few test photos: at least one portrait, one group, one landscape, one with no people

## Golden Path

- [ ] **Single-person portrait**: open photo → tap mask icon → spinner shows briefly → button switches to filled icon → panel header shows `[Subject | Full | Background]` segmented control with Subject selected → adjust subject exposure +0.5 → only the person brightens, background unchanged
- [ ] **Background mode**: switch segment to Background → drop temperature −0.5 → only the surroundings cool, person stays warm
- [ ] **Full mode**: switch to Full → exposure +0.3 → both regions brighten identically
- [ ] **Mask icon active state**: with mask on, icon is filled `person.fill.viewfinder` and tinted; with no mask, icon is outlined `person.viewfinder`

## Refinement Sheet

- [ ] **Open refinement**: with mask active, tap mask icon again → bottom sheet opens with "Edit Mask" title
- [ ] **Feather slider**: drag 0 → 1 → mask edge softens visibly without halos around hair
- [ ] **Invert toggle**: flip → subject and background regions visibly swap (subject becomes the background and vice versa)
- [ ] **Group photo (3+ people)**: open such a photo → mask → refinement sheet → "Subjects" section lists `Subject 1`, `Subject 2`, … → tap one to exclude → that person's region reverts to the background stack's appearance
- [ ] **Instance overlay**: tinted regions appear above the preview at the top of the sheet → tapping a tint also toggles include/exclude
- [ ] **Done button**: dismisses sheet, mask state preserved
- [ ] **Remove Mask**: red destructive button at the bottom of the sheet → tap → confirmation dialog appears → confirm → sheet dismisses, mask is gone, sliders revert to single-stack behavior

## Edge Cases

- [ ] **Pure landscape (no foreground)**: open photo → tap mask → spinner → toast "No subject detected" appears briefly → mask icon stays in the idle (outlined, non-filled) state → no panel header sub-segment appears
- [ ] **Mask + crop**: with mask active, switch to Crop panel → rotate 90° + crop to square → composite stays correctly aligned (subject not split across the crop boundary)
- [ ] **Mask + LUT**: with mask active and Subject scope, pick a film preset → only the subject gets the LUT
- [ ] **Undo across mask add/remove**: enable mask → adjust → undo → mask disappears with one undo press; redo brings it back
- [ ] **Reset All Edits**: with mask active and edits on both stacks, tap DONE menu → Reset All Edits → confirm → mask is cleared, both stacks back to identity

## Library Round-trip

- [ ] **Save with mask active**: enable mask → adjust subject and background → DONE → Save to Library → close editor → re-open from Library → mask still active, both stacks restored, scope reset to Subject
- [ ] **Save legacy (no mask) photo**: opens with `documentData == nil`, lifts to v2 with subject = background = legacy stack, mask = nil. Sliders work.

## Export

- [ ] **Export PNG**: exported image has the masked composite baked in (subject and background edits both visible per the mask)
- [ ] **Export JPEG quality 95**: same — masked composite preserved
- [ ] **Export with no mask**: identical pixels to pre-feature behavior (subject stack only)

## Performance

- [ ] **First mask compute** on a 12 MP photo: < 1.5s on iPhone 12 or newer
- [ ] **Subsequent mask taps** (cache hit): instant
- [ ] **Slider drag in masked mode**: smooth, no >100ms hitches at 2048px preview
- [ ] **Prefetch on import**: open a fresh library photo, wait ~1s, then tap mask → spinner is brief or absent (cache hit)

## Crashes / Errors

- [ ] **Vision unavailable** (rare): fallback toast "Couldn't compute subject mask. Try again." — alert appears, mask stays disabled, no crash
- [ ] **Background app mid-compute**: app foregrounds cleanly, can re-tap mask
- [ ] **Camera-captured photo (no PHAsset)**: enterMaskMode uses fallback assetID derived from view-model identity — mask still works in-session
