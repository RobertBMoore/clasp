# Clasp document-style visual QA

Date: 2026-08-23
Final result: **passed**

## Comparison target

- Visual truth: `/var/folders/nx/6dvbxncx749gjsx418vtyv6m0000gn/T/codex-clipboard-e2f812d6-5a8b-4c02-a050-1510bbd1df1b.png`
- Preserved reference: `artifacts/visual-qa-2026-08-23/document-style-20260823-222656/reference.png`
- Final implementation capture: `artifacts/visual-qa-2026-08-23/document-style-20260823-222656/implementation-final-build7-window-373432-foreground-normalized.png`
- Final side-by-side comparison: `artifacts/visual-qa-2026-08-23/document-style-20260823-222656/comparison-final-build7-reference-left-implementation-right.png`
- Focused semantic-marker capture: `artifacts/visual-qa-2026-08-23/document-style-20260823-222656/focused-semantic-markers-page-window-373432.png`
- QA application: `dist/Clasp Visual QA 20260823-224349.app`

The QA application was staged from the final working tree after the release metadata update. Its artifact-only identity is `com.robertmoore.personalnotepad.visualqa.qa20260823224349`, its display name is `Clasp QA 224349`, and its stamped version is `1.0.0` (build `7`). The generated bundle was re-signed ad hoc and passed strict deep signature verification. The application binary SHA-256 is `a45cecdb1c1b969e3331ca10875a0bceeb40d80fe919cae4b062882fff719dc6`; the generated `Info.plist` SHA-256 is `641c119110b0320c902b6f9467d3b437f4fca5b4b03b01c835fdebc36634fc77`.

## Normalization and state

- The reference is 2396 x 2034 pixels at 2x scale (1198 x 1017 points).
- The final implementation window is 2396 x 2040 pixels at 2x scale (1198 x 1020 points), the nearest native size allowed by the app's minimum window height.
- The combined comparison keeps the shared 2396 x 2034-pixel content area and crops only the bottom 6 implementation pixels (3 points). No scaling was applied to either side.
- Both sides use the light appearance, Inbox collection, selected `Launch checklist` note, and the formatted reading state (`Formatted` in the reference, renamed `Page` in the implementation).
- Only the QA application's resolved window ID (`373432`) was captured. No full-screen or unrelated-window capture was used.

## Fidelity review

### Layout and spacing

The three-column native layout, sidebar/list proportions, blue selected-row treatment, editor toolbar placement, and note content align with the reference's structure. The implementation deliberately changes the editor from a flat edge-to-edge canvas to a centered, bordered paper surface with a narrower reading measure and more vertical whitespace. At the normalized viewport there is no clipping, overlap, unintended overflow, or unstable reflow.

### Typography

Hierarchy is clear and internally consistent: the note heading, introductory copy, list content, focus block, and footer metadata remain distinct. The implementation intentionally replaces the reference's larger serif formatted-view typography with the product's system-sans Page style. The focus sentence wraps to two lines because of the narrower paper measure; it remains fully visible and balanced.

### Color and surfaces

The final capture uses the requested light appearance. System background, white paper surface, separators, secondary text, blue selection/focus accents, and muted semantic markers are coherent and maintain readable contrast. No accidental dark-mode colors or stale appearance state are visible.

### Icons and copy

The toolbar uses sharp native system symbols; no raster-image fidelity issue is present in the compared surface. Copy is coherent and app-specific: `Page`, `Markdown`, and `Stored as Markdown` communicate the two representations without exposing a different storage format. The expanded toolbar is deliberate and remains unclipped.

## Semantic marker review

A separate memory-only synthetic note was used so the document bytes on disk were not changed. It exercised a bullet, checked and unchecked tasks, a blockquote, a thematic break, and a fenced Swift block. The source was set and verified exactly before switching to Page mode.

- Bullets and task markers remain visible and legible as `-`, `- [x]`, and `- [ ]`; task meaning is no longer lost.
- The blockquote retains a visible `>` cue and differentiated secondary treatment.
- The thematic break retains a visible muted `---` cue.
- Opening/closing code fences, the language tag, code text, and a differentiated code background remain visible.
- Page/Markdown mode switching was exercised through the native controls and the selected radio state changed correctly.

Two non-blocking P3 polish opportunities remain: render the thematic break as a stronger full-width rule, and unify the fenced-code background into one cohesive container. The current cues are still visible, preserve the exact Markdown source, and do not rise to P0-P2 severity.

## Findings and iteration history

| Pass | Evidence | Finding | Result |
| --- | --- | --- | --- |
| Initial final-size capture | `implementation-pre-fix-window-371456.png` | **P2:** Page styling globally hid Markdown marker ranges, which removed checklist meaning from the visible reference note. | Fixed. Semantic block markers were restored without altering source bytes. |
| Focused intermediate proof | `implementation-post-marker-fix-window-373092-tiny.png` | Marker visibility returned, but the temporary undersized proof window was not suitable for final comparison. | Rejected as acceptance evidence; retained for history. |
| Final build 7 capture | `implementation-final-build7-window-373432-foreground-normalized.png` and the combined comparison | No remaining P0, P1, or P2 visual or interaction defect was observed. | Passed. |

The final marker implementation is integrated with the existing single analyzer pass and its 100,000 UTF-16-unit semantic-styling cap; documents above the cap retain exact base typography rather than triggering an uncapped second parse.

## Verification checklist

- [x] Deterministic `CLASP_VISUAL_QA` launch selected the expected fixture note.
- [x] Fresh uniquely named QA bundle was staged without overwriting prior artifacts.
- [x] Version `1.0.0` and build `7` were stamped by the corrected staging script.
- [x] Bundle ID and display name were changed only in the generated QA `Info.plist`.
- [x] Generated QA application was re-signed and its signature verified.
- [x] Light appearance was forced for the unique QA bundle.
- [x] Capture was scoped to the QA application's exact native window ID.
- [x] Reference and implementation were compared at the same width and normalized height.
- [x] Page/Markdown switching and semantic-marker visibility were exercised.
- [x] Focused Markdown source-editing tests passed: 18 tests, 0 failures.
- [x] No source file was edited during the final frozen capture pass.

No blocking visual-design question remains. The centered Page surface and system-sans typography are intentional product changes rather than unintentional reference drift.
