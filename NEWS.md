# condathis (development version)

* Add `--no-channel-priority` to `create_env_*()`, `packages_search_*()`, and `install_packages()` (v0.0.3.9019).

* Remove `-c defaults` from all functions (v0.0.3.9020).
* Add `--override-channels` to `create_env_*()`, `packages_search_*()`, and `install_packages()` (v0.0.3.9020).
* Add `--no-rc` to `create_env_*()`, `packages_search_*()`, and `install_packages()` (v.0.0.3.9020).

* Add `--no-rc` to `list_envs()` and `list_packages()` (v.0.0.3.9022).

* Fix path handling in Windows (v0.0.3.9023).
*  Add `mode = "wb"` to internal `download.file()` for handling binary downloads in Windows (v0.0.3.9023).

* Add support for `micromamba` versions above v2.0 (v0.0.3.9024).
* Move `--no-rc` and `--no-env` arguments to `native_cmd()` (v0.0.3.9024).

* Fixate `micromamba` version to "2.0.1-0" (v0.0.3.9025).
* Add `micromamba_version` argument to `install_micromamba()` (v0.0.3.9025).
* Use GitHub releases as the primary URL for installing `micromamba` (v0.0.3.9025).

* Fix [#11](https://github.com/luciorq/condathis/issues/11) by renaming the "BAT" file used by `micromamba run` on Windows (v0.0.3.9026).

* Fix standardize argument order passed to `micromamba`, since v2.0, order of some arguments starts to conflict (v0.0.3.9027).

* Update version of `micromamba` to "2.0.2-0", fixes warnings about missing prefix (v0.0.3.9028).
