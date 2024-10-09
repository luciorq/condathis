# condathis 0.0.4

## Breaking changes

* `create_env()` new argument default `overwrite = FALSE`, since the previous behavior would allow for the environment to always be overwritten. For previous behavior use `overwrite = TRUE`.

* Across the entire package `verbose = FALSE` is default.

## New features

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
