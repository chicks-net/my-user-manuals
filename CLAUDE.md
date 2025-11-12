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

TOML files with metadata about PDF manuals:

- Top-level keys are PDF basenames (without .pdf extension)
- Each entry contains:
  - `original-filename`: The filename from the Brother scanner
  - `tags`: Array of tags (no standard tagging system yet)

Example:

```toml
[magnifying-light-10x]
original-filename = "20250428222848_001.pdf"
```

## Common Commands

### Repository Management

- `just list` - List all available just recipes
- `just compliance_check` - Run the custom compliance checker (verifies
  README, LICENSE, GitHub files, etc.)

### Git Workflow (via just)

- `just branch <branchname>` - Create a new branch with format
  `$USER/<date>-<branchname>`
- `just pr` - Create a pull request with automatic title/body from commits
- `just pr_checks` - Watch GitHub Actions and check for Copilot/Claude
  suggestions
- `just prweb` - Open the PR in a web browser
- `just merge` - Merge the PR, delete branch, and return to main
- `just sync` - Return to main branch and pull latest changes

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
