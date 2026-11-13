# Data governance and privacy

AeroSpatial does not upload recordings by itself. **However, local files can contain highly sensitive aircraft and pilot locations, operating times, and personal notes.** Local storage alone is not encryption and the application does not currently provide at-rest encryption beyond what the host operating system supplies.

- Session logs are JSONL and include raw telemetry when the operator enables recording. Camera-position markers identify the **aircraft**, not a photographed target.
- `Toolkit` stores spatial observations and optional frame-level perception evidence only in opt-in local SQLite files. It has no cloud sync. Frame observations store metadata, not image pixels.
- `.gitignore` excludes ordinary JSONL recordings and SQLite databases. Developers must still review manually staged files and archives before sharing.
- `sanitize INPUT OUTPUT` writes a **new** recording, refusing to overwrite its original or an existing output. It replaces original session IDs, rebases wall-clock time and uptime, drops notes and removes **recognized** coordinate field names. Unknown custom numeric fields may still contain sensitive content; review before public release.
- `digest` checks accidental corruption but does not authenticate data. Raw logs, sanitized outputs, and digest files should be given appropriate file-system access controls.
- Current code neither records microphone audio nor ingests live drone camera video. Adding either capability requires explicit consent, retention limits and data-minimization review.

Example:

```bash
PYTHONPATH=. python3 -m aerospatial_tools sanitize raw.jsonl public.jsonl
PYTHONPATH=. python3 -m aerospatial_tools validate public.jsonl
```

Always inspect `public.jsonl` before publishing. The sanitizer is a conservative convenience layer, not a guarantee of de-identification.
