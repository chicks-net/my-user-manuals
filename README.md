# my-user-manuals

My user manuals, scanned in, so I can stop looking at this pile of paper!

## Organization

Just a bunch of files in directories, with maybe some READMEs.

I have considered other options:

- *Digital Asset Management* - the most popular solutions are PHP based and I just can't do that.
- *Tagging* - there does not seem to be any standard for tagging these files.
- *Document Management Systems* - I [looked for one](https://softwarerecs.stackexchange.com/q/43455/16331) and failed.

So I'm just going to make it up as I go along.

## meta.toml

- TOML ftw!
- A `meta.toml` file in each directory.
- Top keys are the basenames of the PDFs.
- Next levels keys are metadata:
    - `original-filename` is the filename produced by the Brother scanner.  It'd be cool to derive any data from this, like the scan date/time.
    - `tags` is a list of tags.  There are no standard tags yet, hahaha.
