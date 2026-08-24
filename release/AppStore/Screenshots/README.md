# App Store screenshot candidates

Status: **dimension-validated visual candidates, not final signed-build submission evidence**

These five screenshots were captured on 2026-08-24 from the isolated synthetic-data bundle `/private/tmp/Clasp Visual QA build8 20260824-0233-docfit.app`, version `1.0.0` build `8`. No production notes, Vault content, credentials, or unrelated windows are present.

Every image is a non-transparent JPEG at Apple’s accepted 2560×1600 Mac screenshot size. `script/validate_app_store_screenshots.sh` enforces the 1–10 image limit, accepted dimensions, supported format, no alpha channel, no symlinks, a flat file set, and the exact `SHA256SUMS` manifest.

| Order | Candidate | SHA-256 |
| --- | --- | --- |
| 1 | `01-clasp-editor-light-2560x1600.jpg` | `5fc0faf556b61bdf2b268bcf040a5ceac2710cd169c34c818d2a9477963db001` |
| 2 | `02-clasp-markdown-source-2560x1600.jpg` | `9cd34f1708f168c9bfbb91acbdcde37c6900a91a74a162d669a950a1ccbe5765` |
| 3 | `03-clasp-document-style-2560x1600.jpg` | `a1d4b59e12835fe702be0ac0f7b6e2eaf7fff4684d502b19ac554ac63581f0dd` |
| 4 | `04-clasp-editor-dark-2560x1600.jpg` | `5cfd2cd58bc29b05a1cdaa277f1067034208e25f2314cc46b9cd0d7ed61fedb1` |
| 5 | `05-clasp-rich-formatting-2560x1600.jpg` | `aebe505070d01fbc4730024be54d887a43ea67f6f4bf0c662d10cb06e9ab603d` |

Before submission, compare these images with the exact final signed Store build. Recapture any screen whose visible behavior differs, rerun the validator, record the final hashes in `SUBMISSION_HANDOFF.md`, and have Robert approve the ordering and visible copy. A candidate screenshot cannot substitute for signed-sandbox acceptance.
