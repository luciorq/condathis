## condathis 0.1.4

Release Date: 2026-06-19

Development Changelog: [0.1.4](https://github.com/luciorq/condathis/compare/v0.1.3...v0.1.4)

### Added

* New `run_pipeline()` function for Unix-style pipeline execution
  (`cmd1 | cmd2 | cmd3`) using `processx` 3.9.0 kernel-level pipes.
  Each command in the pipeline can run in a different Conda environment.
  Returns an S3 `condathis_pipeline` object with per-process status, stdout
  (last process only), stderr, and PID.
  Supports `stdin` file redirection, writable `stdin = "|"` with an `input`
  value written to the first command, per-command `stdout`/`stderr`
  overrides in the `cmds` named list spec (`stdout` only on the last
  command), `error = "cancel"` / `"continue"`, and automatic crash cleanup
  via `supervise = TRUE`. The default `env_name` environment is now
  auto-created when missing, matching `run()`.

* New `cleanup_tree`, `encoding`, and `linux_pdeathsig` arguments in
  `native_cmd()`, passed through to `processx::run()`.

* `run()` and `run_bin()` gain feature parity with `run_pipeline()`:
  * New `supervise`, `cleanup_tree`, and `linux_pdeathsig` arguments for
    crash-safe process cleanup (previously only available, and always on,
    in `run_pipeline()`). Default to `FALSE`, preserving existing behavior.
  * New `input` argument: writable `stdin = "|"` support, writing
    character/raw data directly to the process's standard input — matching
    `run_pipeline()`'s `input` argument. Previously `stdin` only accepted
    `NULL` or a file path.
  * Both now return a `condathis_result` S3 object instead of a plain
    `processx::run()` list. It remains fully usable as a list (`res$status`,
    `res$stdout`, etc. are unchanged) and adds `pid`, `cmd`, and `env_name`
    fields plus `print()`/`format()` methods, mirroring `condathis_pipeline`.

* `run_pipeline()`'s `supervise`, `cleanup_tree` (previously always `TRUE`),
  and `linux_pdeathsig` (new) are now overridable arguments instead of
  hardcoded, for full parity with `run()`/`run_bin()`.

* New `channel_priority` argument in `create_env()` and `install_packages()`
  to control channel priority strategy.

* Condathis now support system installed `micromamba` binaries.
  For that we added 1 new option and 1 environment variable to control that behavior.
  `condathis_micromamba_path` and `"CONDATHIS_MICROMAMBA_PATH"` respectively.
  The order of discovey is as follows:
  * User override via `getOption("condathis.micromamba_path")`.
  * User override via `CONDATHIS_MICROMAMBA_PATH` environment variable.
  * condathis internal managed path (`micromamba_bin_path()`).
  * R-in-conda: micromamba adjacent to R's own installation prefix.
  * Active conda environment (`CONDA_PREFIX`).
  * condathis managed micromamba-env fallback.
  * System PATH (`Sys.which("micromamba")`).

### Changed

* Internal `micromamba` version bump to "2.8.1-0".

* `clean_cache()` now also removes any additional cache files created in the
  path reported by `tools::R_user_dir(package = "condathis", which = "cache")`.

* Order of `channels` argument changed to have `"conda-forge"` as the first
  option as for using `channel_priority = "strict"` the order of the channels
  matters.
  Note that relying solely on channel order for priority is not recommended.
  Use explicit syntax like: `bioconda::samtools==X.Y.Z` for better guarantee
  of reproducibility.

* `create_env()` now properly parses MatchSpec version constraints strings to
  define if environment need to be recreated using new internal functions
  `parse_match_spec()` and `version_spec_contains()` to parse Conda MatchSpec
  and use VersionSpec to compare versions, following CEP29 and CEP33, respectively.

### Fixed

* Fix error in `create_env()` when packages were specified with `"channel::package"` environment was always recreated.

* Fix `run_pipeline()` checking that Conda environments exist before
  attempting to auto-create the missing default environment, which made the
  auto-create path unreachable.

* Fix `run_pipeline()` crashing when reading `stdout`/`stderr` for a process
  whose output was redirected to a file or discarded (`NULL`) instead of
  captured with `"|"`.

* Fix `run_pipeline()` letting a raw `processx` error escape uncaught when a
  command is not found, ignoring the `error` argument entirely. It now
  matches `run()`: `error = "continue"` reports `status = 127` for that
  command and keeps running the rest of the pipeline; `error = "cancel"`
  throws a `condathis_pipeline_status_error` instead of a low-level error.

* Fix `run_pipeline()` error messages breaking (or silently corrupting) when
  a failing command's `stderr` contained curly braces, since
  `cli::cli_abort()` interprets `{`/`}` as glue syntax. Captured stderr,
  command strings, and environment names are now escaped before being
  embedded in the error message.

* Fix `run_pipeline()` always throwing on a missing custom environment
  regardless of `error`. `error = "continue"` now reports `status = 127` for
  commands targeting that environment instead of aborting the whole
  pipeline; `error = "cancel"` keeps the previous fail-fast behavior.

## condathis 0.1.3

Release Date: 2025-11-07

Development Changelog: [0.1.3](https://github.com/luciorq/condathis/compare/v0.1.2...v0.1.3)

### Added

* New `clean_cache()` function to clean the local package cache.

* New `verbose = "spinner"` strategy to show only spinner animation
  in interactive sessions.
  Spinner is always silenced in non-interactive sessions.

### Changed

* Internal `micromamba` version bump to "2.3.3-0".

* Argument `verbose = TRUE` is now converted to `verbose = "output"` by
  default in all exported functions.

* Argument `verbose` in `create_env()`, `run()`, `run_bin()`,
  and `install_micromamba()` are set to `verbose = "output"` by default.
  All internal calls to other functions are kept as `"silent"`, unless when
  calling the user-facing function with `verbose = "full"`.

* Argument `verbose = "silent"` now also silence the spinner animation in
  interactive sessions.

### Fixed

* Ignore `CONDA_ENVS_DIRS` environment variable.

## condathis 0.1.2

Release Date: 2025-06-02

Development Changelog: [0.1.2](https://github.com/luciorq/condathis/compare/v0.1.1...v0.1.2)

### Added

* New `stdin` argument to `run()` and `run_bin()` functions, allowing input to
  be redirected via standard input (`stdin`) via a text file for commands that
  require it.

* Argument `verbose` included in `install_micromamba()` and other auxiliary
  functions, allowing message suppression in all package functions.

### Changed

* Internal `micromamba` version bump to "2.1.1-0".

* `with_sandbox_dir()` now also defines temporary cache directory paths,
  using `R_USER_CACHE_DIR` and `XDG_CACHE_HOME` environment variables.

### Fixed

* Fix parsing of error messages with curly braces in `run()` and `run_bin()`,
  in the rethrown error, when `error = "cancel"`.

## condathis 0.1.1

Release Date: 2025-01-24

Development Changelog: [0.1.1](https://github.com/luciorq/condathis/compare/v0.1.0...v0.1.1)

### Changed

* Internal `micromamba` version bump to "2.0.5-0".

### Fixed

* Fix error in `run_bin()` when `error = "continue"` and `cmd` is not on
  PATH nor in the environment.
  The expected behavior is to not fail (#23).

* Fix error in `create_env()` that would fail if debris from failed installation
  attempts were left in the environment path.

## condathis 0.1.0

Release Date: 2024-12-10

Development Changelog: [0.1.0](https://github.com/luciorq/condathis/compare/v0.0.8...v0.1.0)

### Added

* Initial submission to CRAN.
* New Package Logo.

### Fixed

* `run()` always creates empty base environment if it does not exists yet.

## condathis 0.0.8

### Breaking changes

* `env_exists()` now error if no argument is supplied.

* The base directory path used for creating the environments is now controlled
  by `tools::R_user_dir()` and accepts `R_USER_DATA_DIR`, and `XDG_DATA_HOME`,
  respectively as environment variables that can control that path.
  On Unix/Linux it should be `"${HOME}/.local/share/R/condathis"`.

* The default `TMPDIR` for all `run()` and `run_bin()` calls is cleaned after
  execution.

* All error messages are resurfaced in the exported function call instead of
  being thrown in the internal `processx` call.

* New classes were added to the error condition in most functions.

### New features

* New `with_sandbox_dir()` allow for isolated tests and examples.

### Minor improvements and fixes

* Improved error message in `list_packages()` when environment doesn't exist (#21).

* Improved message in `install_packages()`.

* Spinner is only active when session is interactive.

## condathis 0.0.7

### New features

* `install_micromamba()` now tries to download an uncompressed version of the
  'micromamba' binary if `untar()` fails because of missing `bzip2` system
  library. (#10 and #14)

* New `parse_output()` parses lines output streams from `run()` results into
  character vectors.

* New `run_bin()` runs binary installed in a Conda environment without wrapping
  in `micromamba run`.

### Minor improvements and fixes

* Internal `micromamba` version bump to "2.0.4-0".

* `create_env()` and `remove_env()` have improved output.

## condathis 0.0.6

### Breaking changes

* `method = "auto"` no longer exists. For backward compatibility will fall back
  to `method = "native"`.
  * All container back-end methods were removed and `method = "native"` is the
    only `method` supported using just this package.
  * A method for supplying additional backends from other packages is planned
    to be implemented.

### Minor improvements and fixes

* Remove dependency on `dockerthis`.

* Fix error in `run()` when `verbose` argument was not supplied.

## condathis 0.0.5

### Breaking changes

* `verbose`, levels `TRUE` and `FALSE` are now soft deprecated.
  For previous functionality `"full"` and `"silent"` should be used respectively.

### New features

* `run()` now has `error` argument.

### Minor improvements and fixes

* `run()` output now has class `"condathis_run_output"` with custom print method.
* `run()` now exposes `stderr`.
* `verbose` now accepts any of `c("silent", "full", "cmd", "output")`.
  `TRUE` and `FALSE` are deprecated but still kept for compatibility.
* Improved error handling in `run()` when invalid arguments are provided.

## condathis 0.0.4

### Breaking changes

* `create_env()` new argument default `overwrite = FALSE`,
  since the previous behavior would allow for the environment to always be overwritten.
  For previous behavior use `overwrite = TRUE`.

* Across the entire package `verbose = FALSE` is default.

### New features

* New `get_env_dir()` retrieves path to environment v(0.0.3.9032).

* `create_env()` now has `overwrite = FALSE` argument v(0.0.3.9030).

* `install_micromamba()` now has `micromamba_version` argument (v0.0.3.9025).

* Add support for internal `micromamba` versions above v2.0 (v0.0.3.9024).

* New `remove_env()` created (v0.0.3.9012 #7).

### Minor improvements and fixes

* `native_cmd()` now uses additional Environmental Variables for removing
  warnings when calling nested `micromamba run` (v0.0.3.9029 #13).

* Standardize argument order passed to `micromamba`, since v2.0, order of some
  arguments starts to conflict (v0.0.3.9027).

* On Windows, the "BAT" file used by `micromamba run` is renamed (v0.0.3.9026 #11).

* Internal `micromamba` version is upgraded to "2.0.2-0", fixes warnings about
  missing prefixes (v0.0.3.9028).

* The internal `micromamba` version is now fixed (currently "v2.0.1-0") (v0.0.3.9025).

* Use GitHub releases as the primary URL for installing `micromamba` (v0.0.3.9025).

* Move `--no-rc` and `--no-env` arguments to `native_cmd()` (v0.0.3.9024).

* Fix path handling in Windows (v0.0.3.9023).

* Add `mode = "wb"` to internal `download.file()` for handling binary downloads
in Windows (v0.0.3.9023).

* `list_envs()` and `list_packages()` uses `--no-rc` internally (v.0.0.3.9022).

* `create_env_*()`, `packages_search_*()`, and `install_packages()` now uses
  `--no-rc` and `--override-channels` (v0.0.3.9020).

* Remove "defaults" channel (`-c defaults`) from all functions (v0.0.3.9020).

* `create_env_*()`, `packages_search_*()`, and `install_packages()` uses
  `--no-channel-priority` internally (v0.0.3.9019).
