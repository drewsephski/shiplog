# Shiplog identity

A folded S connects the journal to the work moving forward. The icon uses warm ivory paper against near-black; the companion logo reduces that silhouette to a single color.

## Deliverables

- `exports/shiplog-app-icon.png` — opaque 1024 × 1024 App Store icon, square and unmasked.
- `exports/shiplog-symbol.svg` — scalable symbol with `currentColor` fill.
- `exports/shiplog-symbol.pdf` — vector symbol used by Apple's asset catalog.
- `exports/shiplog-symbol.png` — transparent 1024 × 1024 black symbol for other tools.
- `source/shiplog-icon-master.png` — original generated artwork, preserved unchanged.
- `source/shiplog-symbol.svg` — the clean vector companion geometry.

## App usage

`ShiplogBrand.swift` provides the appearance-aware mark, native SF wordmark lockup, and icon tile. Today uses the standalone mark, onboarding uses the lockup, and Settings uses the same artwork as the installed icon. Decorative marks are hidden from accessibility; the wordmark remains readable. The logo follows the system's primary color for light mode, dark mode and increased contrast. The icon retains its fixed ivory/near-black treatment.

The PDF retains vector data and renders as a template. The source canvas carries the icon's clear space; the in-app mark uses a deliberate crop of that empty space. Keep the glyph's proportions, negative-space cuts and slopes unchanged. Use the monochrome logo on content surfaces; reserve the shaded icon for app identity. Avoid outlines, additional effects and recoloring individual folds.

## Reproduce exports

From the repository root:

```sh
swift scripts/generate-icon.swift
```

The script sizes and encodes the icon, and produces matching SVG, PDF and PNG logo exports from one canonical vector path. It uses only Apple frameworks. It does not regenerate artwork or upload a build. Changes appear on installed devices after a new app build is distributed; TestFlight build 1 retains the original icon.

## Artwork provenance

The icon was created with the built-in imagegen tool. Two automatic transparent-logo extraction attempts produced rough raster artifacts and were discarded. The shipped companion logo is a clean vector redraw of the icon silhouette, preserving its proportions and open cuts. The wordmark uses native system typography rather than generated text.

Final icon prompt:

> Use case: logo-brand. Asset type: production iPhone app icon for Shiplog, a personal build journal for software builders. Create ONE final square icon, flat straight-on full-bleed artwork, not a mockup or presentation sheet. Design a bespoke striking geometric S monogram made of two broad interlocking folded-paper ribbons: architectural, precise, compact, slightly ascending, evoking a journal's folded pages and work moving forward. The S must be immediately legible as a single strong distinctive silhouette at 32px, with generous open negative-space cuts, equal-weight strokes, chamfered corners and carefully softened edges. Upper right terminal subtly points forward/up without a separate arrow. Taste: premium editorial identity, quiet confidence, native Apple productivity, Linear-level precision. Color: warm ivory symbol on solid near-black #101113 background; extremely subtle tonal definition only within the fold planes, predominantly flat high contrast. Symbol centered optically and occupying about 58% of square width and height, ample uninterrupted dark space. Output a crisp 1024x1024 opaque square, background reaching every edge; no outer rounded corners, Apple applies its mask. No typography, letters besides the designed S, no terminal window, no rocket, ship, anchor, checkmark, sparkle, gradient, glow, texture, glass, chrome, border, drop shadow, perspective, watermarks, or additional objects. This is a polished App Store production icon, not a generic pictogram.
