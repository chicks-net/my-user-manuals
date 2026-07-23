# my-user-manuals

My user manuals, scanned in, so I can stop looking at this pile of paper!

## Organization

Just a bunch of files in directories, with maybe some READMEs.

I have considered other options:

- *Digital Asset Management* - the most popular solutions are PHP based and I
  just can't do that.
- *Tagging* - there does not seem to be any standard for tagging these files.
- *Document Management Systems* - I
  [looked for one](https://softwarerecs.stackexchange.com/q/43455/16331) and failed.

So I'm just going to make it up as I go along.

## Requirements

- [git-lfs](https://git-lfs.com/)

## meta.toml

- TOML ftw!
- A `meta.toml` file in each directory.
- Top keys are the basenames of the PDFs.
- Next levels keys are metadata:
  - `original-filename` is the filename produced by the Brother scanner.  The
    filename embeds the scan-start timestamp; see
    [docs/brother-ads-4900w-filenames.md](docs/brother-ads-4900w-filenames.md)
    for the format and the PDF metadata quirks.
  - `tags` is a list of tags.  There are no standard tags yet, hahaha.

See [docs/meta-toml.md](docs/meta-toml.md) for the full field reference,
worked examples, and how to validate.

## Thanks

- Thanks to [Apple.StackExchange](https://apple.stackexchange.com/q/230437/210526)
  for giving a command line way to combine PDFs.
