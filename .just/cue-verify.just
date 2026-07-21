# File Format Self-checks

# use Cue to verify /.repo.toml validity and flag configuration
[group('Testing/Compliance')]
cue-verify:
    #!/usr/bin/env bash
    set -euo pipefail

    # Stage 1: Cue validates TOML structure and types
    cue vet .repo.toml docs/repo-toml.cue
    echo "{{GREEN}}Cue structure validation passed.{{NORMAL}}"

    # Extract org/repo names once at the top for all stages
    ORG_NAME=$(cue export .repo.toml | jq -r '.urls.web_url // ""' | sed -E 's|https://github.com/([^/]+)/.*|\1|')
    REPO_NAME=$(cue export .repo.toml | jq -r '.urls.web_url // ""' | sed -E 's|.*/([^/]+)/?$|\1|')

    # Stage 2: Validate flags match actual configuration
    echo "{{BLUE}}Verifying .repo.toml flags match repository configuration...{{NORMAL}}"

    # Extract flags from .repo.toml using cue export + jq
    CLAUDE_FLAG=$(cue export .repo.toml | jq -r '.flags.claude // false')
    CLAUDE_REVIEW_FLAG=$(cue export .repo.toml | jq -r '.flags."claude-review" // false')
    COPILOT_REVIEW_FLAG=$(cue export .repo.toml | jq -r '.flags."copilot-review" // false')
    STANDARD_RELEASE_FLAG=$(cue export .repo.toml | jq -r 'if .flags."standard-release" == false then "false" else "true" end')

    # Error counter
    ERRORS=0

    # Validate claude flag
    if [[ "$CLAUDE_FLAG" == "true" ]]; then
        if [[ ! -e ".github/workflows/claude.yml" ]]; then
            echo "{{RED}}[flags.claude] Missing required file: .github/workflows/claude.yml{{NORMAL}}"
            ERRORS=$((ERRORS + 1))
        fi
        if [[ ! -e ".github/workflows/claude-code-review.yml" ]]; then
            echo "{{RED}}[flags.claude] Missing required file: .github/workflows/claude-code-review.yml{{NORMAL}}"
            ERRORS=$((ERRORS + 1))
        fi
    fi

    # Validate claude-review flag
    if [[ "$CLAUDE_REVIEW_FLAG" == "true" ]]; then
        if [[ ! -e ".github/workflows/claude-code-review.yml" ]]; then
            echo "{{RED}}[flags.claude-review] Missing required file: .github/workflows/claude-code-review.yml{{NORMAL}}"
            ERRORS=$((ERRORS + 1))
        fi
        if [[ ! -e ".just/gh-process.just" ]]; then
            echo "{{RED}}[flags.claude-review] Missing required file: .just/gh-process.just{{NORMAL}}"
            ERRORS=$((ERRORS + 1))
        fi
    fi

    # Validate copilot-review flag
    if [[ "$COPILOT_REVIEW_FLAG" == "true" ]]; then
        if [[ -z "$ORG_NAME" ]]; then
            echo "{{RED}}[flags.copilot-review] Cannot extract organization name from .repo.toml{{NORMAL}}"
            ERRORS=$((ERRORS + 1))
        else
            # Try to check if org has Copilot via GitHub API
            if gh api "orgs/$ORG_NAME/copilot/billing" &>/dev/null; then
                # API call succeeded - org has Copilot
                :
            else
                EXIT_CODE=$?
                if [[ $EXIT_CODE -eq 22 ]]; then
                    # HTTP 404 - org doesn't have Copilot
                    echo "{{RED}}[flags.copilot-review] Organization '$ORG_NAME' does not have GitHub Copilot enabled{{NORMAL}}"
                    ERRORS=$((ERRORS + 1))
                else
                    # Permission or network error - warn but don't fail
                    echo "{{YELLOW}}[flags.copilot-review] Warning: Cannot verify Copilot status (exit code: $EXIT_CODE){{NORMAL}}"
                    echo "{{YELLOW}}  This may be due to API permissions or network issues{{NORMAL}}"
                fi
            fi
        fi
    fi

    # Validate standard-release flag (informational only)
    if [[ "$STANDARD_RELEASE_FLAG" == "false" ]]; then
        echo "{{YELLOW}}[flags.standard-release] Standard release workflow is disabled{{NORMAL}}"
        echo "{{YELLOW}}  Ensure custom release recipes exist in justfile or .just/ modules{{NORMAL}}"
    fi

    # Stage 3: Validate GitHub metadata sync
    echo "{{BLUE}}Verifying description and topics match GitHub...{{NORMAL}}"

    # Extract description and topics from .repo.toml
    TOML_DESC=$(cue export .repo.toml | jq -r '.about.description // ""')
    TOML_TOPICS=$(cue export .repo.toml | jq -r '.about.topics // [] | sort | join(",")')

    # Check if we can extract org and repo names
    if [[ -z "$ORG_NAME" || -z "$REPO_NAME" ]]; then
        echo "{{YELLOW}}Warning: Cannot extract org/repo name from .repo.toml - skipping GitHub sync check{{NORMAL}}"
    else
        # Fetch metadata from GitHub API
        if GH_DATA=$(gh api "repos/$ORG_NAME/$REPO_NAME" 2>/dev/null); then
            GH_DESC=$(echo "$GH_DATA" | jq -r '.description // ""')
            GH_TOPICS=$(echo "$GH_DATA" | jq -r '.topics // [] | sort | join(",")')

            # Compare description
            if [[ "$TOML_DESC" != "$GH_DESC" ]]; then
                echo "{{RED}}[about.description] Mismatch with GitHub{{NORMAL}}"
                echo "  .repo.toml: $TOML_DESC"
                echo "  GitHub:     $GH_DESC"
                ERRORS=$((ERRORS + 1))
            fi

            # Compare topics
            if [[ "$TOML_TOPICS" != "$GH_TOPICS" ]]; then
                echo "{{RED}}[about.topics] Mismatch with GitHub{{NORMAL}}"
                echo "  .repo.toml: $TOML_TOPICS"
                echo "  GitHub:     $GH_TOPICS"
                ERRORS=$((ERRORS + 1))
            fi
        else
            echo "{{YELLOW}}Warning: Cannot fetch GitHub metadata (API error){{NORMAL}}"
            echo "{{YELLOW}}  This may be due to API permissions or network issues{{NORMAL}}"
        fi
    fi

    # Report results
    if [[ $ERRORS -gt 0 ]]; then
        echo ""
        echo "{{RED}}Flag verification failed with $ERRORS error(s){{NORMAL}}"
        exit 1
    fi

    echo "{{GREEN}}Flag verification passed.{{NORMAL}}"

    # Stage 4: Validate all meta.toml files against docs/meta-toml.cue and
    # cross-check that each declared PDF basename exists on disk next to the
    # meta.toml that declares it. Delegated to a standalone recipe so it can
    # also be run on its own: `just cue-verify-meta`.
    just cue-verify-meta

