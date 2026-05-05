---
phase: quick-260505-e3t
plan: "01"
type: research
subsystem: histogram
tags: [core-image, histogram, colorspace, bug-research]
dependency_graph:
  provides: [root-cause-analysis, canonical-fix-pattern]
  requires: []
  affects: [PhotoEditor/Editor/HistogramRenderer.swift, PhotoEditor/Editor/EditorViewModel.swift]
tech_stack:
  patterns: [CIAreaHistogram-readback, DeviceRGB-passthrough]
key_files:
  created:
    - .planning/quick/260505-e3t-research-rgb-histogram-only-shows-red-ch/260505-e3t-RESEARCH.md
decisions:
  - "Root cause: colorSpace:nil in context.render() applies P3/sRGB transforms to count data"
  - "Fix 1 (sufficient): pass CGColorSpaceCreateDeviceRGB() instead of nil"
  - "Fix 2 (latent safety): use bins.extent instead of hardcoded CGRect"
  - "scale=1.0 hypothesis refuted: CI divides by extent area, values stay in [0,1]"
metrics:
  duration: "35 minutes"
  completed: "2026-05-05"
  tasks_completed: 1
  tasks_total: 1
---

# Phase quick-260505-e3t Plan 01: RGB Histogram Red-Only Bug Research Summary

**One-liner**: `colorSpace:nil` in `context.render()` lets Core Image apply P3→sRGB matrix to histogram count data, zeroing G and B; fix is `CGColorSpaceCreateDeviceRGB()`.

## Deliverable

Full research findings are in:
`.planning/quick/260505-e3t-research-rgb-histogram-only-shows-red-ch/260505-e3t-RESEARCH.md`

## Key Findings

1. **Root cause confirmed (Hypothesis 1)**: `HistogramRenderer.render()` passes `colorSpace: nil` to `context.render()`. Apple documents this as "use the output color space of the context." The `histogramContext` has no explicit output colorspace, so CI applies a colorspace transform (extLinearSRGB→device display = P3 on modern iPhones) to the histogram count data. This is a 3×3 matrix multiply that mixes channel values, destroying per-channel independence for G and B.

2. **Contributing factor (Hypothesis 5)**: Using `CGRect(x:0,y:0,width:256,height:1)` instead of `bins.extent` is a latent fragility. Likely not causing the current bug (preview CGImages have origin 0,0) but a silent failure waiting for any non-zero-origin input.

3. **Hypothesis 2 refuted**: Apple's CI Filter Reference documents `inputScale` as "Core Image scales the histogram by dividing the scale by the area of the inputExtent rectangle." Values are already in [0,1] with scale=1.0. No overflow or clamping.

4. **Hypothesis 3 not a bug**: GraphicsContext is a struct; the `var layer = ctx` copy pattern is correct.

## Minimal Fix (1 line)

In `PhotoEditor/Editor/HistogramRenderer.swift` line 51, change:
```swift
colorSpace: nil
```
to:
```swift
colorSpace: CGColorSpaceCreateDeviceRGB()
```

Apply simultaneously: change line 43 `CGRect(x:0,y:0,width:256,height:1)` → `bins.extent`.

## Self-Check: PASSED

- RESEARCH.md exists: confirmed (468 lines)
- Covers CIAreaHistogram colorspace semantics: yes (Section 1, Hypothesis 1)
- Covers bins.extent vs hardcoded bounds: yes (Section 1, Hypothesis 5)
- Canonical implementation code present: yes (Section 2, complete function body)
- Hypotheses ranked with clear "try this first": yes (Section 3, ranked table)
