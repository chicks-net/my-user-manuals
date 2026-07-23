# Brother ADS-4900W filenames and PDF metadata

This note documents what the Brother ADS-4900W scanner records about a scan,
both in the filename it writes and in the PDF metadata it embeds. It exists so
we don't have to rediscover the quirks each time we look at the archive.

## Filename format

The default scan filename follows:

```text
YYYYMMDDHHMMSS_NNN.pdf
```

| Component  | Meaning                              | Example                 |
| ---------- | ------------------------------------ | ----------------------- |
| `YYYYMMDD` | Scan date, local wall-clock          | `20250428` = 2025-04-28 |
| `HHMMSS`   | Scan time, 24-hr local wall-clock    | `214718` = 21:47:18     |
| `_NNN`     | 3-digit sequence per job, from `001` | `001`, `002`, ...       |

The scanner also accepts an optional **user-supplied prefix**, which is
prepended verbatim and followed by the same timestamp and sequence:

```text
<prefix>_YYYYMMDDHHMMSS_NNN.pdf
```

Examples from this archive:

- `costco_polygroupstore_1487014_christmas_tree_20260207183717_001.pdf`
- `cuisinart_toa-95_20260101153922_001.pdf`
- `dt770pro_product_information_20260101125232_001.pdf`

### What the filename does **not** encode

- Timezone or UTC offset
- Page count, duplex, color/B&W, DPI
- Scanner profile, operator, or device serial
- Scan-to destination (PC, USB, network, OCR, ...)

So the filename timestamp is local, offset-naive, and ambiguous across DST
transitions or travel. Treat it as the **scan-start clock** only.

## PDF metadata

Every Brother-generated PDF in this archive carries two date fields in the Info
dictionary:

| PDF field       | exiftool tag     | Meaning                         |
| --------------- | ---------------- | ------------------------------- |
| `/CreationDate` | `PDF:CreateDate` | When the PDF was written        |
| `/ModDate`      | `PDF:ModifyDate` | Same as `/CreationDate` always  |

Only four metadata keys are populated total: `Creator`, `Producer`,
`CreateDate`, `ModifyDate`. Nothing else (no `Title`, `Author`, `Subject`,
`Keywords`, device serial, profile, etc.).

### Two producers, two behaviors

There are two distinct scan paths in active use in this archive, and they
behave differently. You can tell them apart by `Creator` / `Producer`.

#### Native path -- scan-to-PC

```text
Creator:  Brother Scanner System : ADS-4900W
Producer: Brother Scanner System Image Conversion
```

- `/CreationDate` uses a proper local offset, e.g.
  `2026:01:01 15:39:32-05:00`.
- Lands ~10 seconds after the filename timestamp. This gap is scan-start
  (filename) to PDF-finalization (`/CreationDate`).
- The offset is correct across DST changes (winter scans carry `-05:00`,
  summer scans would carry `-04:00`).
- **Trustworthy.** This is the cleanest timestamp signal in the archive.

Observed samples:

| Filename (local)       | PDF `/CreationDate`         | Delta  |
| ---------------------- | --------------------------- | ------ |
| `20260101153922` (EST) | `2026:01:01 15:39:32-05:00` | +10 s  |
| `20260101125232` (EST) | `2026:01:01 12:52:42-05:00` | +10 s  |

#### OCR path -- OmniPage

```text
Creator:  OmniPage CSDK 21
Producer: ops3
```

- `/CreationDate` is stored as UTC with a `Z` suffix, e.g.
  `2025:04:29 02:47:42Z`.
- **Beware a DST bug:** during EDT months the OmniPage path adds an extra,
  spurious hour to the timestamp. During EST months it does not.

Observed samples (filename converted to UTC for comparison):

| Filename (local)       | PDF `/CreationDate` (UTC) | Delta vs filename  |
| ---------------------- | ------------------------- | ------------------ |
| `20250428214718` (EDT) | `2025:04:29 02:47:42Z`    | +1 h 00 m 24 s     |
| `20250428222848` (EDT) | `2025:04:29 03:29:05Z`    | +1 h 00 m 17 s     |
| `20250429083440` (EDT) | `2025:04:29 13:34:58Z`    | +1 h 00 m 18 s     |
| `20250429143855` (EDT) | `2025:04:29 19:39:14Z`    | +1 h 00 m 19 s     |
| `20260319175312` (EDT) | `2026:03:19 22:53:29Z`    | +1 h 00 m 17 s     |
| `20260207183717` (EST) | `2026:02:07 23:38:14Z`    | +0 h 00 m 57 s     |

The five EDT scans all land almost exactly one hour after the filename clock
(within ±24 s). The single EST scan (Polygroup, Feb 7) lands only 57 s after,
matching the native path's ~1 min latency.

Interpretation: OmniPage CSDK 21 appears to apply a fixed 1-hour "summer time"
adjustment during DST even though the PDF timestamp is already being emitted in
UTC -- a double correction. The result is that `/CreationDate` is wrong by one
hour for any scan taken between the second Sunday of March and the first Sunday
of November.

### Recovery formulas

Given a Brother-produced PDF, to recover the true scan-start time:

1. Read `Creator`.
2. If it is `Brother Scanner System : ADS-4900W`, trust `/CreationDate`
   as-is (subtract ~10 s if you want scan-start rather than finalize time).
3. If it is `OmniPage CSDK 21`:
   - Parse `/CreationDate` as UTC.
   - If the scan was taken during local DST (roughly March-November),
     subtract one hour to undo the bug.
   - Subtract ~1 min if you want scan-start rather than finalize time.
4. The filename's `YYYYMMDDHHMMSS` is always the authoritative scan-start in
   local time; use the PDF `/CreationDate` only to recover the timezone
   offset. When the two disagree by ~1 h, the filename is correct and the
   OmniPage metadata is wrong.

## Why this matters for the archive

- `meta.toml`'s `original-filename` field preserves the scanner's filename, so
  the scan-start timestamp is always recoverable even after we rename the PDF
  for cataloging.
- The filename is the more reliable chronological key. Do **not** blindly sort
  or dedupe by `/CreationDate` across the two scan paths during DST -- you'll
  get OmniPage scans misordered by an hour.
- If consistent metadata ever becomes a priority, routing everything through
  the native scan-to-PC path would give clean, correctly-offset
  `/CreationDate` values, at the cost of whatever OCR benefit the OmniPage
  path provides.

## How to reproduce

```sh
# List all date fields a Brother PDF carries
exiftool -time:all -G -s path/to/file.pdf

# Show all populated PDF metadata keys
exiftool -a -G1 -s -PDF:all path/to/file.pdf

# Quick summary via poppler
pdfinfo path/to/file.pdf
```

All three are available on macOS via Homebrew: `brew install exiftool poppler
qpdf`.