# use Cue to verify every meta.toml under the category directories against
# docs/meta-toml.cue, and cross-check that each top-level key [basename] has a
# matching <basename>.pdf on disk in the same directory as the meta.toml.
[group('Testing/Compliance')]
cue-verify-meta:
    #!/usr/bin/env bash
    set -euo pipefail

    SCHEMA="docs/meta-toml.cue"
    ERRORS=0
    META_COUNT=0

    # Discover every meta.toml under the repo, excluding .git.
    while IFS= read -r -d '' META; do
        META_COUNT=$((META_COUNT + 1))
        DIR="$(dirname "$META")"

        # Stage A: structural validation against the CUE schema.
        if ! cue vet "$META" "$SCHEMA"; then
            echo "{{RED}}[$META] CUE schema validation failed{{NORMAL}}"
            ERRORS=$((ERRORS + 1))
            # Skip the cross-check: keys may not even be parseable.
            continue
        fi

        # Stage B: every top-level key [basename] must have a <basename>.pdf
        # sitting next to this meta.toml. `cue export` emits the keys as a JSON
        # object, so jq -r 'keys[]' gives us the basenames.
        for BASE in $(cue export "$META" | jq -r 'keys[]'); do
            PDF="$DIR/$BASE.pdf"
            if [[ ! -f "$PDF" ]]; then
                echo "{{RED}}[$META] missing $BASE.pdf (declared as [$BASE]){{NORMAL}}"
                ERRORS=$((ERRORS + 1))
            fi
        done
    done < <(find . -name meta.toml -not -path './.git/*' -print0)

    if [[ $META_COUNT -eq 0 ]]; then
        echo "{{YELLOW}}No meta.toml files found.{{NORMAL}}"
    fi

    if [[ $ERRORS -gt 0 ]]; then
        echo ""
        echo "{{RED}}meta.toml verification failed with $ERRORS error(s) across $META_COUNT file(s){{NORMAL}}"
        exit 1
    fi

    echo "{{GREEN}}meta.toml verification passed ($META_COUNT file(s)).{{NORMAL}}"

