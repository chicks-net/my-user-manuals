# `meta.toml` reference

Each directory holding one or more PDF manuals also contains a `meta.toml`
file that describes those PDFs. This document is the human-friendly reference
for that format. The authoritative sources remain
[`CLAUDE.md`](../CLAUDE.md) (the dev-facing summary) and
[`meta-toml.cue`](meta-toml.cue) (the machine-facing schema used by
`just cue-verify`); this page is a friendly derivative, not a fork.

## Location and top-level keys

A `meta.toml` lives next to the PDFs it describes. Each top-level key is a
**PDF basename** — the PDF filename without the `.pdf` extension — and its
value is a table of metadata about that PDF.

```toml
[my_manual]
original-filename = "my_manual.pdf"
```

For this entry to validate, a file named `my_manual.pdf` must sit in the same
directory as the `meta.toml`. The cross-check is performed by
`just cue-verify-meta` (CUE only validates the TOML structure; the on-disk
match is done by the just recipe).

### Dotted basenames must be quoted

TOML parses unquoted keys containing dots as nested-key separators, so a
basename that contains dots (for example
`Microcom_Deskport_28.8s_14.4s_users_guide`) must be written as a quoted
string so it is treated as a single key:

```toml
["Microcom_Deskport_28.8s_14.4s_users_guide"]
original-filename = "Microcom_Deskport_28.8s_14.4s_users_guide.pdf"
```

## Field reference

### `original-filename`

- **Required?** One of `original-filename` / `source` is required.
- **Type:** string, or array of strings.
- **Constraints:** Each value must end in `.pdf`. A plain string is used for
  a single-scan or downloaded PDF that preserves its source filename. An
  array records a multi-scan merge — one catalog PDF assembled from several
  Brother scanner outputs — in scan order. Absent for derivative PDFs (e.g.
  ImageMagick-processed or hand-cleaned) with no preserved scanner filename;
  such entries must carry a `source` URL instead.

### `source`

- **Required?** One of `original-filename` / `source` is required.
- **Type:** string.
- **Constraints:** Must be an `http://` or `https://` URL where the PDF was
  downloaded from. Optional when `original-filename` is present; both may
  appear together (a downloaded PDF that keeps its source filename).

### `manufacturer-model`

- **Required?** optional.
- **Type:** string.
- **Constraints:** Must be non-empty. A free-form manufacturer/model
  identifier for the device.

### `tags`

- **Required?** optional.
- **Type:** array of strings.
- **Constraints:** Free-form tags. There is no standard taxonomy yet.

### `scan-time`

- **Required?** optional.
- **Type:** string.
- **Constraints:** RFC 3339 timestamp with a timezone offset (e.g.
  `2025-11-12T01:36:46-05:00`). Only present for direct scanner outputs;
  absent for downloaded or derivative PDFs. Always a scalar, even when
  `original-filename` is an array — it records the first scan's start time,
  not one per array element.

### The provenance rule

Every entry must carry **at least one** of `original-filename` or `source`.
Both may be present (a downloaded PDF that keeps its source filename is
common). This "at least one of two optional fields" rule cannot be expressed
by the CUE schema (field-presence disjunctions produce "incomplete value"
errors under concrete evaluation), so it is enforced by a `jq` check inside
`just cue-verify-meta` rather than by `meta-toml.cue`.

### `scan-time` derivation

`scan-time` is recovered from the first Brother scanner filename's
`YYYYMMDDHHMMSS` clock plus the UTC offset derived from the PDF's
`/CreationDate`. The full procedure is documented in
[`brother-ads-4900w-filenames.md`](brother-ads-4900w-filenames.md).

## Comments and future fields

Free-text `#` comments are allowed anywhere in a `meta.toml` and are ignored
by the validator. Use them to leave notes for future contributors:

```toml
# TODO: confirm the manufacturer-model string against the device label.
[my_manual]
original-filename = "my_manual.pdf"
```

The CUE schema opens every entry with `...`, so **additional future fields
are permitted** without breaking validation. If you need a new field, add it
— but consider updating `meta-toml.cue` and this document so the field
becomes part of the documented format rather than an untracked extra.

## Worked examples

### A downloaded PDF

A downloaded PDF that keeps its source filename, with both provenance fields
present. From `Computer/Keyboards/meta.toml`:

```toml
[MOD007B_HE_manual]
original-filename = "MOD007B_HE.pdf"
source = "https://file.akkogear.com/MOD007B_HE.pdf"
```

### A single Brother scan

A direct scanner output with a `scan-time` recovered from the scanner
filename. From `Bathroom/Azang/meta.toml`:

```toml
[Azang_EyeMask_User_Manual]
original-filename = "20260319175312_001.pdf"
scan-time = "2026-03-19T17:53:12-04:00"
```

### A multi-scan merge

A catalog PDF assembled from several Brother scanner outputs, recorded as an
array of the constituent filenames in scan order. Note that `scan-time` is a
scalar — it records the first scan's start time, not one per array element.
From `Computer/Printer/meta.toml`:

```toml
[Epson_FX-650_1050_Users_Manual]
original-filename = [
  "Epson_FX-650_1050_Users_Manual_a_20240827205404_001.pdf",
  "Epson_FX-650_1050_Users_Manual_b_20240827210554_001.pdf",
  "Epson_FX-650_1050_Users_Manual_c_20240827211229_001.pdf",
  "Epson_FX-650_1050_Users_Manual_d_20240827211317_001.pdf",
]
manufacturer-model = "Epson FX-650 / FX-1050"
scan-time = "2024-08-27T20:54:04-04:00"
tags = ["printer", "Epson"]
```

## Validation

Two just recipes validate `meta.toml` files:

- `just cue-verify-meta` — validates every `meta.toml` under the category
  directories against [`meta-toml.cue`](meta-toml.cue), cross-checks that
  each declared `[basename]` has a matching `<basename>.pdf` on disk, and
  enforces the provenance rule (at least one of `original-filename` or
  `source`).
- `just cue-verify` — runs the above plus validates `.repo.toml` against
  [`repo-toml.cue`](repo-toml.cue) and checks that `.repo.toml` flags match
  the actual repository configuration.

Both recipes live in [`.just/cue-verify.just`](../.just/cue-verify.just).

### Continuous integration

Validation runs in CI via
[`.github/workflows/cue-verify.yml`](../.github/workflows/cue-verify.yml).
The workflow is path-filtered: it runs on changes to `.repo.toml`, any
`docs/*.cue`, `.just/cue-verify.just`, the workflow file itself, and any
`**/meta.toml`. A failing run blocks the pull request.

## Source of truth

`CLAUDE.md` and `meta-toml.cue` are the authoritative sources for this
format. If this document and either of those disagree, the authoritative
source wins — and please open an issue or PR to fix this page.
