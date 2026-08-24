---
layout: default
title: Clasp Privacy Policy
---

# Clasp Privacy Policy

Last updated: August 24, 2026

Paper LLC publishes Clasp. This policy explains how Clasp for Mac handles information and how the separate support channels linked from this page work.

## The short version

Clasp is designed to keep note content on the user's Mac. It does not require an account. The Mac App Store build has no developer-operated network client, advertising, analytics, tracking, cloud sync, or external AI service. It does not transmit note bodies, titles, tags, Vault content, clipboard content, images, recognized image text, identifiers, or app telemetry to Paper LLC.

Support messages and public GitHub Issues are separate from the app. They may contain information a person chooses to submit and routine account or delivery metadata handled by the selected service provider.

## Information Paper LLC receives through support

The Clasp app does not collect support information automatically. A person may voluntarily send Paper LLC an email or GitHub report containing an email address or GitHub account name, Clasp version and build, macOS version, Mac model, reproduction steps, expected and observed results, and an optional screenshot or other diagnostic the person chooses to provide.

Paper LLC uses that information only to respond to the request, diagnose and correct product or security issues, prevent abuse, and improve Clasp. It is not sold, used for advertising, or used to build an advertising profile.

## Information stored on the Mac

Regular notes are stored as local Markdown. Regular-note bodies, titles, tags, image attachments, recognized image text, organizational information, and timestamps are plaintext by design. Anyone or any process with access to those files may be able to read them.

Vault content is encrypted locally with AES-GCM using a random 256-bit key. Clasp requires macOS device-owner authentication before reading or creating that key in Keychain. Vault titles, tags, bodies, image data, recognized image text, organizational information, and timestamps are encrypted at rest. Decrypted Vault content exists in memory while the Vault is unlocked.

There is no Clasp account, recovery service, or encryption backdoor. An encrypted Vault export uses a separately generated recovery key that Clasp displays once and does not retain. Losing that recovery key makes the export unrecoverable.

## Clipboard, selected content, images, and files

Clasp reads clipboard or selected content only after the user invokes a capture action. The app does not maintain clipboard history. Optional safe clearing for a Vault capture can clear only the captured clipboard value if it has not changed; clipboard managers or other apps may already have retained a copy.

Mac App Store selected-content capture uses macOS Services. Import, export, formatting conversion, classification, and Apple Vision image-text recognition run locally. Clasp does not use a web view or fetch remote resources when it imports supported formatted content.

User-selected Vault imports and exports are read from or written to locations the user chooses. Vault exports remain encrypted and require their recovery key. Regular notes remain plaintext Markdown files in Clasp's local storage.

## Network and update behavior

The Mac App Store build receives software updates through Apple and does not include Clasp's direct-download updater.

A separately distributed direct-download build can contact Clasp's GitHub-hosted Sparkle update feed over HTTPS to check for and retrieve signed software updates. That updater does not send note, Vault, clipboard, account, analytics, or telemetry data. Apple and GitHub may process routine store, download, update, hosting, or connection information under their own terms and privacy policies.

## Support information

If a person emails support, Paper LLC receives the information that person chooses to provide and uses it to respond to and investigate the request. Email providers process those messages as part of delivering the service.

GitHub Issues are public and are processed by GitHub. GitHub's private vulnerability reporting form is private to authorized repository participants, but it still requires information to be submitted to GitHub. Support submissions are not collected by the Clasp app. Do not send note content, Vault files, recovery keys, credentials, or other sensitive information in an initial report. Paper LLC will explain through a private channel if a narrowly scoped, non-secret diagnostic is needed. Never send an encrypted Vault export together with its recovery key.

Paper LLC uses email-service providers to receive support mail and GitHub to host public issues, source, update artifacts, and private vulnerability reports. Apple separately operates App Store distribution and updates. Paper LLC requires any service provider or other party it authorizes to process user information to protect that information to the same or an equivalent standard as this policy and Apple's applicable privacy requirements. Clasp does not integrate advertising, analytics, tracking, cloud-note storage, or external AI processors.

## Retention, deletion, and consent

Local Clasp data remains on the user's Mac until the user edits or deletes it, subject to copies retained by macOS backups, clipboard managers, screenshots, or other software outside Clasp. Clasp has no account or server-side note record for Paper LLC to delete.

Paper LLC retains voluntarily submitted support information only as long as reasonably necessary to respond, investigate and correct the issue, protect Clasp and its users, maintain appropriate security or abuse records, and satisfy applicable legal obligations. Public GitHub activity can also remain in GitHub's history or systems under GitHub's policies.

A person can withdraw consent for future optional support processing by not sending further information. To request access to or deletion of support information controlled by Paper LLC, or to ask Paper LLC to remove or redact repository content it controls, email [hello@paper.ai](mailto:hello@paper.ai). Include enough information to locate the request, but do not include note content, Vault data, credentials, or recovery keys. Paper LLC will honor the request unless retention is required for security, fraud prevention, dispute resolution, or another legal obligation. Requests concerning information controlled independently by Apple, GitHub, an email provider, macOS, or another app must also follow that provider's process.

## Deletion and security limits

Users control their local notes and exports. Moving a regular or Vault note to Trash is a recoverable soft deletion until it is permanently deleted. Permanent deletion rewrites Clasp's current data without the deleted record, but Clasp cannot promise secure erasure or prevent forensic recovery from APFS or SSD storage, backups, clipboard managers, screenshots, or other software.

Clasp's Vault protects encrypted data at rest. It is not a defense against malware, privileged memory inspection, keystroke or screen capture, or someone controlling an already-unlocked Mac.

## Changes and contact

This page will be updated if Clasp's information practices materially change. The policy must always be checked against the exact shipping build.

For privacy questions, email Paper LLC at [hello@paper.ai](mailto:hello@paper.ai). For product help or private security-reporting directions, visit [Clasp Support](index.html).
