# Clasp marketing site — design QA

## Source and implementation

- Selected source: `../artifacts/clasp-brand-directions-2026-08-29/01-quiet-instrument.png`
- Desktop implementation: `qa/desktop-hero-v2.png` at 1440 × 1000 CSS px
- Mobile implementation: `qa/mobile-hero.png` and `qa/mobile-demo.png` at 390 × 844 CSS px
- Direct comparison: `qa/design-comparison.png` at 1600 × 1000 CSS px
- Interactive app capture: `qa/app-window.png` at 1440 × 1000 CSS px
- Native dark-mode check: isolated `Clasp Visual QA` build inspected on macOS

## Comparison passes

### Pass 1

- **P1 · Imagery:** the first hero used constructed decoration around the icon instead of showing believable product content. Replaced it with a real capture of the working interactive demo and the production icon asset.
- **P1 · Responsive behavior:** the desktop-width demo was horizontally cropped on a phone and hid the editor. Added a mobile document-focused layout with usable Page/Markdown controls and toolbar.
- **P1 · Sidebar behavior:** closing the sidebar left a zero-width ghost column and compressed the editor. Changed the collapsed grid to two real columns.
- **P2 · Icon quality:** the first generated icon was soft and textured; the second had an opaque exterior matte. Regenerated crisp flat artwork, removed the exterior matte, created a 2048 px alpha master, and rebuilt the full macOS iconset and `.icns`.
- **P2 · Checklist behavior:** GFM checkboxes rendered disabled. The demo now deliberately exposes them as interactive controls and writes the changed state back into the canonical Markdown string.
- **P2 · Content safety:** the selected concept's seed-phrase example was unsafe for the product. Replaced it with public-address research and recovery-procedure guidance plus an explicit instruction to keep seed phrases, private keys, recovery codes, and signing credentials in purpose-built storage.

### Pass 2

- Recompared the 1440 px desktop implementation directly beside the selected Quiet Instrument board.
- Confirmed the paper, ink, indigo, copper, editorial serif, restrained borders, realistic app capture, prelaunch state, and safety hierarchy remain coherent.
- Confirmed mobile hierarchy, wrapping, tap targets, and document readability at 390 × 844.
- Confirmed the browser console has no warnings or errors.
- No remaining P0, P1, or P2 findings.

## Functional checks

- Inbox, All Notes, Pinned, Vault, and Trash navigation
- Search filtering
- Vault locked, unlocked, and synthetic safe-note states
- Page → Markdown → Page source synchronization
- Bold Markdown presentation after a source edit
- Checklist click writes the expected `[x]` / `[ ]` source change
- Light/dark transition
- Sidebar collapse and restore
- Desktop and mobile layouts
- Canonical public Support and Privacy links

## Build and native evidence

- `npm run build`: passed
- `npm run test:sites`: 4 passed, 0 failed
- `swift test`: 197 passed, 0 failed
- Document palette test: light and dark primary text both meet at least 7:1 contrast against their page surface
- `dist/Clasp.app`: locally signed and validated
- Packaged `AppIcon.icns`: byte-for-byte matches the rebuilt source `.icns`

## Result

**Passed.** The marketing prototype is locally verified and ready for review. It has not been published.
