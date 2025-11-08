# Changelog

## condathis 0.1.4 (Development Version)

Release Date: Unreleased

Development Changelog:
[dev](https://github.com/luciorq/condathis/compare/v0.1.3...HEAD)

## condathis 0.1.3

CRAN release: 2025-11-08

Release Date: 2025-11-07

Development Changelog:
[0.1.3](https://github.com/luciorq/condathis/compare/v0.1.2...v0.1.3)

### Added

- New
  [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  function to clean the local package cache.

- New `verbose = "spinner"` strategy to show only spinner animation in
  interactive sessions. Spinner is always silenced in non-interactive
  sessions.

### Changed

- Internal `micromamba` version bump to “2.3.3-0”.

- Argument `verbose = TRUE` is now converted to `verbose = "output"` by
  default in all exported functions.

- Argument `verbose` in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
  and
  [`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
  are set to `verbose = "output"` by default. All internal calls to
  other functions are kept as `"silent"`, unless when calling the
  user-facing function with `verbose = "full"`.

- Argument `verbose = "silent"` now also silence the spinner animation
  in interactive sessions.

### Fixed

- Ignore `CONDA_ENVS_DIRS` environment variable.

## condathis 0.1.2

CRAN release: 2025-06-02

Release Date: 2025-06-02

Development Changelog:
[0.1.2](https://github.com/luciorq/condathis/compare/v0.1.1...v0.1.2)

### Added

- New `stdin` argument to
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) and
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  functions, allowing input to be redirected via standard input
  (`stdin`) via a text file for commands that require it.

- Argument `verbose` included in
  [`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
  and other auxiliary functions, allowing message suppression in all
  package functions.

### Changed

- Internal `micromamba` version bump to “2.1.1-0”.

- [`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)
  now also defines temporary cache directory paths, using
  `R_USER_CACHE_DIR` and `XDG_CACHE_HOME` environment variables.

### Fixed

- Fix parsing of error messages with curly braces in
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) and
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
  in the rethrown error, when `error = "cancel"`.

## condathis 0.1.1

CRAN release: 2025-01-23

Release Date: 2025-01-24

Development Changelog:
[0.1.1](https://github.com/luciorq/condathis/compare/v0.1.0...v0.1.1)

### Changed

- Internal `micromamba` version bump to “2.0.5-0”.

### Fixed

- Fix error in
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  when `error = "continue"` and `cmd` is not on PATH nor in the
  environment. The expected behavior is to not fail
  ([\#23](https://github.com/luciorq/condathis/issues/23)).

- Fix error in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  that would fail if debris from failed installation attempts were left
  in the environment path.

## condathis 0.1.0

CRAN release: 2024-12-11

Release Date: 2024-12-10

Development Changelog:
[0.1.0](https://github.com/luciorq/condathis/compare/v0.0.8...v0.1.0)

### Added

- Initial submission to CRAN.
- New Package Logo.

### Fixed

- [`run()`](https://luciorq.github.io/condathis/reference/run.md) always
  creates empty base environment if it does not exists yet.

## condathis 0.0.8

### Breaking changes

- [`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md)
  now error if no argument is supplied.

- The base directory path used for creating the environments is now
  controlled by
  [`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html) and
  accepts `R_USER_DATA_DIR`, and `XDG_DATA_HOME`, respectively as
  environment variables that can control that path. On Unix/Linux it
  should be `"${HOME}/.local/share/R/condathis"`.

- The default `TMPDIR` for all
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) and
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  calls is cleaned after execution.

- All error messages are resurfaced in the exported function call
  instead of being thrown in the internal `processx` call.

- New classes were added to the error condition in most functions.

### New features

- New
  [`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)
  allow for isolated tests and examples.

### Minor improvements and fixes

- Improved error message in
  [`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md)
  when environment doesn’t exist
  ([\#21](https://github.com/luciorq/condathis/issues/21)).

- Improved message in
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md).

- Spinner is only active when session is interactive.

## condathis 0.0.7

### New features

- [`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
  now tries to download an uncompressed version of the ‘micromamba’
  binary if [`untar()`](https://rdrr.io/r/utils/untar.html) fails
  because of missing `bzip2` system library.
  ([\#10](https://github.com/luciorq/condathis/issues/10) and
  [\#14](https://github.com/luciorq/condathis/issues/14))

- New
  [`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md)
  parses lines output streams from
  [`run()`](https://luciorq.github.io/condathis/reference/run.md)
  results into character vectors.

- New
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  runs binary installed in a Conda environment without wrapping in
  `micromamba run`.

### Minor improvements and fixes

- Internal `micromamba` version bump to “2.0.4-0”.

- [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  and
  [`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)
  have improved output.

## condathis 0.0.6

### Breaking changes

- `method = "auto"` no longer exists. For backward compatibility will
  fall back to `method = "native"`.
  - All container back-end methods were removed and `method = "native"`
    is the only `method` supported using just this package.
  - A method for supplying additional backends from other packages is
    planned to be implemented.

### Minor improvements and fixes

- Remove dependency on `dockerthis`.

- Fix error in
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) when
  `verbose` argument was not supplied.

## condathis 0.0.5

### Breaking changes

- `verbose`, levels `TRUE` and `FALSE` are now soft deprecated. For
  previous functionality `"full"` and `"silent"` should be used
  respectively.

### New features

- [`run()`](https://luciorq.github.io/condathis/reference/run.md) now
  has `error` argument.

### Minor improvements and fixes

- [`run()`](https://luciorq.github.io/condathis/reference/run.md) output
  now has class `"condathis_run_output"` with custom print method.
- [`run()`](https://luciorq.github.io/condathis/reference/run.md) now
  exposes `stderr`.
- `verbose` now accepts any of `c("silent", "full", "cmd", "output")`.
  `TRUE` and `FALSE` are deprecated but still kept for compatibility.
- Improved error handling in
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) when
  invalid arguments are provided.

## condathis 0.0.4

### Breaking changes

- [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  new argument default `overwrite = FALSE`, since the previous behavior
  would allow for the environment to always be overwritten. For previous
  behavior use `overwrite = TRUE`.

- Across the entire package `verbose = FALSE` is default.

### New features

- New
  [`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md)
  retrieves path to environment v(0.0.3.9032).

- [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  now has `overwrite = FALSE` argument v(0.0.3.9030).

- [`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
  now has `micromamba_version` argument (v0.0.3.9025).

- Add support for internal `micromamba` versions above v2.0
  (v0.0.3.9024).

- New
  [`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)
  created (v0.0.3.9012
  [\#7](https://github.com/luciorq/condathis/issues/7)).

### Minor improvements and fixes

- `native_cmd()` now uses additional Environmental Variables for
  removing warnings when calling nested `micromamba run` (v0.0.3.9029
  [\#13](https://github.com/luciorq/condathis/issues/13)).

- Standardize argument order passed to `micromamba`, since v2.0, order
  of some arguments starts to conflict (v0.0.3.9027).

- On Windows, the “BAT” file used by `micromamba run` is renamed
  (v0.0.3.9026 [\#11](https://github.com/luciorq/condathis/issues/11)).

- Internal `micromamba` version is upgraded to “2.0.2-0”, fixes warnings
  about missing prefixes (v0.0.3.9028).

- The internal `micromamba` version is now fixed (currently “v2.0.1-0”)
  (v0.0.3.9025).

- Use GitHub releases as the primary URL for installing `micromamba`
  (v0.0.3.9025).

- Move `--no-rc` and `--no-env` arguments to `native_cmd()`
  (v0.0.3.9024).

- Fix path handling in Windows (v0.0.3.9023).

- Add `mode = "wb"` to internal
  [`download.file()`](https://rdrr.io/r/utils/download.file.html) for
  handling binary downloads in Windows (v0.0.3.9023).

- [`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md)
  and
  [`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md)
  uses `--no-rc` internally (v.0.0.3.9022).

- `create_env_*()`, `packages_search_*()`, and
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  now uses `--no-rc` and `--override-channels` (v0.0.3.9020).

- Remove “defaults” channel (`-c defaults`) from all functions
  (v0.0.3.9020).

- `create_env_*()`, `packages_search_*()`, and
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  uses `--no-channel-priority` internally (v0.0.3.9019).
