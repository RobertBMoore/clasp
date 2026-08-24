# Clasp document-style visual QA

## Build 8 acceptance supplement

Date: 2026-08-24
Current result: **passed for the installed local product; external release gates remain separate**

The final Build 8 QA application was staged as `/private/tmp/Clasp Visual QA build8 20260824-0233-docfit.app`. The production local bundle was then built, validated, installed at `/Applications/Clasp.app`, and launched successfully. Its identity is `com.robertmoore.personalnotepad`, version `1.0.0` (build `8`), architecture `arm64`; the installed and staged executables share SHA-256 `4d2f40064649806b91babce2b4eef3617dd948494087799134cba4816a297d46`. The installed bundle passes strict deep code-signature validation with its expected local ad-hoc signature and contains no Sparkle linkage. This is local installation evidence, not Apple distribution signing or notarization evidence.

### Current interaction acceptance

- Page and Markdown remain a source-exact two-way editor. Switching modes, typing, selecting text, and applying inline or block formatting preserve selection and scroll position without observed layout jumps.
- Applying Italic to a selected phrase kept the selection in place and changed only that phrase to `*selected text*` in Markdown.
- Applying Heading 2 to a mid-line selection isolated only that selection on its own `##` line while leaving the surrounding source intact.
- Clicking a Page-mode checklist control changed exactly one source marker from `- [ ]` to `- [x]`.
- The in-app Style menu stayed inside the editor pane, supported keyboard dismissal with Escape, and dismissed on click-away without moving the document.
- Every Settings tab was inspected at the fixed window size. Appearance changed atomically among Light, Dark, and System; Documents fit the initial viewport without clipping or a surprise scrollbar; Clipboard and Vault warning states retained stable geometry.
- The shortcut recorder exposed clear Replace, Clear, Cancel, Reset, conflict, and availability states. macOS Services and one-step selection/clipboard shortcut paths were visible without hiding the instructions behind a disclosure control.
- The installed `/Applications/Clasp.app` launched into an accessible native window after installation.

### Current visual evidence

- Style menu in bounds: `/var/folders/nx/6dvbxncx749gjsx418vtyv6m0000gn/T/com.openai.sky.CUAService/Clasp Visual QA Screenshot 2026-08-24 at 2.27.10 AM.jpeg`
- Documents settings fit: `/var/folders/nx/6dvbxncx749gjsx418vtyv6m0000gn/T/com.openai.sky.CUAService/Clasp Visual QA Screenshot 2026-08-24 at 2.32.52 AM.jpeg`
- Dark settings: `/var/folders/nx/6dvbxncx749gjsx418vtyv6m0000gn/T/com.openai.sky.CUAService/Clasp Visual QA Screenshot 2026-08-24 at 2.33.10 AM.jpeg`
- Dark main window: `/var/folders/nx/6dvbxncx749gjsx418vtyv6m0000gn/T/com.openai.sky.CUAService/Clasp Visual QA Screenshot 2026-08-24 at 2.33.22 AM.jpeg`
- Final light Page view: `/var/folders/nx/6dvbxncx749gjsx418vtyv6m0000gn/T/com.openai.sky.CUAService/Clasp Visual QA Screenshot 2026-08-24 at 2.34.28 AM.jpeg`
- Installed-app launch: `/var/folders/nx/6dvbxncx749gjsx418vtyv6m0000gn/T/com.openai.sky.CUAService/Clasp Screenshot 2026-08-24 at 2.44.24 AM.jpeg`

Reference and implementation captures were also viewed as combined comparisons at `/private/tmp/clasp-editor-reference-final.png`, `/private/tmp/clasp-theme-reference-final.png`, and `/private/tmp/clasp-docsettings-reference-final.png`. The Build 8 implementation retains the requested three-pane Mac structure while improving the editor with a centered paper surface, native checkboxes, stable full Markdown controls, atomic semantic appearance, and balanced document settings. No P0-P2 visual or editor-interaction defect remained in this acceptance pass.

### Current automated boundaries

- Local Release, arm64: 185/185 tests passed; Sparkle absent.
- App Store Release, arm64: 179/179 tests passed; Sparkle and forbidden direct-capture symbols absent.
- Direct Release, arm64: 185/185 tests passed with the locked Sparkle 2.9.6 dependency.
- Focused document and release UI acceptance: 26/26 tests passed after the final settings-fit adjustment.
- Workflow syntax, shell lint, packaging fixtures, dependency-lock custody, direct-update acceptance contracts, and release workflow contract tests passed.

The following Build 7 record is retained as historical comparison evidence.

Date: 2026-08-23
Historical result: **passed**

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
