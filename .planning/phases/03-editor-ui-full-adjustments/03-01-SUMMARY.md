---
phase: 03-editor-ui-full-adjustments
plan: 01
subsystem: RenderEngine
tags: [cifilter, light, tonecurve, pipeline]
dependency_graph:
  requires: []
  provides: [applyLight-complete]
  affects: [all downstream UI plans that exercise Whites/Blacks sliders]
tech_stack:
  added: [CIToneCurve (CIFilterBuiltins)]
  patterns: [gated CIFilter insertion — filter block skipped entirely when value is zero]
key_files:
  created: []
  modified:
    - PhotoEditor/RenderEngine/PipelineBuilder.swift
key_decisions:
  - "Whites/Blacks mapped via CIToneCurve 5-point shaping: input -1...+1 scales to ±0.3 endpoint shift in normalized (0-1) curve space; mid-points held on identity diagonal"
  - "Gate on (whites != 0 || blacks != 0) preserves identity-stack guarantee — no CIFilter allocation when sliders are at zero"
metrics:
  duration: 5min
  completed: 2026-05-03
  tasks: 1
  files: 1
---

# Phase 3 Plan 01: Whites/Blacks CIToneCurve Implementation Summary

**One-liner:** Whites/Blacks fully wired via 5-point CIToneCurve endpoint shaping — applyLight now covers all 6 light controls.

## What Was Built

The Phase-1 whites/blacks stub (`// Phase 1 stub — no-op`) in `PipelineBuilder.applyLight` was replaced with a live CIToneCurve implementation.

**Curve mapping:**
- Input range: `-1...+1` for both `whites` and `blacks`
- Endpoint shift magnitude: `input × 0.3` in normalized curve space
- `blacks > 0`: lifts point0's X coordinate (`p0x = blacksShift`), pulling the black point right and brightening shadows
- `blacks < 0`: drops point0's Y coordinate (`p0y = -blacksShift`), crushing blacks toward zero
- `whites > 0`: moves point4's X coordinate left (`p4x = 1 - whitesShift`), brightening highlights by reaching full output sooner
- `whites < 0`: drops point4's Y coordinate (`p4y = 1 + whitesShift`), compressing the white point below 1.0
- Points 1–3 remain on the identity diagonal (0.25, 0.5, 0.75)

**Identity guarantee preserved:** the entire block is guarded by `if light.whites != 0 || light.blacks != 0`, so an identity `AdjustmentStack` (all zeros) still returns the input image with zero filters applied.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- PipelineBuilder.swift: FOUND
- Commit e2e5083: FOUND