# sync description and topics from GitHub API into .repo.toml
[group('Template Maintenance')]
cue-sync-from-github:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "{{BLUE}}Syncing description and topics from GitHub...{{NORMAL}}"

    REPO_TOML_EXISTS=false
    if [[ -f .repo.toml ]]; then
        REPO_TOML_EXISTS=true
    fi

    # Extract org and repo name
    if $REPO_TOML_EXISTS; then
        ORG_NAME=$(cue export .repo.toml | jq -r '.urls.web_url // ""' | sed -E 's|https://github.com/([^/]+)/.*|\1|')
        REPO_NAME=$(cue export .repo.toml | jq -r '.urls.web_url // ""' | sed -E 's|.*/([^/]+)/?$|\1|')
    fi

    # Fall back to git remote if .repo.toml is missing or parsing failed
    if [[ -z "${ORG_NAME:-}" || -z "${REPO_NAME:-}" ]]; then
        REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
        if [[ -n "$REMOTE_URL" ]]; then
            # Handle SSH (git@github.com:org/repo.git) and HTTPS URLs
            REMOTE_URL="${REMOTE_URL%.git}"
            REMOTE_URL="${REMOTE_URL#git@github.com:}"
            REMOTE_URL="${REMOTE_URL#https://github.com/}"
            ORG_NAME=$(echo "$REMOTE_URL" | cut -d/ -f1)
            REPO_NAME=$(echo "$REMOTE_URL" | cut -d/ -f2)
        fi
    fi

    if [[ -z "${ORG_NAME:-}" || -z "${REPO_NAME:-}" ]]; then
        echo "{{RED}}Error: Cannot determine org/repo name from .repo.toml or git remote{{NORMAL}}"
        exit 1
    fi

    echo "{{BLUE}}Org: $ORG_NAME, Repo: $REPO_NAME{{NORMAL}}"

    # Fetch metadata from GitHub API
    if ! GH_DATA=$(gh api "repos/$ORG_NAME/$REPO_NAME" 2>/dev/null); then
        echo "{{RED}}Error: Cannot fetch GitHub metadata (API error){{NORMAL}}"
        echo "{{YELLOW}}  Check your network connection and GitHub authentication{{NORMAL}}"
        exit 1
    fi

    # Extract description and topics from GitHub
    GH_DESC=$(echo "$GH_DATA" | jq -r '.description // ""')
    GH_TOPICS=$(echo "$GH_DATA" | jq -r '.topics // []')

    # Convert topics array to TOML format
    TOPICS_TOML=$(echo "$GH_TOPICS" | jq -r 'map("\"" + . + "\"") | join(", ")')

    echo "  Description: $GH_DESC"
    echo "  Topics: [$TOPICS_TOML]"

    if $REPO_TOML_EXISTS; then
        # Create backup
        cp .repo.toml .repo.toml.backup
        echo "{{YELLOW}}Created backup: .repo.toml.backup{{NORMAL}}"

        # The state-aware awk program lives in .just/lib/cue_sync.awk so the
        # test runner (.just/lib/cue_sync_test.sh) invokes the exact same
        # logic. See issue #196 for why the program is no longer inlined.
        # Behavior: handles three cases for each key (description, topics):
        #   1. Active line (e.g. `topics = [...]`)        -> replace in place
        #   2. Commented line (e.g. `# topics = [...]`)   -> replace in place
        #   3. Missing line                               -> insert inside [about] block
        # Missing keys are inserted at the end of the `[about]` block, *before*
        # any trailing blank line that separates it from the next section,
        # landing adjacent to the preceding key (e.g. `license`) rather than
        # visually attaching to the next `[section]`. See issue #165 for the
        # failure modes this addresses.
        #
        # Description is passed via the environment (desc=...), not awk's -v,
        # because -v processes backslash escape sequences before the program
        # runs, which would mangle backslashes in the GitHub description. The
        # awk program applies TOML-escaping (backslash and double-quote) on
        # emit, so the output is valid TOML regardless of the description's
        # contents. See issue #198.
        desc="$GH_DESC" awk -v topics="[$TOPICS_TOML]" \
            -f .just/lib/cue_sync.awk .repo.toml > .repo.toml.tmp
        mv .repo.toml.tmp .repo.toml

        # Validate the TOML is still valid after modification.
        # NOTE: cue vet passing does NOT prove the sync wrote the right values
        # (topics is optional in the CUE schema), so the backup is preserved
        # until the trailing `just cue-verify` also passes. See issue #165.
        echo "{{BLUE}}Validating modified TOML...{{NORMAL}}"
        if ! cue vet .repo.toml docs/repo-toml.cue; then
            mv .repo.toml.backup .repo.toml
            echo "{{RED}}Sync failed - TOML validation error. Restored from backup.{{NORMAL}}"
            exit 1
        fi

        # Run full verification (this catches silent topics/description write
        # failures that cue vet cannot, by comparing against the GitHub API).
        echo ""
        echo "{{BLUE}}Running full verification...{{NORMAL}}"
        if ! just cue-verify; then
            mv .repo.toml.backup .repo.toml
            echo "{{RED}}Sync failed - verification mismatch. Restored from backup.{{NORMAL}}"
            exit 1
        fi

        rm .repo.toml.backup
        echo "{{GREEN}}Successfully synced from GitHub to .repo.toml{{NORMAL}}"
    else
        echo "{{YELLOW}}.repo.toml not found - creating from GitHub metadata{{NORMAL}}"

        GIT_SSH="git@github.com:$ORG_NAME/$REPO_NAME.git"
        WEB_URL="https://github.com/$ORG_NAME/$REPO_NAME"

        # TOML-escape the description for the new file: backslash -> \\ and
        # double-quote -> \". Without this, a description containing a
        # backslash (e.g. `C:\path`) produces invalid TOML and cue vet fails,
        # leaving the repo unable to bootstrap .repo.toml on first sync.
        # See issue #198.
        GH_DESC_TOML="${GH_DESC//\\/\\\\}"
        GH_DESC_TOML="${GH_DESC_TOML//\"/\\\"}"

        printf '%s\n' \
            "# .repo.toml" \
            "" \
            "[about]" \
            "description = \"$GH_DESC_TOML\"" \
            "topics = [$TOPICS_TOML]" \
            "" \
            "[urls]" \
            "git_ssh = \"$GIT_SSH\"" \
            "web_url = \"$WEB_URL\"" \
            "" \
            "[flags]" \
            "claude = false" \
            "claude-review = false" \
            "copilot-review = false" \
            "standard-release = true" \
            > .repo.toml

        # Validate the new TOML
        echo "{{BLUE}}Validating new TOML...{{NORMAL}}"
        if ! cue vet .repo.toml docs/repo-toml.cue; then
            rm .repo.toml
            echo "{{RED}}Failed to create valid .repo.toml{{NORMAL}}"
            exit 1
        fi

        # Mirror existing-file branch: clean up on failure (no backup to restore).
        echo ""
        echo "{{BLUE}}Running full verification...{{NORMAL}}"
        if ! just cue-verify; then
            rm .repo.toml
            echo "{{RED}}Newly created .repo.toml failed verification - file removed.{{NORMAL}}"
            exit 1
        fi

        echo "{{GREEN}}Successfully synced from GitHub to .repo.toml{{NORMAL}}"
    fi
