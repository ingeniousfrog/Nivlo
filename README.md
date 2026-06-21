# Nivlo

Nivlo is a local-first visual workspace for macOS. It indexes images across
your folders, projects, downloads, and external drives without moving,
modifying, or uploading the originals.

## Current status

Phase 1 is under active development. The current vertical slice can:

- let the user explicitly choose a directory;
- recursively discover image files while skipping hidden files and packages;
- identify files using volume and file resource identifiers instead of paths;
- persist security-scoped bookmarks for explicitly authorized folders;
- restore valid folder access across launches and isolate unavailable drives;
- surface up to 500 lightweight image candidates from Spotlight metadata;
- store basic file and pixel metadata in a persistent SQLite index;
- classify assets by likely source such as Desktop, Downloads, Documents,
  external volumes, projects, and other paths;
- generate bounded local thumbnail cache files without altering originals;
- extract TIFF/EXIF camera metadata;
- run best-effort Vision OCR and store OCR text when macOS can read it;
- extract dominant color buckets for color filtering;
- compute streaming SHA-256 and 64-bit perceptual hashes;
- invalidate and rebuild derived metadata when source files change;
- preserve existing index records when a scan is incomplete or loses access;
- reconcile deleted and moved files when a directory is rescanned;
- watch active library roots with FSEvents, coalesce bursts, and rescan only
  affected folders when possible;
- group exact duplicates and perceptually similar images;
- restore indexed assets on launch;
- browse indexed images in a native SwiftUI grid;
- search indexed images by filename, path, OCR text, and keywords;
- browse smart views for screenshots, recent downloads, recently modified
  images, and large files;
- process images into an output directory with output-only conversion,
  compression quality, resizing, batch naming, and overwrite-safe suffixes;
- persist processing/export history for generated derivatives;
- copy paths or Markdown image references, reveal files in Finder, and drag
  file URLs out of the grid.

Remaining Phase 1 work is mostly polish: deeper operation-history UI,
additional batch-action presets, and real-world tuning for external-volume
remount behavior. Spotlight results are discovery candidates only; Nivlo builds
its complete index only after the user authorizes a folder.

## Run locally

Requirements:

- macOS 14 or later
- Xcode 16 or later
- Swift 6

From the repository root:

```bash
swift run Nivlo
```

Run the test suite:

```bash
swift test
```

The local index is stored at:

```text
~/Library/Application Support/Nivlo/index.sqlite
```

Derived thumbnails are stored beside the database under `Thumbnails/`.
Removing this derived data does not remove or alter any original image.
