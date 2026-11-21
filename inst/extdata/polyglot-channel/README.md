# polyglot test channel

A local conda channel with one package, `polyglot` 0.1.0 (`noarch: generic`,
no dependencies, 1.5 KB). It installs the same script twice, as
`bin/polyglot` and `Scripts/polyglot.cmd`. The script runs as a POSIX
shell script and as a Windows batch file, and prints which kind of system
it runs on.

- Source: <https://github.com/luciorq/polyglot>
- Published: <https://prefix.dev/channels/universe/packages/polyglot>
- File: `noarch/polyglot-0.1.0-h4616a5c_1.conda` (build 1, which records
  the MIT license), SHA256
  `83da2f436e7b4221bcc9ae2ebd29b9630a0f1c4e1e151e214a315a7b3486cc0b`

`noarch/repodata.json` is the package's entry from the `universe` channel's
`noarch/repodata.json`. A channel needs no platform subdirectory when all its
packages are `noarch`.

Examples use it through
`system.file("extdata", "polyglot-channel", package = "condathis")`, and
tests through `polyglot_channel()` (`tests/testthat/helper-polyglot.R`).
Both create environments without network access once micromamba is
installed. A plain directory path works as a channel, and so does a
`file://` URL.
