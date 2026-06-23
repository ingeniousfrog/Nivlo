# Nivlo

[English](README.md) | [简体中文](README-CN.md)

**A local-first visual asset workbench for macOS.**

Nivlo helps you discover, index, browse, search, organize, process, edit, and trace images and videos across your folders, projects, downloads, and external drives — without moving originals or uploading them by default.

Repository: [github.com/ingeniousfrog/Nivlo](https://github.com/ingeniousfrog/Nivlo)

> Screenshots coming soon.
>
> Project status last verified against the repository on June 23, 2026.

---

## Overview

Nivlo is built for people who keep visual assets scattered across Desktop, Downloads, project folders, and removable volumes. Instead of importing everything into a proprietary library, you explicitly authorize the folders you care about. Nivlo builds a rich local index on top of your existing file layout and keeps watching for changes.

Spotlight can surface lightweight discovery candidates, but the full index is built only after you grant folder access. All derived data — thumbnails, hashes, OCR text, and exports — lives under Application Support and never alters your source files.

### How Nivlo differs from Apple Photos

Nivlo is not intended to replace the personal photo library and iCloud experience in Apple Photos. It is aimed at creators and developers who work with visual files that already live across project folders, Downloads, external drives, and other user-managed locations.

| Area | Nivlo | Apple Photos |
|------|-------|--------------|
| Storage model | Indexes authorized folders in place; originals keep their existing paths | Imports or references items through a managed Photos library |
| Primary workflow | Project assets, search, batch processing, derivative exports, and lineage | Personal memories, iPhone capture, albums, sharing, and cross-device sync |
| Cloud model | Local-first; cloud AI is explicitly opt-in | Deep iCloud Photos and Apple ecosystem integration |
| Search and organization | Filename, path, OCR, metadata, color, source, exact duplicates, and perceptual similarity | People and pets, places, dates, media types, albums, Smart Albums, memories, and semantic search |
| Editing direction | File-oriented editing, export presets, annotations, masks, and planned multi-model generative editing | Mature photo adjustments, Live Photo/Portrait/Cinematic workflows, extensions, and Apple Intelligence features |
| Provenance | Explicit processing history and derivative lineage | Non-destructive edits inside the Photos library |

The strongest product position for Nivlo is therefore a **local visual asset workbench**, not a Photos clone: preserve folder ownership, make large mixed asset collections searchable, and connect conventional editing, batch delivery, and AI-generated variants in one traceable workflow.

---

## Highlights

- **Non-destructive by design** — Originals stay in place. Indexing, thumbnails, and exports are derivative data only.
- **Explicit authorization** — You choose which folders to index. No default scan of the entire system.
- **Stable file identity** — Assets are tracked by volume and file resource identifiers, so moved files can be reconciled across rescans.
- **Rich local metadata** — EXIF, Vision OCR, perceptual hashes, dominant colors, and FTS-backed full-text search.
- **Optional cloud AI** — Bring your own API key, stored in the macOS Keychain. No bundled model quota or default cloud analysis.

---

## Features

### Discover & Index

- Add library roots through explicit folder authorization with security-scoped bookmarks.
- Restore valid folder access across launches; isolate unavailable external volumes.
- Recursively scan authorized directories for images and videos, skipping hidden files and packages.
- Classify assets by likely source: Desktop, Downloads, Documents, external volumes, projects, and more.
- Surface up to 500 Spotlight metadata candidates before full indexing.
- Persist file and pixel metadata in a SQLite database with WAL mode.
- Enrich assets with thumbnails, SHA-256 hashes, 64-bit perceptual hashes, EXIF/TIFF metadata, Vision OCR, and dominant color buckets.
- Watch active library roots with FSEvents, coalesce bursts, and rescan only affected folders when possible.
- Invalidate and rebuild derived metadata when source files change; preserve records when access is temporarily lost.

### Browse & Search

- Browse indexed assets in a native SwiftUI grid with masonry layout support.
- Search by filename, path, OCR text, and keywords via SQLite FTS.
- Smart views for screenshots, recent downloads, recently modified images, and large files.
- Filter by time, folder, format, dimensions, file size, color, keywords, OCR text, and source.
- Sort by date, filename, size, dimensions, and folder.
- Built-in English and Chinese UI.

### Organize

- Group exact duplicates by SHA-256 content hash.
- Surface perceptually similar images using connected-component clustering.

### Batch Process & Export

- Write processed outputs to a chosen directory without modifying originals.
- Convert to PNG, JPEG, WebP, or AVIF (when supported by ImageIO on your Mac).
- Apply compression quality, resizing, and batch filename templates with overwrite-safe suffixes.
- Copy file paths or Markdown image references, reveal files in Finder, and drag file URLs from the grid.
- Track processing history and derivative lineage from source to export.

### Image Editor *(Phase 2 — Beta)*

- Open indexed images in a native editor canvas.
- Crop, rotate, and flip; adjust exposure, contrast, saturation, and warmth.
- Add editable text, rectangle, and arrow annotations; paint and erase masks.
- Preview the composed result and export optimized derivatives through Picx.
- Track the exported edit in the asset lineage.

### Video Editor *(Phase 2 — Beta)*

- Preview, trim, crop, scale, rotate, and change frame rate.
- Export MP4, MOV, or WebM derivatives through FFmpeg.
- Probe media with FFprobe; optionally export audio only.

### AI Generation *(Integration foundation, not production-ready)*

- Pluggable `GenerationAdapter` interface for text-to-image, image-to-image, inpainting, outpainting, background removal, super-resolution, and style variants.
- The settings UI, Keychain storage, generation panel, result export, and lineage hooks are present.
- The current direct OpenAI adapter is a prototype and does not yet represent the intended production integration.
- **Next provider target:** the [Synclip.ai API Platform](https://synclip.ai/dev), used as one provider surface for multiple image-generation and image-editing models.
- Image editing comes first; video-generation models are intentionally deferred until the image workflow, async jobs, error handling, and cost visibility are reliable.
- API keys are stored in the macOS Keychain, not in the repository or index database.

---

## Privacy & Local-First

Nivlo is designed around a few non-negotiable principles:

- **No proprietary library migration** — Your files stay where you put them.
- **No forced cloud sync, accounts, or multi-user collaboration.**
- **No default scan of all system directories** — Access is always explicit.
- **No bundled paid AI quota** — Cloud generation is opt-in with your own key.
- **Safe to delete derived data** — Removing `~/Library/Application Support/Nivlo/` clears the index, thumbnails, and tools cache without touching your original images or videos.

---

## Architecture

Nivlo is a Swift Package with a modular layout:

```mermaid
flowchart TB
  subgraph app [NivloApp]
    UI[SwiftUI Views]
  end
  subgraph domain [NivloDomain]
    Models[Asset Query Lineage]
  end
  subgraph indexing [NivloIndexing]
    Scan[DirectoryScanner]
    Watch[FileEventWatcher]
    Access[LibraryRootAccess]
  end
  subgraph imaging [NivloImaging]
    Enrich[ImageEnricher]
    Batch[ImageBatchProcessor]
    FFmpeg[FFmpegProcessor]
    Picx[PicxProcessor]
  end
  subgraph persistence [NivloPersistence]
    SQLite[SQLiteAssetRepository]
  end
  UI --> domain
  UI --> indexing
  UI --> imaging
  indexing --> domain
  imaging --> domain
  indexing --> persistence
  imaging --> persistence
```

| Module | Role |
|--------|------|
| `NivloApp` | SwiftUI executable and application shell |
| `NivloDomain` | Domain models, queries, edit sessions, generation interfaces |
| `NivloIndexing` | Scanning, Spotlight candidates, FSEvents, bookmark authorization |
| `NivloImaging` | Enrichment, batch processing, similarity analysis, FFmpeg/Picx |
| `NivloPersistence` | SQLite repositories for assets, enrichment, and processing history |

---

## Getting Started

### Requirements

- macOS 14 or later
- Xcode 16 or later
- Swift 6

### Run from source

From the repository root:

```bash
swift run Nivlo
```

### First launch

1. **Authorize folders** — Choose the directories you want Nivlo to index.
2. **Wait for indexing** — Nivlo scans authorized roots, generates thumbnails, and enriches metadata in the background.
3. **Browse and work** — Search, filter, batch-export, or open assets in the image/video editors.

On first launch, Nivlo also bootstraps external tools (FFmpeg, FFprobe, and Picx) into Application Support. Video editing and Picx-based image export depend on this step completing successfully.

---

## Development

### Run tests

```bash
swift test
```

Tests use Swift Testing (`@Test`) across domain, indexing, imaging, and persistence modules.

### External tools

Managed by `ToolBootstrapper` and installed to:

```text
~/Library/Application Support/Nivlo/tools/
```

The manifest tracks FFmpeg, FFprobe, Picx, and a Python virtual environment. Check tool status in the library sidebar if video export or Picx optimization fails.

---

## Data & Storage

| Path | Contents |
|------|----------|
| `~/Library/Application Support/Nivlo/index.sqlite` | Main asset index and FTS tables |
| `~/Library/Application Support/Nivlo/Thumbnails/` | Local thumbnail cache |
| `~/Library/Application Support/Nivlo/tools/` | Bootstrapped FFmpeg, FFprobe, Picx, and support files |

All paths above are derivative. Deleting them does not remove or alter any original file on disk.

---

## Roadmap

The phases below describe user-visible outcomes, not just the presence of interfaces or UI shells.

### Phase 0 — Foundation *(complete)*

Native SwiftUI application shell, modular Swift Package structure, SQLite persistence, security-scoped folder access, and automated domain/indexing/imaging/persistence tests.

### Phase 1 — Local asset library *(core complete)*

Local visual asset workbench: authorized indexing, rich metadata, incremental maintenance, browse/search/filter, duplicate detection, batch processing, export history, and derivative lineage.

Remaining work is primarily hardening: large-library performance, clearer index/tool health, recovery flows, and real-world usability validation.

### Phase 2 — Native editing workbench *(beta, in progress)*

Already available:

- Non-destructive image geometry, basic global adjustments, annotations, masks, preview, and export.
- Video preview, trim, transform, export, and audio extraction.
- Processing history and a basic lineage view.

Next editing milestone:

- RGB and luminance histograms with interactive black point, white point, and gamma controls.
- Levels and curves, plus HSL/HSV color-range editing rather than only whole-image saturation.
- White balance/tint, highlights/shadows, clarity/definition, sharpen, noise reduction, vignette, and reusable presets.
- Undo/redo history, before/after comparison, zoom/pan, and saved edit sessions.
- Better layer controls and mask-assisted local adjustments.

### Phase 3 — Synclip.ai image intelligence *(next)*

- Replace the direct provider prototype with a tested Synclip.ai adapter.
- Fetch or configure an explicit model catalog and route capabilities by model.
- Support image-to-image, inpainting, outpainting, background removal, super-resolution, and style variants before expanding scope.
- Treat generation as asynchronous jobs with progress, cancellation, retry, timeout, and recoverable failure states.
- Show model, estimated cost/credits, output parameters, prompt, source image, and mask before submission.
- Store downloaded results locally and attach complete provenance to lineage records.
- Keep uploads explicit and disclose when an operation leaves the Mac.

### Phase 4 — Semantic organization, automation, and generative video *(later)*

- Semantic and image-to-image search.
- Automatic clustering and project asset association.
- Configurable local automation workflows.
- Synclip.ai video generation and image-to-video only after the image API workflow is stable.
- Queue/history UI for long-running generation and reusable multi-step workflows.

---

## License

Copyright © [Ingenious Frog](https://github.com/ingeniousfrog)

Licensed under the [Apache License, Version 2.0](LICENSE).
