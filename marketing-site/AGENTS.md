# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

The approved brand direction is “Quiet Instrument”: warm paper, near-black ink, deep indigo, restrained copper, editorial serif headlines, and native-feeling sans-serif controls. Avoid blue-purple AI gradients, glass-heavy cards, security clichés, fake testimonials, and generic crypto imagery. Marketing examples must use realistic synthetic data and must never depict seed phrases, private keys, recovery codes, or signing credentials stored in Clasp.

After this website is live, every user-facing Clasp UI/UX change requires an interactive-demo impact check. If the change affects a screen, control, navigation path, copy, visual token, theme, editor behavior, Vault, capture flow, or Markdown presentation shown here, update and verify the demo against fresh screenshots from the same release candidate.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.
