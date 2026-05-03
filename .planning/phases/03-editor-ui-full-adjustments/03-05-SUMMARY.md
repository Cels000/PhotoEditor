---
phase: 03-editor-ui-full-adjustments
plan: "05"
subsystem: RenderEngine
tags: [hsl, cifilter, pipeline, color-grading]
dependency_graph:
  requires: [03-01, 03-02]
  provides: [applyHSL-8-channel]
  affects: [PipelineBuilder.build]
tech_stack:
  added: []
  patterns: [CIColorMatrix-band-masking, CIBlendWithMask-compositing]
key_files:
  created: []
  modified:
    - PhotoEditor/RenderEngine/PipelineBuilder.swift
decisions:
  - "HSL route: CIColorMatrix band masking + CIHueAdjust per channel (documented approximation); Metal CIColorKernel deferred to v2"
  - "hue ±1 maps to ±30° (pi/6) rotation via CIHueAdjust.angle"
  - "luminance ±1 maps to ±0.5 EV via CIExposureAdjust"
  - "saturation ±1 maps to 0...2 on CIColorControls.saturation"
metrics:
  duration: "5min"
  completed_date: "2026-05-03"
  tasks_completed: 1
  files_modified: 1
---

# Phase 3 Plan 05: HSL Per-Channel Adjustments Summary

**One-liner:** 8-channel HSL adjustments via CIColorMatrix hue-band masking + CIHueAdjust/CIColorControls/CIExposureAdjust per channel, composited with CIBlendWithMask.

## What Was Built

Replaced the `applyHSL` stub in `PipelineBuilder.swift` with a full 8-channel HSL implementation:

- **Identity guard:** All 8 channels at default zero values → early return with no filter passes (zero render cost).
- **Per-channel passes:** For each non-default channel, apply `CIHueAdjust` (angle = hue × π/6), `CIColorControls` (saturation = 1 + sat), `CIExposureAdjust` (EV = luminance × 0.5) in sequence on the running output, then composite via `CIBlendWithMask` using a band mask derived from the source image.
- **Band masking:** `hslMask(channel:in:)` uses `CIColorMatrix` to boost the target band's RGB components and suppress others, then `CIColorClamp` to constrain to 0...1 — resulting luminance image acts as the blend mask.
- **HSLBand enum:** 8 cases (red, orange, yellow, green, aqua, blue, purple, magenta) with distinct RGB coefficient vectors.

## Route Choice and V2 Deferral

The plan explicitly selected the CIColorMatrix route over a Metal CIColorKernel. This is a coarser approximation — the band masks are per-dominant-RGB-component rather than true hue-distance computation. The code comment documents this decision and defers the precise per-pixel Metal kernel to v2.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- `PhotoEditor/RenderEngine/PipelineBuilder.swift` modified with all required symbols
- Commit 98a227d exists with `feat(03-05)` message
- All 6 grep checks passed: `applyHSL`, `hueAdjust`, `blendWithMask`, `HSLBand`, `hslMask`, `deferred to v2`
