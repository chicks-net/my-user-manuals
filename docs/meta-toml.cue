// CUE schema for meta.toml validation
// Validates the structure and types of per-directory manual metadata files.
//
// Each meta.toml lives alongside one or more PDF manuals and describes them.
// Top-level keys are PDF basenames (without the .pdf extension); each key
// holds a struct of metadata about that PDF. See CLAUDE.md for the format.

package meta

// Every top-level key is a PDF basename (no extension) mapping to its metadata.
// The basename must correspond to a <basename>.pdf file sitting next to the
// meta.toml (the just recipe cross-checks this; CUE only validates the TOML).
//
// At least one provenance field is required: every entry must carry either an
// `original-filename` (for scanner outputs or downloads that preserve the
// source filename) or a `source` URL (for downloads/derivatives with no
// preserved filename). Both may be present. CUE cannot express "at least one
// of two optional fields" as a disjunction (field-presence disjunctions
// produce "incomplete value" errors under concrete evaluation), so this
// constraint is enforced by a jq check in the `cue-verify-meta` just recipe
// rather than by the schema itself. The schema only types the fields.
[base=string]: {
	// Original filename from the Brother scanner or download source.
	// Always ends in .pdf so it is unambiguously a PDF reference.
	//
	// For multi-scan merges (one catalog PDF assembled from several Brother
	// scanner outputs), an array of the constituent scanner filenames is
	// recorded in scan order. Single-scan or downloaded PDFs use a plain
	// string. Optional: some PDFs are derivatives (e.g. ImageMagick-processed
	// or hand-cleaned) with no preserved scanner filename; such entries
	// must carry a `source` URL instead.
	"original-filename"?: (string & =~"\\.pdf$") | [...string & =~"\\.pdf$"]

	// Optional URL where the PDF was downloaded from.
	source?: string & =~"^https?://"

	// Common optional fields shared by all entries.
	"manufacturer-model"?: string & !=""
	tags?: [...string]

	// Optional scan-start timestamp in RFC 3339 form with a timezone offset
	// (e.g. `2025-11-12T01:36:46-05:00`). Recovered from the first Brother
	// scanner filename's YYYYMMDDHHMMSS clock plus the offset derived from
	// the PDF's /CreationDate per docs/brother-ads-4900w-filenames.md. Only
	// present for direct scanner outputs; absent for downloaded or
	// derivative PDFs. Always a scalar even when `original-filename` is an
	// array -- it records the first scan's start time.
	"scan-time"?: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$"

	// Permit future fields without breaking validation.
	...
}
