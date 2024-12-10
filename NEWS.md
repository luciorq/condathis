# condathis 0.1.0

* Initial submission to CRAN.

# condathis 0.0.8

## Breaking changes

* `env_exists()` now error if no argument is supplied.

* The base directory path used for creating the environments is now controlled by `tools::R_user_dir()` and accepts `R_USER_DATA_DIR`, and `XDG_DATA_HOME`, respectively as environment variables that can control that path. On Unix/Linux it should be `"${HOME}/.local/share/R/condathis"`.

* The default `TMPDIR` for all `run()` and `run_bin()` calls are clean after execution.

* All error messages are resurfaced in the exported function call instead of being thrown in the internal `processx` call.

* New classes were added to the error condition in most functions.

## New features

## Minor improvements and fixes

* Improved error message in `list_packages()`when env don't exist (#21).

* Improved message in `install_packages()`.

* Spinner is only active when session is interactive.

* New `with_sandbox_dir()` allow for isolated tests and examples.

# condathis 0.0.7

## New features

* `install_micromamba()` now tries to download an uncompressed version of the 'micromamba' binary if `untar()` fails
  because of missing `bzip2` system library. (#10 and #14)

* New `parse_output()` parse lines output streams from `run()` results into character vectors.

* New `run_bin()` runs binary installed in a Conda environment without wrapping in `micromamba run`.

## Minor improvements and fixes

* Internal `micromamba` version bump to "2.0.4-0".

* `create_env()` and `remove_env()` have improved output.

# condathis 0.0.6

## Breaking changes

* `method = "auto"` no longer exists. For backward compatibility will fall back
  to `method = "native"`.
  * All container back-end methods were removed and `method = "native"` is the
    only `method` supported using just this package.
  * A method for supplying additional backends from other packages is planned to be implemented.

## Minor improvements and fixes

* Remove dependency on `dockerthis`.

* Fix error in `run()` when `verbose` argument was not supplied.

# condathis 0.0.5

## Breaking changes

* `verbose`, levels `TRUE` and `FALSE` are now soft deprecated. For previous functionality `"full"` and `"silent"` should be used respectively.

## New features

* `run()` now has `error` argument.

## Minor improvements and fixes

* `run()` output now has class `"condathis_run_output"` with custom print method.
* `run()` now exposes `stderr`.
* `verbose` now accept any of `c("silent", "full", "cmd", "output")`. `TRUE` and `FALSE` are deprecated but still kept for compatibility.

# condathis 0.0.4

## Breaking changes

* `create_env()` new argument default `overwrite = FALSE`, since the previous behavior would allow for the environment to always be overwritten. For previous behavior use `overwrite = TRUE`.

* Across the entire package `verbose = FALSE` is default.

## New features

* New `get_env_dir()` retrieves path to environment v(0.0.3.9032).

* `create_env()` now has `overwrite = FALSE` argument v(0.0.3.9030).

* `install_micromamba()` now has `micromamba_version` argument (v0.0.3.9025).

* Add support for internal `micromamba` versions above v2.0 (v0.0.3.9024).

* New `remove_env()` created (v0.0.3.9012 #7).

## Minor improvements and fixes

* `native_cmd()` now uses additional Environmental Variables for removing warnings when calling nested `micromamba run` (v0.0.3.9029 #13).

* Standardize argument order passed to `micromamba`, since v2.0, order of some arguments starts to conflict (v0.0.3.9027).

* On Windows, the "BAT" file used by `micromamba run` is renamed (v0.0.3.9026 #11).

* Internal `micromamba` version is upgraded to "2.0.2-0", fixes warnings about missing prefixes (v0.0.3.9028).
* The internal `micromamba` version is now fixed (currently "v2.0.1-0") (v0.0.3.9025).
* Use GitHub releases as the primary URL for installing `micromamba` (v0.0.3.9025).

* Move `--no-rc` and `--no-env` arguments to `native_cmd()` (v0.0.3.9024).

* Fix path handling in Windows (v0.0.3.9023).
*  Add `mode = "wb"` to internal `download.file()` for handling binary downloads in Windows (v0.0.3.9023).

* `list_envs()` and `list_packages()` uses `--no-rc` internally (v.0.0.3.9022).

* `create_env_*()`, `packages_search_*()`, and `install_packages()` now uses `--no-rc` and `--override-channels` (v0.0.3.9020).

* Remove "defaults" channel (`-c defaults`) from all functions (v0.0.3.9020).

* `create_env_*()`, `packages_search_*()`, and `install_packages()` uses `--no-channel-priority` internally (v0.0.3.9019).
