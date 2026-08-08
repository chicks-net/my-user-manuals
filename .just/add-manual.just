# Download a manual PDF from a URL into a category directory and record its
# provenance in that directory's meta.toml.
#
# Usage:
#   just add-manual <url> <dir> [basename]
#
# Arguments:
#   url      Source URL (http:// or https://). Required.
#   dir      Target category directory, absolute or repo-relative (e.g.
#            "Computer/Modems"). Created if missing. Required.
#   basename Optional meta.toml top-level key AND local PDF filename stem
#            (the on-disk file becomes <basename>.pdf). Defaults to the
#            URL's last path segment with any trailing .pdf/.PDF stripped.
#
# Behavior:
#   - Downloads <url> to <dir>/<basename>.pdf via curl.
#   - Appends (or creates) <dir>/meta.toml with a minimal entry:
#       [<basename>]
#       original-filename = "<url's filename, .pdf appended if missing>"
#       source = "<url>"
#   - git add's the new PDF (tracked via git-lfs per .gitattributes) and the
#     meta.toml. Does not commit.
#   - Runs `just cue-verify-meta` at the end; on failure the files are left
#     in place (and staged) for manual inspection.
#
# Collisions: errors out if the target PDF already exists, or if meta.toml
# already contains an entry for <basename>. Edit meta.toml by hand or pick a
# different basename.
#
# Optional fields like manufacturer-model, tags, and scan-time are intentionally
# not written -- those are human-added later (matching the shape of existing
# downloaded entries in Cuisinart/HamptonBay meta.toml files).
[group('Manuals')]
add-manual-url url dir basename='':
    #!/usr/bin/env bash
    set -euo pipefail

    # --- argument binding ---------------------------------------------------
    # just substitutes the url/dir/basename placeholders at recipe-expand
    # time; bind them to shell variables first so shellcheck sees real
    # variables rather than the literal placeholder strings (which trip
    # SC2157 because they look like non-empty literals to shellcheck).
    URL="{{url}}"
    DIR="{{dir}}"
    BASENAME="{{basename}}"

    if [[ -z "$URL" ]]; then
        echo "{{RED}}Error: url is required.{{NORMAL}}" >&2
        echo "Usage: just add-manual <url> <dir> [basename]" >&2
        exit 1
    fi
    if [[ -z "$DIR" ]]; then
        echo "{{RED}}Error: dir is required.{{NORMAL}}" >&2
        echo "Usage: just add-manual <url> <dir> [basename]" >&2
        exit 1
    fi

    # URL must be http(s) -- matches the CUE schema's source regex.
    if [[ ! "$URL" =~ ^https?:// ]]; then
        echo "{{RED}}Error: url must start with http:// or https:// (got: $URL){{NORMAL}}" >&2
        exit 1
    fi

    # --- derive original-filename (URL's last path segment) -----------------
    # Strip any trailing slash, then take everything after the final '/'.
    URL_PATH="${URL%/}"
    URL_TAIL="${URL_PATH##*/}"
    if [[ -z "$URL_TAIL" ]]; then
        echo "{{RED}}Error: could not derive a filename from the URL (got: $URL){{NORMAL}}" >&2
        exit 1
    fi

    # If the URL has a query string, strip it from the tail (the Cuisinart
    # "P-TOA-95" entry is a clean stem; URLs with ?query=... are common for
    # CDN downloads and would otherwise pollute the local filename).
    URL_TAIL="${URL_TAIL%%\?*}"

    # original-filename must end in .pdf per docs/meta-toml.cue. If the URL's
    # tail already ends in .pdf or .PDF (case-insensitive), keep it; otherwise
    # append .pdf so the CUE schema's =~"\\.pdf$" check passes.
    # Use tr rather than ${var,,} so this works under bash 3.2 (macOS /bin/bash).
    ORIG_FILENAME="$URL_TAIL"
    LOWER_TAIL="$(printf '%s' "$ORIG_FILENAME" | tr '[:upper:]' '[:lower:]')"
    if [[ "$LOWER_TAIL" != *.pdf ]]; then
        ORIG_FILENAME="${ORIG_FILENAME}.pdf"
    fi

    # --- derive basename (meta.toml key + local pdf stem) --------------------
    if [[ -z "$BASENAME" ]]; then
        # Default: original-filename with its .pdf/.PDF extension stripped.
        BASENAME="${ORIG_FILENAME%.*}"
    fi

    # A basename containing dots would be parsed by TOML as nested keys, so
    # the meta.toml key must be quoted. This also means our collision scan
    # below must check both the bare and quoted forms.
    if [[ "$BASENAME" == *.* ]]; then
        KEY="\"$BASENAME\""
    else
        KEY="$BASENAME"
    fi

    PDF_PATH="$DIR/$BASENAME.pdf"
    META_PATH="$DIR/meta.toml"

    # --- collision checks ---------------------------------------------------
    if [[ -e "$PDF_PATH" ]]; then
        echo "{{RED}}Error: PDF already exists at $PDF_PATH{{NORMAL}}" >&2
        echo "Pick a different basename, or remove the existing file first." >&2
        exit 1
    fi

    if [[ -f "$META_PATH" ]]; then
        # Look for an existing top-level key line: either "[basename]" (bare)
        # or "[\"basename\"]" (quoted, used when basename contains dots).
        # Use fixed-string whole-line grep so basename characters like dots,
        # brackets, and backslashes are matched literally rather than as
        # regexes (avoids SC2016-prone sed-based escaping).
        BARE_KEY_LINE="[$BASENAME]"
        QUOTED_KEY_LINE="[\"$BASENAME\"]"
        if grep -Fxq "$BARE_KEY_LINE" "$META_PATH" \
           || grep -Fxq "$QUOTED_KEY_LINE" "$META_PATH"; then
            echo "{{RED}}Error: meta.toml already has an entry for [$BASENAME]{{NORMAL}}" >&2
            echo "Edit $META_PATH by hand or pick a different basename." >&2
            exit 1
        fi
    fi

    # --- download -----------------------------------------------------------
    mkdir -p "$DIR"

    echo "{{BLUE}}Downloading $URL -> $PDF_PATH{{NORMAL}}"
    if ! curl -fsSL "$URL" -o "$PDF_PATH"; then
        echo "{{RED}}Error: curl download failed for $URL{{NORMAL}}" >&2
        rm -f "$PDF_PATH"
        exit 1
    fi

    # Sanity check: non-empty file whose first bytes look like a PDF.
    if [[ ! -s "$PDF_PATH" ]]; then
        echo "{{RED}}Error: downloaded file is empty: $PDF_PATH{{NORMAL}}" >&2
        rm -f "$PDF_PATH"
        exit 1
    fi
    HEADER="$(head -c 4 "$PDF_PATH" 2>/dev/null || true)"
    if [[ "$HEADER" != "%PDF" ]]; then
        echo "{{RED}}Error: downloaded file does not start with %PDF (got: $(printf '%q' "$HEADER")){{NORMAL}}" >&2
        echo "Leaving the file in place for inspection: $PDF_PATH" >&2
        exit 1
    fi

    # --- write / append meta.toml -------------------------------------------
    # TOML-escape the original-filename and source values. Backslash first,
    # then double-quote, per the TOML spec.
    ORIG_ESCAPED="${ORIG_FILENAME//\\/\\\\}"
    ORIG_ESCAPED="${ORIG_ESCAPED//\"/\\\"}"
    SRC_ESCAPED="${URL//\\/\\\\}"
    SRC_ESCAPED="${SRC_ESCAPED//\"/\\\"}"

    BLOCK="$(printf '[%s]\noriginal-filename = "%s"\nsource = "%s"\n' \
        "$KEY" "$ORIG_ESCAPED" "$SRC_ESCAPED")"

    if [[ ! -e "$META_PATH" ]]; then
        printf '%s\n' "$BLOCK" > "$META_PATH"
    else
        # Ensure exactly one blank line separates the existing content from
        # the new entry, mirroring the visual style of the existing files.
        printf '\n%s\n' "$BLOCK" >> "$META_PATH"
    fi

    echo "{{GREEN}}Wrote entry for [$BASENAME] in $META_PATH{{NORMAL}}"

    # --- stage files (git-lfs handles the PDF per .gitattributes) -----------
    git add "$PDF_PATH" "$META_PATH"
    echo "{{GREEN}}Staged $PDF_PATH and $META_PATH (not committed).{{NORMAL}}"

    # --- validate -----------------------------------------------------------
    # Run cue-verify-meta last so a bad meta.toml (e.g. from manual edits
    # elsewhere in the same file) surfaces here. We deliberately do NOT
    # auto-revert on failure: the user may want to inspect and fix by hand,
    # and the files are already staged for review.
    echo "{{BLUE}}Validating meta.toml files...{{NORMAL}}"
    if ! just cue-verify-meta; then
        echo "{{RED}}Validation failed. The new files are staged for inspection:{{NORMAL}}" >&2
        echo "{{RED}}  $PDF_PATH{{NORMAL}}" >&2
        echo "{{RED}}  $META_PATH{{NORMAL}}" >&2
        echo "{{RED}}Fix meta.toml by hand, then re-run 'just cue-verify-meta'.{{NORMAL}}" >&2
        exit 1
    fi

    echo "{{GREEN}}Done. Added manual [$BASENAME] to $DIR.{{NORMAL}}"

# Process a zip file of scanned PDFs into a category directory and record its
# provenance in that directory's meta.toml.
#
# Usage:
#   just add-manual-zip <zip> <dir> [basename]
#
# Arguments:
#   zip      Path to a local .zip file containing one or more scanned PDFs.
#            Required. The zip's own name is ignored -- the basename is
#            derived from the PDF filenames inside the zip.
#   dir      Target category directory, absolute or repo-relative (e.g.
#            "Computer/Modems"). Created if missing. Required.
#   basename Optional meta.toml top-level key AND local PDF filename stem
#            (the on-disk file becomes <basename>.pdf). Defaults to the
#            longest common stem of the PDF filenames inside the zip, with
#            any trailing Brother scanner suffix (_YYYYMMDDHHMMSS_NNN)
#            stripped.
#
# Behavior:
#   - Extracts the zip to a temp directory and collects every *.pdf entry
#     (case-insensitive), sorted alphabetically for deterministic merge
#     order. Non-PDF files are ignored.
#   - Derives the basename from the longest common prefix of the PDF stems
#     (filename with directory and .pdf stripped), then trims trailing
#     _-. <space> characters. For a single-PDF zip, the scanner suffix is
#     also stripped so e.g. "Foo_20251117022348_001.pdf" yields basename
#     "Foo".
#   - Merges all PDFs into <dir>/<basename>.pdf via `pdfunite` (poppler).
#     A single-PDF zip is copied directly (no merge). Both poppler's
#     pdfunite and exiftool must be on PATH.
#   - Derives scan-time from the first (alphabetically sorted) PDF using
#     the rules in docs/brother-ads-4900w-filenames.md:
#       * The filename's YYYYMMDDHHMMSS clock supplies scan-start.
#       * exiftool reads the PDF's /CreationDate and Creator.
#       * Native path (Creator == "Brother Scanner System : ADS-4900W"):
#         the offset is embedded in /CreationDate (e.g. -05:00).
#       * OmniPage path (Creator == "OmniPage CSDK 21"): /CreationDate is
#         UTC with a Z suffix; the well-known DST double-correction bug
#         is undone by subtracting one hour when the filename month is
#         3-10. The timezone offset is computed as the rounded
#         difference between the filename clock and the adjusted
#         CreationDate.
#       * If the filename does not match the Brother scanner pattern, or
#         metadata is missing, scan-time is omitted (the entry still
#         passes cue-verify-meta because original-filename is present).
#   - Appends (or creates) <dir>/meta.toml with:
#       [<basename>]
#       original-filename = "<single name>" | [ "<name1>", "<name2>", ... ]
#       scan-time = "<RFC 3339 with offset>"   # only if derivable
#   - git add's the merged PDF (tracked via git-lfs per .gitattributes) and
#     the meta.toml. Does not commit.
#   - Runs `just cue-verify-meta` at the end; on failure the files are left
#     in place (and staged) for manual inspection.
#
# Collisions: errors out if the target PDF already exists, or if meta.toml
# already contains an entry for <basename>. Edit meta.toml by hand or pick a
# different basename.
#
# Optional fields like manufacturer-model and tags are intentionally not
# written -- those are human-added later (matching the shape of existing
# scanner-derived entries in Computer/Modems meta.toml).
[group('Manuals')]
add-manual-zip zip dir basename='':
    #!/usr/bin/env bash
    set -euo pipefail

    # --- argument binding ---------------------------------------------------
    # See add-manual-url for the rationale behind binding just placeholders
    # to shell variables before use (shellcheck SC2157).
    ZIP="{{zip}}"
    DIR="{{dir}}"
    BASENAME="{{basename}}"

    if [[ -z "$ZIP" ]]; then
        echo "{{RED}}Error: zip is required.{{NORMAL}}" >&2
        echo "Usage: just add-manual-zip <zip> <dir> [basename]" >&2
        exit 1
    fi
    if [[ -z "$DIR" ]]; then
        echo "{{RED}}Error: dir is required.{{NORMAL}}" >&2
        echo "Usage: just add-manual-zip <zip> <dir> [basename]" >&2
        exit 1
    fi

    # --- preflight: dependencies and zip existence -------------------------
    if ! command -v unzip >/dev/null 2>&1; then
        echo "{{RED}}Error: unzip is required but not on PATH.{{NORMAL}}" >&2
        exit 1
    fi
    if ! command -v pdfunite >/dev/null 2>&1; then
        echo "{{RED}}Error: pdfunite (poppler) is required but not on PATH.{{NORMAL}}" >&2
        echo "Install via: brew install poppler" >&2
        exit 1
    fi
    if ! command -v exiftool >/dev/null 2>&1; then
        echo "{{RED}}Error: exiftool is required but not on PATH.{{NORMAL}}" >&2
        echo "Install via: brew install exiftool" >&2
        exit 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "{{RED}}Error: jq is required but not on PATH.{{NORMAL}}" >&2
        exit 1
    fi

    if [[ ! -f "$ZIP" ]]; then
        echo "{{RED}}Error: zip file not found: $ZIP{{NORMAL}}" >&2
        exit 1
    fi

    # --- detect BSD vs GNU date for OmniPage offset math -------------------
    # macOS ships BSD date (supports -j -f); Linux ships GNU date (supports -d).
    # Probe once and dispatch in the OmniPage branch. Native branch needs no
    # date arithmetic (the offset is a string substring of /CreationDate).
    DATE_IMPL="unknown"
    if date -j -f "%Y" "2025" "+%s" >/dev/null 2>&1; then
        DATE_IMPL="bsd"
    elif date -d "@1700000000" "+%s" >/dev/null 2>&1; then
        DATE_IMPL="gnu"
    fi

    # --- enumerate PDFs in the zip ------------------------------------------
    # `unzip -Z1` lists each entry on its own line. We filter to *.pdf
    # (case-insensitive) and strip any directory prefix so we keep just the
    # filename. Sorting gives deterministic merge order and a stable "first"
    # PDF for scan-time derivation.
    # Use a while/read loop rather than `mapfile` so this runs under bash 3.2
    # (macOS /bin/bash); mapfile is a bash 4+ builtin.
    ZIP_PDFS=()
    while IFS= read -r line; do ZIP_PDFS+=("$line"); done < <(unzip -Z1 "$ZIP" | tr '[:upper:]' '[:lower:]' | grep '\.pdf$')
    if [[ ${#ZIP_PDFS[@]} -eq 0 ]]; then
        echo "{{RED}}Error: no .pdf entries found inside $ZIP{{NORMAL}}" >&2
        exit 1
    fi

    # The lowercased list is fine for filtering and ordering, but we need the
    # original-case names for original-filename (the scanner's filename is
    # the provenance record). Re-list with original case, sorted to match.
    PDF_NAMES=()
    while IFS= read -r line; do PDF_NAMES+=("$line"); done < <(unzip -Z1 "$ZIP" | grep -i '\.pdf$' | LC_ALL=C sort)

    # Sanity: both lists should have the same length.
    if [[ ${#PDF_NAMES[@]} -ne ${#ZIP_PDFS[@]} ]]; then
        echo "{{RED}}Error: internal mismatch enumerating PDFs in $ZIP{{NORMAL}}" >&2
        exit 1
    fi

    PDF_COUNT="${#PDF_NAMES[@]}"
    echo "{{BLUE}}Found $PDF_COUNT PDF(s) in $ZIP{{NORMAL}}"

    # --- derive basename (longest common prefix of stems) -------------------
    # Strip any leading directory from each zip entry, then the .pdf/.PDF
    # extension. Compute the longest common prefix across all stems, then
    # trim trailing _-. <space> chars. For a single PDF we additionally
    # strip the Brother scanner suffix _YYYYMMDDHHMMSS_NNN if present so the
    # basename is the human-readable device name.
    stems=()
    for name in "${PDF_NAMES[@]}"; do
        stem="${name##*/}"          # strip directory
        stem="${stem%.[pP][dD][fF]}" # strip .pdf/.PDF (case-insensitive, no shopt)
        stems+=("$stem")
    done

    if [[ -z "$BASENAME" ]]; then
        # Seed with the first stem, then shorten to each subsequent stem.
        common="${stems[0]}"
        for stem in "${stems[@]:1}"; do
            # Walk back char by char until common is a prefix of stem.
            while [[ "${stem#"$common"}" == "$stem" && -n "$common" ]]; do
                common="${common%?}"
            done
        done
        # Trim trailing separators/junk.
        while [[ "$common" == *[-_.\ ] ]]; do
            common="${common%?}"
        done
        BASENAME="$common"
    fi

    # Strip a trailing Brother scanner suffix from the basename if present.
    # This applies to both single and multi-PDF cases (the common-prefix step
    # leaves the suffix on the last stem when the prefix itself ends in the
    # scanner clock, e.g. "Foo_a_20260720025804" -> "Foo_a_20260720025804").
    # Pattern: _YYYYMMDDHHMMSS_NNN at end of basename.
    if [[ "$BASENAME" =~ _[0-9]{14}_[0-9]{3}$ ]]; then
        BASENAME="${BASENAME%_*}"  # drop _NNN
        BASENAME="${BASENAME%_*}"  # drop _YYYYMMDDHHMMSS
    fi

    # Final sanity: basename must be non-empty and free of path separators.
    if [[ -z "$BASENAME" ]]; then
        echo "{{RED}}Error: could not derive a basename from the zip contents.{{NORMAL}}" >&2
        echo "Pass an explicit basename: just add-manual-zip <zip> <dir> <basename>" >&2
        exit 1
    fi
    if [[ "$BASENAME" == */* ]]; then
        echo "{{RED}}Error: derived basename contains a path separator: $BASENAME{{NORMAL}}" >&2
        echo "Pass an explicit basename." >&2
        exit 1
    fi

    # A basename containing dots would be parsed by TOML as nested keys, so
    # the meta.toml key must be quoted (mirrors add-manual-url).
    if [[ "$BASENAME" == *.* ]]; then
        KEY="\"$BASENAME\""
    else
        KEY="$BASENAME"
    fi

    PDF_PATH="$DIR/$BASENAME.pdf"
    META_PATH="$DIR/meta.toml"

    echo "{{BLUE}}Using basename: $BASENAME{{NORMAL}}"

    # --- collision checks ---------------------------------------------------
    if [[ -e "$PDF_PATH" ]]; then
        echo "{{RED}}Error: PDF already exists at $PDF_PATH{{NORMAL}}" >&2
        echo "Pick a different basename, or remove the existing file first." >&2
        exit 1
    fi
    if [[ -f "$META_PATH" ]]; then
        BARE_KEY_LINE="[$BASENAME]"
        QUOTED_KEY_LINE="[\"$BASENAME\"]"
        if grep -Fxq "$BARE_KEY_LINE" "$META_PATH" \
           || grep -Fxq "$QUOTED_KEY_LINE" "$META_PATH"; then
            echo "{{RED}}Error: meta.toml already has an entry for [$BASENAME]{{NORMAL}}" >&2
            echo "Edit $META_PATH by hand or pick a different basename." >&2
            exit 1
        fi
    fi

    # --- extract zip to a temp dir ------------------------------------------
    # mktemp -d gives us a clean scratch space; the trap ensures cleanup even
    # on error. We extract everything (not just PDFs) because unzip has no
    # "extract only .pdf" mode, then operate on the PDFs we care about.
    TMPDIR=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf $TMPDIR" EXIT

    echo "{{BLUE}}Extracting $ZIP to temp dir...{{NORMAL}}"
    if ! unzip -qq -o "$ZIP" -d "$TMPDIR"; then
        echo "{{RED}}Error: unzip failed for $ZIP{{NORMAL}}" >&2
        exit 1
    fi

    # Build the list of extracted PDF paths in the same sorted order as
    # PDF_NAMES so pdfunite merges in the intended sequence.
    extracted_paths=()
    for name in "${PDF_NAMES[@]}"; do
        # Strip any leading "./" from zip entries and join onto TMPDIR.
        clean="${name#./}"
        extracted_paths+=("$TMPDIR/$clean")
    done

    # --- derive scan-time from the first PDF -------------------------------
    # Per docs/brother-ads-4900w-filenames.md: scan-time combines the
    # filename's YYYYMMDDHHMMSS clock (authoritative scan-start) with the
    # timezone offset recovered from the PDF's /CreationDate. The first PDF
    # in sorted order carries the earliest scan-start (matching the
    # multi-scan merge convention where scan-time records the first scan).
    FIRST_PDF="${extracted_paths[0]}"
    FIRST_NAME="${PDF_NAMES[0]}"
    FIRST_STEM="${FIRST_NAME##*/}"
    FIRST_STEM="${FIRST_STEM%.[pP][dD][fF]}"

    SCAN_TIME=""
    # Brother scanner suffix pattern: _YYYYMMDDHHMMSS_NNN at end of stem.
    if [[ "$FIRST_STEM" =~ _([0-9]{14})_[0-9]{3}$ ]]; then
        FILE_CLOCK="${BASH_REMATCH[1]}"
        YYYY="${FILE_CLOCK:0:4}"
        MM="${FILE_CLOCK:4:2}"
        DD="${FILE_CLOCK:6:2}"
        hh="${FILE_CLOCK:8:2}"
        mm="${FILE_CLOCK:10:2}"
        ss="${FILE_CLOCK:12:2}"
        FILE_CLOCK_ISO="${YYYY}-${MM}-${DD}T${hh}:${mm}:${ss}"

        # Read Creator and CreationDate via exiftool. -json gives clean
        # machine-parseable output; jq pulls the two fields.
        META_JSON=$(exiftool -json -Creator -CreateDate "$FIRST_PDF" 2>/dev/null || true)
        CREATOR=$(printf '%s' "$META_JSON" | jq -r '.[0].Creator // ""')
        CREATE_DATE=$(printf '%s' "$META_JSON" | jq -r '.[0].CreateDate // ""')

        if [[ -n "$CREATOR" && -n "$CREATE_DATE" ]]; then
            # Native path: Creator contains "Brother Scanner System".
            # /CreationDate format: "2026:01:01 15:39:32-05:00".
            # The offset is the trailing [+-]HH:MM; no arithmetic needed.
            if [[ "$CREATOR" == *"Brother Scanner System"* ]]; then
                if [[ "$CREATE_DATE" =~ ([+-][0-9]{2}:[0-9]{2})$ ]]; then
                    OFFSET="${BASH_REMATCH[1]}"
                    SCAN_TIME="${FILE_CLOCK_ISO}${OFFSET}"
                else
                    echo "{{YELLOW}}Warning: native /CreationDate has no offset; skipping scan-time.{{NORMAL}}" >&2
                fi
            # OmniPage path: Creator contains "OmniPage CSDK".
            # /CreationDate is UTC with a Z suffix: "2025:04:29 02:47:42Z".
            # Per the doc there is a DST double-correction bug: during EDT
            # months an extra hour is added, so we subtract one hour when
            # the filename month is 3-10 (rough approximation of US DST).
            elif [[ "$CREATOR" == *"OmniPage CSDK"* ]]; then
                # Parse the UTC timestamp: "YYYY:MM:DD HH:MM:SSZ" -> epoch.
                # exiftool emits colons in the date; normalize to make the
                # date parsers happy.
                CD_DATE="${CREATE_DATE%% *}"        # 2025:04:29
                CD_TIME="${CREATE_DATE#* }"         # 02:47:42Z
                CD_TIME="${CD_TIME%Z}"              # 02:47:42
                CD_Y="${CD_DATE%%:*}"
                CD_REST="${CD_DATE#*:}"
                CD_MO="${CD_REST%%:*}"
                CD_D="${CD_REST#*:}"
                CD_H="${CD_TIME%%:*}"
                CD_TREST="${CD_TIME#*:}"
                CD_M="${CD_TREST%%:*}"
                CD_S="${CD_TREST#*:}"
                CD_ISO="${CD_Y}-${CD_MO}-${CD_D}T${CD_H}:${CD_M}:${CD_S}"

                if [[ "$DATE_IMPL" == "unknown" ]]; then
                    echo "{{YELLOW}}Warning: neither BSD nor GNU date detected; skipping OmniPage scan-time.{{NORMAL}}" >&2
                else
                    # Convert both clocks to epoch seconds (UTC) so the
                    # difference is pure integer math. The filename clock is
                    # local wall-clock; we treat it as UTC for the diff and
                    # interpret the result as the offset.
                    if [[ "$DATE_IMPL" == "bsd" ]]; then
                        FILE_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$FILE_CLOCK_ISO" "+%s")
                        CD_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$CD_ISO" "+%s")
                    else
                        FILE_EPOCH=$(date -u -d "$FILE_CLOCK_ISO" "+%s")
                        CD_EPOCH=$(date -u -d "$CD_ISO" "+%s")
                    fi

                    # Undo the OmniPage DST double-correction: subtract one
                    # hour when the filename month is in DST (3-10). Use 10#
                    # to force base-10 interpretation; MM is zero-padded and
                    # values like 08/09 are invalid as octal under [[ -ge ]].
                    if (( 10#$MM >= 3 && 10#$MM <= 10 )); then
                        CD_EPOCH=$((CD_EPOCH - 3600))
                    fi

                    # offset_seconds = FILE_EPOCH - CD_EPOCH
                    # (filename clock is local; CreationDate is UTC; the
                    # difference is the timezone offset, positive east of
                    # UTC, negative west. We are west, so expect negative.)
                    DIFF=$((FILE_EPOCH - CD_EPOCH))

                    # Round to the nearest hour (US timezones are whole-hour
                    # offsets; the ~1 min finalize latency falls within the
                    # 30-min rounding band).
                    if [[ "$DIFF" -ge 0 ]]; then
                        OFFSET_HH=$(( (DIFF + 1800) / 3600 ))
                    else
                        OFFSET_HH=$(( (DIFF - 1800) / 3600 ))
                    fi

                    # Format as [+-]HH:00. Bash arithmetic is truncation
                    # toward zero, so handle sign explicitly for the width.
                    if [[ "$OFFSET_HH" -ge 0 ]]; then
                        OFFSET=$(printf '+%02d:00' "$OFFSET_HH")
                    else
                        OFFSET=$(printf -- '-%02d:00' "$((-OFFSET_HH))")
                    fi
                    SCAN_TIME="${FILE_CLOCK_ISO}${OFFSET}"
                fi
            else
                echo "{{YELLOW}}Warning: unknown Creator '$CREATOR'; skipping scan-time.{{NORMAL}}" >&2
            fi
        else
            echo "{{YELLOW}}Warning: could not read PDF metadata for scan-time; skipping.{{NORMAL}}" >&2
        fi
    else
        echo "{{YELLOW}}Note: first PDF does not match Brother scanner filename pattern; no scan-time.{{NORMAL}}" >&2
    fi

    # --- merge PDFs (or copy if single) -------------------------------------
    mkdir -p "$DIR"

    if [[ "$PDF_COUNT" -eq 1 ]]; then
        echo "{{BLUE}}Copying single PDF -> $PDF_PATH{{NORMAL}}"
        if ! cp "${extracted_paths[0]}" "$PDF_PATH"; then
            echo "{{RED}}Error: cp failed{{NORMAL}}" >&2
            rm -f "$PDF_PATH"
            exit 1
        fi
    else
        echo "{{BLUE}}Merging $PDF_COUNT PDFs -> $PDF_PATH{{NORMAL}}"
        if ! pdfunite "${extracted_paths[@]}" "$PDF_PATH"; then
            echo "{{RED}}Error: pdfunite failed{{NORMAL}}" >&2
            rm -f "$PDF_PATH"
            exit 1
        fi
    fi

    # Sanity check: non-empty file whose first bytes look like a PDF.
    if [[ ! -s "$PDF_PATH" ]]; then
        echo "{{RED}}Error: output PDF is empty: $PDF_PATH{{NORMAL}}" >&2
        rm -f "$PDF_PATH"
        exit 1
    fi
    HEADER="$(head -c 4 "$PDF_PATH" 2>/dev/null || true)"
    if [[ "$HEADER" != "%PDF" ]]; then
        echo "{{RED}}Error: output does not start with %PDF (got: $(printf '%q' "$HEADER")){{NORMAL}}" >&2
        echo "Leaving the file in place for inspection: $PDF_PATH" >&2
        exit 1
    fi

    # --- write / append meta.toml -------------------------------------------
    # TOML-escape each original-filename value: backslash first, then
    # double-quote. For a single PDF we emit a plain string; for multiple we
    # emit a TOML array (matching the multi-scan merge style in
    # Computer/Modems meta.toml).
    escaped_names=()
    for name in "${PDF_NAMES[@]}"; do
        en="${name//\\/\\\\}"
        en="${en//\"/\\\"}"
        escaped_names+=("$en")
    done

    if [[ "$PDF_COUNT" -eq 1 ]]; then
        OFN_LINE="original-filename = \"${escaped_names[0]}\""
    else
        # Indent array entries to match the existing style (two spaces).
        OFN_LINE="original-filename = ["
        for en in "${escaped_names[@]}"; do
            OFN_LINE="$OFN_LINE"$'\n  '"\"$en\","
        done
        # Strip the trailing comma and close the array.
        OFN_LINE="${OFN_LINE%,}"
        OFN_LINE="$OFN_LINE"$'\n'"]"
    fi

    if [[ -n "$SCAN_TIME" ]]; then
        BLOCK="$(printf '[%s]\n%s\nscan-time = "%s"\n' \
            "$KEY" "$OFN_LINE" "$SCAN_TIME")"
    else
        BLOCK="$(printf '[%s]\n%s\n' "$KEY" "$OFN_LINE")"
    fi

    if [[ ! -e "$META_PATH" ]]; then
        printf '%s\n' "$BLOCK" > "$META_PATH"
    else
        printf '\n%s\n' "$BLOCK" >> "$META_PATH"
    fi

    echo "{{GREEN}}Wrote entry for [$BASENAME] in $META_PATH{{NORMAL}}"
    if [[ -n "$SCAN_TIME" ]]; then
        echo "{{GREEN}}  scan-time = $SCAN_TIME{{NORMAL}}"
    fi

    # --- stage files (git-lfs handles the PDF per .gitattributes) -----------
    git add "$PDF_PATH" "$META_PATH"
    echo "{{GREEN}}Staged $PDF_PATH and $META_PATH (not committed).{{NORMAL}}"

    # --- validate -----------------------------------------------------------
    echo "{{BLUE}}Validating meta.toml files...{{NORMAL}}"
    if ! just cue-verify-meta; then
        echo "{{RED}}Validation failed. The new files are staged for inspection:{{NORMAL}}" >&2
        echo "{{RED}}  $PDF_PATH{{NORMAL}}" >&2
        echo "{{RED}}  $META_PATH{{NORMAL}}" >&2
        echo "{{RED}}Fix meta.toml by hand, then re-run 'just cue-verify-meta'.{{NORMAL}}" >&2
        exit 1
    fi

    echo "{{GREEN}}Done. Added manual [$BASENAME] to $DIR from $ZIP.{{NORMAL}}"
