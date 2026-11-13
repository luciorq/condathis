## Submission

This is an update of condathis from 0.1.4 (on CRAN since 2026-06-19) to
0.2.0.

condathis 0.2.0 is a feature release with breaking changes: some exported
functions changed their arguments, defaults or return values. NEWS.md lists
these changes first, under "Breaking changes", each with the code to write
instead. No package on CRAN or Bioconductor depends on, imports, suggests
or enhances condathis, so no other package is affected.

## Test environments

* Local: Ubuntu 24.04 (x86_64), R 4.5.3, with the PDF manual, also with
  `_R_CHECK_DEPENDS_ONLY_=true`
* Local: macOS 26.4.1 (arm64), R 4.6.1, also with no network access
* Local: Windows 11 (x64), R 4.6.1 ucrt
* Docker: Ubuntu 26.04, R-devel (2026-11-12 r90880), with the PDF manual,
  also with `_R_CHECK_DEPENDS_ONLY_=true` and with the incoming spell check
  (`_R_CHECK_CRAN_INCOMING_USE_ASPELL_=true`)
* Docker: Ubuntu 26.04, R 4.6.2, with the PDF manual, also with no
  network access
* Docker: Ubuntu 22.04, R 4.3.3 (the minimum in Depends)

## R CMD check results

0 errors | 0 warnings | 0 notes

## Notes

* Examples that need an environment are in \dontrun{}. They download and
  run a third-party executable ('micromamba') and download 'Conda'
  packages, so they need internet access. \donttest{} would not keep them
  from running, because `R CMD check --as-cran` runs \donttest{} examples.
  Examples that need no environment run unguarded.

* Tests that need the internet or a 'micromamba' binary are skipped on
  CRAN. Examples and tests write only to temporary directories.

* condathis downloads 'micromamba' only when a function needs it and no
  usable copy is found, or when the user calls install_micromamba(). The
  download is checked against the SHA256 checksum published with the
  release, and a binary that does not match is not installed. A function
  that downloads micromamba says so in a message, and a binary whose
  checksum cannot be verified is installed with a warning, both unless
  `verbose = "silent"`. condathis installs it in its data directory,
  tools::R_user_dir("condathis", "data") (see ?get_install_dir).
  clean_cache() and remove_env() manage that directory, and ?clean_cache
  shows how to remove everything condathis installed.

* The help pages, NEWS.md and the README mention 'rattlerthis', an
  optional backend package that is not on CRAN. condathis works without
  it: it is not in Depends, Imports, Suggests or Enhances, and condathis
  never installs it. condathis loads it only when it is already installed
  and the user chose that backend: with `method = "rattler"`, with the
  option `condathis.backend_priority`, or because environments or package
  caches that it created earlier exist in the condathis data directory.

## Reverse dependencies

There are no reverse dependencies on CRAN or Bioconductor (checked on
2026-11-12).
