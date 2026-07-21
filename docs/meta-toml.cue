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
[base=string]: {
	// Original filename from the Brother scanner or download source.
	// Always ends in .pdf so it is unambiguously a PDF reference.
	"original-filename": string & =~"\\.pdf$"

	// Optional URL where the PDF was downloaded from.
	source?: string & =~"^https?://"

	// Optional manufacturer/model identifier for the device.
	"manufacturer-model"?: string & !=""

	// Optional free-form tags. No standard tagging system yet.
	tags?: [...string]

	// Permit future fields without breaking validation.
	...
}
