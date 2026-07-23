# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Repository Purpose

This is a personal user manual archive repository where scanned PDF manuals are
stored using git-lfs. The goal is to organize physical user manuals digitally
to eliminate paper clutter. Each manual is stored as a PDF in categorized
directories (Computer, Office, Bathroom, Garage, Sewing, etc.).

## Key Technologies

- **git-lfs**: Required for handling PDF files. PDFs are stored via git-lfs
  (configured in .gitattributes)
- **just**: Command runner for repository automation tasks
- **markdownlint-cli2**: All markdown files must comply with markdownlint
  standards

## Repository Structure

- Top-level directories represent categories (Computer/, Office/, Bathroom/, etc.)
- Each subdirectory typically contains:
  - One or more PDF files (user manuals)
  - A `meta.toml` file with metadata about the PDFs
  - An optional `README.md` describing the contents

### meta.toml Format

TOML files with metadata about PDF manuals. Each meta.toml lives next to the
PDFs it describes and is validated against `docs/meta-toml.cue` by
`just cue-verify` (see [CUE Validation](#cue-validation)).

- Top-level keys are PDF basenames (without `.pdf` extension); a matching
  `<basename>.pdf` must exist in the same directory. Basenames containing
  dots (e.g. `Microcom_Deskport_28.8s_14.4s_users_guide`) must be quoted
  as TOML strings so the dots are not parsed as nested-key separators
- Each entry contains at least one of these two provenance fields
  (both may be present):
  - `original-filename`: The filename from the Brother scanner or download
    (optional when `source` is present, must end in `.pdf`). Either a plain
    string for a single source file, or an array of strings for a multi-scan
    merge (one catalog PDF assembled from several Brother scanner outputs,
    in scan order). Absent for derivative PDFs (e.g. ImageMagick-processed
    or hand-cleaned) with no preserved scanner filename; such entries must
    carry a `source` URL instead
  - `source`: URL where the PDF was downloaded from. Required when
    `original-filename` is absent; optional otherwise
  - `manufacturer-model`: Optional manufacturer/model identifier for the device
  - `tags`: Optional array of tags (no standard tagging system yet)
  - `scan-time`: Optional RFC 3339 scan-start timestamp with a timezone
    offset (e.g. `2025-11-12T01:36:46-05:00`), recovered from the first
    Brother scanner filename's `YYYYMMDDHHMMSS` clock plus the offset
    derived from the PDF's `/CreationDate` per
    `docs/brother-ads-4900w-filenames.md`. Only present for direct
    scanner outputs; absent for downloaded or derivative PDFs. Always a
    scalar even when `original-filename` is an array

The "at least one of `original-filename` or `source`" rule is enforced
by a jq check in the `just cue-verify-meta` recipe (CUE cannot express
field-presence disjunctions without producing "incomplete value"
errors, so the schema only types the fields). The CUE schema permits
additional future fields. Free-text `#` comments are allowed and
ignored by the validator.

Example (single-scan download):

```toml
[MOD007B_HE_manual]
original-filename = "MOD007B_HE.pdf"
source = "https://file.akkogear.com/MOD007B_HE.pdf"
```

Example (multi-scan merge with scan-time):

```toml
[Microcom_QX_4232bis]
original-filename = [
  "Microcom_QX_4232bis_a_20260721213625_001.pdf",
  "Microcom_QX_4232bis_b_20260721214039_001.pdf",
  "Microcom_QX_4232bis_c_20260721214359_001.pdf",
]
manufacturer-model = "Microcom QX 4232bis"
scan-time = "2026-07-21T21:36:25-04:00"
tags = ["modem", "Microcom"]
```

## Common Commands

### Repository Management

- `just list` - List all available just recipes
- `just compliance_check` - Run the custom compliance checker (verifies
  README, LICENSE, GitHub files, etc.)
- `just shellcheck` - Run shellcheck on all bash scripts in just recipes

### CUE Validation

- `just cue-verify` - Validate `.repo.toml` against `docs/repo-toml.cue` and
  every `meta.toml` against `docs/meta-toml.cue`, then cross-check that each
  declared PDF basename exists on disk. Runs in CI via
  `.github/workflows/cue-verify.yml` (path-filtered to TOML/CUE/justfile
  changes).
- `just cue-verify-meta` - Run only the `meta.toml` validation and PDF
  cross-check stage.

### Git Workflow (via just)

- `just branch <branchname>` - Create a new branch with format
  `$USER/<date>-<branchname>`
- `just pr` - Create a pull request with automatic title/body from commits
- `just pr_checks` - Watch GitHub Actions and check for Copilot/Claude
  suggestions
- `just pr_update` - Update the Done section of PR description with current
  commits
- `just pr_verify` - Add or append to Verify section from stdin
- `just again` - Push changes, update PR description, and watch GHAs (for
  iterative development)
- `just prweb` - Open the PR in a web browser
- `just merge` - Merge the PR, delete branch, and return to main
- `just sync` - Return to main branch and pull latest changes
- `just release <version>` - Create a new release with generated notes
- `just release_age` - Check how long ago the last release was

The workflow uses `main` as the release branch.

## Important Constraints

- All PDF files must be tracked with git-lfs
- Markdown files must pass markdownlint-cli2 validation
- The repository uses a manual categorization system (no formal tagging
  standard exists yet)
- When adding new manuals, maintain the directory structure pattern and
  include meta.toml files

## GitHub Integration

- Claude Code workflow configured at `.github/workflows/claude.yml` (responds
  to @claude mentions)
- Pull requests auto-populate descriptions from commit messages
- PR checks include watching GHA runs and checking for Copilot/Claude code
  review comments
