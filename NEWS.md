# condathis (development version)

* Add `--no-channel-priority` to `create_env_*()`, `packages_search_*()`, and `install_packages()` (v0.0.3.9019).

* Remove `-c defaults` from all functions (v0.0.3.9020).
* Add `--override-channels` to `create_env_*()`, `packages_search_*()`, and `install_packages()` (v0.0.3.9020).
* Add `--no-rc` to `create_env_*()`, `packages_search_*()`, and `install_packages()` (v.0.0.3.9020).

* Add `--no-rc` to `list_envs()` and `list_packages()` (v.0.0.3.9022).

* Fix path handling in Windows (v0.0.3.9023).
*  Add `mode = "wb"` to internal `download.file()` for handling binary downloads in Windows (v0.0.3.9023).
