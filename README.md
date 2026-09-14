# Aidoku
This is a personal fork of Aidoku with additional features/ changes.

## Fork changes

### Added

- Compact list layout for the library
- Automatic Google Drive uploads for scheduled backups
- A smaller custom backup format, typically around one-quarter the size of upstream backups
    - Backups created by this fork are incompatible with upstream Aidoku
- Quick rating lookups from Trackers
- Persistent metadata and chapter caching for viewed and history titles outside the library
- Cancelable library updates that can work in the background
  - This may not work if your sideloading method installs under a different app ID.
- Hardened session crash logging

### Performance and reliability

- Faster library and history operations
- Lower reader memory usage, bounded webtoon preloading, and disk-backed temporary page data
- More reliable reader position restoration during text saves and webtoon layout changes
- Safer CloudKit history processing and recovery after interrupted library updates

### Exclusions

Some changes from upstream have been excluded from my fork because I use other apps for these features, and don't want them to clog up build time.

- OCR dictionary lookup
- EPUB importing

## Installation

You have to sideload it. You can either grab builds from [nightly](https://github.com/Amqx/Aidoku/releases/tag/nightly) or use an AltStore manifest-compatible app and add the [repo](https://raw.githubusercontent.com/Amqx/Aidoku/altstore/apps.json) link.

The fork uses its own bundle and iCloud identifiers, separate from upstream Aidoku.

## Stability
I highly recommend using [upstream](https://github.com/Aidoku/Aidoku) if you want a more stable experience. This fork may contain changes that are less thoroughly tested.
