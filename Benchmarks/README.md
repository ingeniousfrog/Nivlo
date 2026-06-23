# Nivlo performance benchmarks

Run the synthetic 10k/50k/100k asset benchmark from the repository root:

```bash
swift run NivloBenchmark
```

The harness measures:

- SQLite-backed library startup after transactional fixture seeding.
- Masonry layout work used by scrolling.
- Bounded concurrent enrichment scheduling.
- A complete synthetic directory rescan.

Baseline captured on June 23, 2026:

| Assets | Startup | Layout | Enrichment | Rescan |
|-------:|--------:|-------:|-----------:|-------:|
| 10,000 | 12.15 ms | 1.88 ms | 44.83 ms | 431.40 ms |
| 50,000 | 63.89 ms | 11.96 ms | 232.24 ms | 2,085.12 ms |
| 100,000 | 117.02 ms | 21.45 ms | 469.97 ms | 4,203.56 ms |

Use these numbers as a local regression baseline, not as universal hardware
targets.

For a real editor UI smoke workflow:

```bash
swift run Nivlo --ui-smoke
swift run Nivlo --ui-smoke --ui-smoke-video
```

Smoke mode creates real local PNG and H.264 MOV fixtures, then opens the image
or video editor without touching the user's asset library.
