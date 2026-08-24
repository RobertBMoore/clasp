# Readability research and Clasp document-style defaults

Research reviewed 2026-08-23.

## Conclusion

There is no scientifically universal "perfect" font or page format. Reading
performance depends on the reader, font metrics, visual angle, language,
display, environment, and task. The strongest product conclusion is therefore
to ship a restrained default inside well-supported bounds and let each reader
change it without changing the Markdown source.

This note uses three evidence labels:

- **Standard** — authoritative accessibility or Apple platform guidance. This
  is a product requirement or strong platform convention, not necessarily an
  experimental finding.
- **Study** — peer-reviewed empirical evidence. Findings may be limited to the
  tested font, population, display, or reading task.
- **Design judgment** — a Clasp choice made within the supported range. It must
  not be presented as a scientific optimum.

## Evidence

### Font size and font metrics

Rello, Pielot, and Marcos tested Arial from 10 to 26 points with 104 readers.
Readability and comprehension improved through approximately 18–22 points;
18 points provided the best subjective balance in that experiment. The paper
does not establish 18 points as a universal optimum, because it used one font,
one desktop setup, and short Wikipedia passages. **Study.**

- [Make It Big! The Effect of Font Size and Line Spacing on Online Readability](https://doi.org/10.1145/2858036.2858204)

Legge and Bigelow show that critical print size and x-height, not the nominal
point value alone, constrain fluent reading. Fonts with the same point size can
look materially different. Clasp should preserve apparent size when a reader
changes families instead of assuming equal point sizes are perceptually equal.
**Study.**

- [Does print size matter for reading?](https://doi.org/10.1167/11.5.8)

### Font family

Apple identifies SF Pro as the macOS system family and provides the document
user-font API for editable document text. Using the system document font is the
most native and lowest-risk default for Clasp. **Standard.**

- [Apple Human Interface Guidelines: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)

Controlled testing by Arditi and Cho found no continuous-reading advantage
that could be attributed merely to the presence or absence of serifs. Clasp
must not claim that serif or sans serif is universally superior. **Study.**

- [Serifs and font legibility](https://doi.org/10.1016/j.visres.2005.06.013)

Wallace and colleagues found substantial within-reader variation across fonts:
participants read an average of 35% faster in their fastest tested font than
their slowest without reduced comprehension, and there was no single fastest
font for everyone. This strongly supports reader-selectable families and sizes.
The study concerned short, interleaved digital reading rather than complete
long-form books, so its exact effect size must not be generalized carelessly.
**Study.**

- [Towards Individuated Reading Experiences](https://doi.org/10.1145/3502222)

### Line length, spacing, and reflow

Dyson and Haselgrove found a medium 55-character line supported effective
screen reading better than the shorter and longer conditions they tested.
WCAG's optional enhanced visual-presentation mechanism caps prose at 80
characters or glyphs (40 for CJK) and requires left-aligned rather than fully
justified text. A target between those values is justified; an exact target of
68 characters is a Clasp design choice. **Study, Standard, and design
judgment.**

- [The influence of reading speed and line length on the effectiveness of reading from screen](https://doi.org/10.1006/ijhc.2001.0458)
- [WCAG 2.2: Understanding Visual Presentation](https://www.w3.org/WAI/WCAG22/Understanding/visual-presentation.html)

Evidence for one ideal line-height value is weaker. The Rello study found
extreme tested spacings could impair comprehension but did not establish a
universal optimum. W3C advises 1.5 line spacing as an accessible presentation
and requires content to tolerate user spacing overrides without clipping or
loss. A 1.55 default is a conservative Clasp design judgment, not a proven
optimum. **Study, Standard, and design judgment.**

- [WCAG 2.2: Understanding Text Spacing](https://www.w3.org/WAI/WCAG22/Understanding/text-spacing)

WCAG's text-spacing criterion does **not** require every document to start at
1.5 line height, 2 em paragraph spacing, 0.12 em letter spacing, or 0.16 em word
spacing. It requires the presentation to remain usable when a reader applies
those overrides. Clasp should test this explicitly. **Standard.**

### Contrast, color, and appearance

WCAG requires at least 4.5:1 contrast for ordinary text and recommends 7:1 at
the enhanced level. Meaningful control boundaries and graphical cues need 3:1
against adjacent colors. Links must not rely on color alone. **Standard.**

- [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
- [WCAG 2.2: Understanding Non-text Contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast)

Apple recommends adaptive semantic colors, sufficient contrast in every
appearance, and avoiding a naive inversion of light colors for Dark Mode.
Clasp should follow the system appearance by default and support Increase
Contrast. **Standard.**

- [Apple Human Interface Guidelines: Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)

Several controlled proofreading studies found better performance with dark
text on a light background, although luminance, reader age, task, and display
conditions affect the result. This is not sufficient reason to override a
reader's chosen macOS appearance. **Study.**

- [Text-background polarity affects performance irrespective of ambient illumination and colour contrast](https://doi.org/10.1080/00140130701306413)
- [Smaller pupil size and better proofreading performance with positive than with negative polarity displays](https://doi.org/10.1080/00140139.2014.948496)

### Structure, headings, and whitespace

Logical headings, semantic lists, whitespace, and consistent grouping help
people navigate and understand long content. Visual heading treatment must
retain the Markdown heading level for VoiceOver and other assistive technology.
W3C does not prescribe Clasp's exact heading sizes, margins, quote border, or
code-block radius; those are design-system choices. **Standard and design
judgment.**

- [W3C Page Structure Tutorial](https://www.w3.org/WAI/tutorials/page-structure/)
- [W3C Cognitive Accessibility: Use White Spacing](https://www.w3.org/WAI/WCAG2/supplemental/patterns/o3p10-whitespace/)
- [W3C Cognitive Accessibility: Clear Page Structure](https://www.w3.org/WAI/WCAG2/supplemental/patterns/o2p03-page-structure/)

## Recommended Clasp presets

These are product defaults, not universal scientific optima. Sizes are macOS
points, line height is a multiplier of body size, the table expresses
paragraph spacing relative to body size, and measure is the target number of
characters per line. `DocumentStyle` stores the corresponding paragraph gaps
as 12, 8, 16, and 10 points so the values remain straightforward in AppKit.

| Preset | Body | Line height | Paragraph | Measure | Intended use |
| --- | ---: | ---: | ---: | ---: | --- |
| **Balanced** | 18 pt | 1.55 | 0.67 em | 68 | Default long-form reading and editing |
| **Compact** | 16 pt | 1.40 | 0.50 em | 76 | More context on smaller windows |
| **Spacious** | 20 pt | 1.75 | 0.80 em | 56 | Low-density, highly separated reading |
| **Technical** | 16 pt | 1.50 | 0.625 em | 72 | Notes with frequent code and tables |

All presets should default to:

- the native macOS document font for prose and SF Mono for code;
- regular body weight with no extra tracking;
- left-aligned, ragged-right prose;
- a continuous, page-like canvas rather than artificial print page breaks;
- System appearance and semantic colors;
- ordinary body contrast targeting at least 7:1 and never below 4.5:1;
- responsive reflow with no horizontal scrolling for prose; and
- presentation metadata stored separately from the Markdown content.

At 18 points, Balanced should normally produce a text column around 620–680
points and a page-like canvas around 760–820 points including margins. Exact
point widths are secondary to measuring the rendered font and maintaining the
target character count. **Design judgment.**

Suggested visual hierarchy for Balanced:

| Element | Size / line height | Notes |
| --- | --- | --- |
| Document title | 34 / 41 pt | Bold |
| Heading 1 | 30 / 37 pt | Semibold |
| Heading 2 | 25 / 32 pt | Semibold |
| Heading 3 | 21 / 28 pt | Semibold |
| Heading 4 | 19 / 27 pt | Semibold |
| Heading 5–6 | 18 / 27 pt | Use weight and spacing, not all caps |
| Inline code | 0.9 em | SF Mono with a subtle background |
| Code block | 15 / 23 pt | Preserve source; wrapping is a presentation preference |
| Block quote | Body size | Whitespace plus a restrained 3 pt cue; avoid whole-block italics |

These exact sizes and spacings are **design judgments**. The evidence-backed
requirement is a clear, consistent semantic hierarchy.

## Presentation-only contract

Markdown remains the canonical content. A document style changes rendering,
not stored prose. Applying a preset, changing appearance, zooming, or changing
font/spacing/measure must not:

- insert CSS, HTML, front matter, or application-specific tokens into a note;
- change Markdown bytes merely because the reader switched modes or presets;
- alter export or copy-as-Markdown output; or
- move a note between Inbox and Vault.

Rich and source editing may both edit the canonical Markdown, but style changes
must remain independent presentation state. Global defaults and optional
per-note overrides should be stored in Clasp preferences or metadata outside
the `.md` body.

## Accessibility and localization acceptance

- Support font family, apparent size, line height, paragraph spacing, measure,
  theme, and code-wrap controls, plus a one-action reset to Balanced.
- Reflow prose at 200% text size without clipping, overlap, or back-and-forth
  horizontal scrolling.
- Remain usable under WCAG spacing overrides: 1.5 line height, 2 em paragraph
  spacing, 0.12 em letter spacing, and 0.16 em word spacing.
- Preserve heading levels, list structure, checklist state, links, quotes, and
  code semantics for VoiceOver.
- Use color plus a non-color cue for links and state.
- Test System, Light, Dark, and Increase Contrast appearances.
- Do not apply Latin-specific measure and spacing assumptions blindly to other
  writing systems. In particular, use the 40-glyph WCAG maximum for CJK and
  respect script-specific paragraph conventions.
