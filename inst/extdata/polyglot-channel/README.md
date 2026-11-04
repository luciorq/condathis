# polyglot test channel

A local conda channel with one package, `polyglot` 0.1.0 (`noarch: generic`,
no dependencies, 1.5 KB). It installs one script, `bin/polyglot` and
`Scripts/polyglot.cmd`, that runs as a POSIX shell script and as a Windows
batch file. It prints which kind of system it runs on.

- Source: <https://github.com/luciorq/polyglot>
- Published: <https://prefix.dev/channels/universe/packages/polyglot>
- File: `noarch/polyglot-0.1.0-h4616a5c_0.conda`, SHA256
  `8c37f42361a32fb76093020403b38064644a7410e8ffc65c669b5595eca36507`

`noarch/repodata.json` is the package's entry from the `universe` channel's
`noarch/repodata.json`. A channel needs no platform subdirectory when all its
packages are `noarch`.

Examples use it through
`system.file("extdata", "polyglot-channel", package = "condathis")`, and
tests through `polyglot_channel()` (`tests/testthat/helper-polyglot.R`).
Both create environments without network access once micromamba is
installed. A plain directory path works as a channel, and so does a
`file://` URL.
