# TODO: Fewer and cleaner lines in `~/.conda/environments.txt`

See `PLAN.md` for the decisions.

## Done

- [x] Remove the six stale lines the 2026-11-16 tests left in the user's
      registry (exact lines only, backup kept outside the repo).
- [x] 1: `micromamba_pip_needs_home()`; `micromamba_env_file_needs_home()`
      uses it for pip sections; macOS `PIP_CACHE_DIR` for `create`.
- [x] 2: `micromamba_unregister_env()`, called from
      `micromamba_backend_remove_env()`.
- [x] Docs: `?remove_env`, `?get_install_dir`, `?condathis-options`,
      internal docs in `R/native_cmd.R`; NEWS 0.2.0 entry replaced.
- [x] Tests: `test-native_cmd.R` (pip rule, pip files per platform, macOS
      cache, unregister), `test-footprint.R` (removal deletes the line).
- [x] Linux: targeted tests, end-to-end check, full suite (no failures,
      no skips).
- [x] macOS (omicron) and Windows (kappa): `test-native_cmd.R` and
      `test-footprint.R` with no failures and no skips; end to end on the
      real home passes (registry unchanged through a `pip:` env; a
      registered line removed byte-exactly, CRLF and backslashes on
      Windows; macOS pip cache stays in `~/Library/Caches/pip`).

## Open

- [x] Full suite on omicron and kappa, after the concurrent run/run_bin session
  stops editing tests and functions: done with that session's rounds 5
  and 6 (2026-11-17, `../feat-run-unify/PLAN.md` "Verification"), no
  failures, no skips but one POSIX-only test on Windows.
- [x] Stale `py-mizu-env` and `py-mizu-ml-env` lines removed from the
  omicron and kappa registries (2026-11-17).
