## Submission

condathis 0.2.0 is a feature release. Some exported functions changed
their arguments or return values; NEWS.md lists these changes first,
under "Breaking changes".

## Test environments

* Local: Ubuntu 24.04 (x86_64), R 4.5.3
* Local: macOS 26.4 (arm64), R 4.6.1, also with no network access
* Local: Windows 11 (x64), R 4.6.1
* Docker: Ubuntu 26.04, R-devel (2026-10-29 r90794), also with
  `_R_CHECK_DEPENDS_ONLY_=true`
* Docker: Ubuntu 24.04, R 4.6.1 with TeX Live 2026 (PDF manual included)
* Docker: Ubuntu 22.04, R 4.3.3

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE

  Found the following (possibly) invalid URLs:
    URL: https://github.com/luciorq/condathis/compare/v0.1.4...v0.2.0
      From: NEWS.md
      Status: 404

  The link compares two GitHub tags. It returns 404 until the v0.2.0 tag
  is pushed, on acceptance.

On the local Windows machine, the check also lists a folder 'NULL' in the
check directory and in the temporary directory. R 4.6.1 on Windows
creates it there for any package, a minimal one included.

## Notes

* Examples that create environments need the internet: they download the
  'micromamba' binary and 'Conda' packages. They are in \dontrun{}, not
  \donttest{}, because R CMD check --as-cran runs \donttest{} examples.
  Tests that would download anything are skipped on CRAN. Examples and
  tests write only to temporary directories.

* Some help pages mention 'rattlerthis', an optional backend package that
  is not on CRAN. condathis does not depend on, suggest or enhance it. It
  loads it, when it is installed, only for users who chose that backend,
  for example with `method = "rattler"`.

## revdepcheck results

There are currently no downstream dependencies for this package.
