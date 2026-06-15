---
name: generic
---
# Profile: generic (fallback)

## Detection
Selected when no language-specific profile matches. See `detect.sh stacks`.

## Toolchain
None. Reasoning-only against `baseline-categories.md`.

## Reasoning checklist
Walk all five baseline categories. With no tool ground truth, every finding here
is at most Medium unless adversarial verification produces a clear repro path.

## Auto-fix-safe
Nothing is auto-fix-safe in the generic profile (no tool confirmation available).
