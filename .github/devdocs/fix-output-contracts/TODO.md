# TODO: Exported-function output-type/class contract consistency

See `PLAN.md` for full rationale, the audit findings, and design decisions
behind each item below.

## Done

- [x] Full output-type/class audit of all 17 exported functions —
      identified 5 return-shape families, 2 verified-live type/failure-mode
      bugs (`list_envs()`, `list_packages()`), and several lower-priority
      asymmetries (see PLAN.md's "Secondary findings").
- [x] Fix 1: unify `create_env()`, `install_packages()`, `remove_env()`,
      `clean_cache()` around `condathis_result` (same class `run()`/
      `run_bin()` already use), including `create_env()`'s
      "already satisfied" short-circuit path.
- [x] Update `@returns` docs for all four functions.
- [x] Add `expect_s3_class(..., "condathis_result")` assertions to the
      existing success-path tests in all four test files.
- [x] Add a dedicated new test for `create_env()`'s short-circuit path
      (previously untested for its return shape specifically).
- [x] Re-verify: `test-clean_cache.R` (11/11), `test-remove_env.R`
      (13/13), `test-create_env.R` (37/37), `test-run.R` (34/34),
      `test-run_bin.R` (26/26) — all clean, no regressions from adding
      `pid`/`cmd`/`env_name` to functions that didn't have them before.
- [x] Committed as two commits: `test: extend coverage for public api
      contracts`, `feat: move all public facing internal wrappers output
      to condathis_result instead of bare lists`.

- [x] Fix 2: `run_pipeline()`'s per-process entries → real `condathis_result`.
      `processes[[i]] <- list(...)` became `new_condathis_result(...)`,
      keeping the already-real `pid` (from `proc_i$get_pid()`, unlike fix
      1's functions) and adding an honest `timeout = FALSE` (per-process
      timeouts aren't tracked). `format.condathis_pipeline()` needed no
      changes (reads fields by `$name`). New test: `res$processes[[i]]` is
      `condathis_result`-classed and `format()`/`print()` work on an
      individual stage directly. `test-run_pipeline.R` went from 82 to 88
      passing assertions, 0 failures. Committed: `feat: individual
      pipeline output slots are classed as condathis_result`.
- [x] Fix 3: `list_envs()` always raises on failure, never returns a
      numeric fallback. Replaced the `else { return(px_res$status) }`
      branch with an explicit `condathis_cmd_status_error` abort; dropped
      the misleading `@returns` sentence. New test mocks `native_cmd()`
      directly (bypassing `rethrow_error_cmd()`'s normal throw path) to
      force the previously-reachable-but-untested branch and confirms the
      new behavior. Re-verified `test-list_envs.R` (8/8) and every
      dependent file (`test-create_env.R`, `test-clean_cache.R`,
      `test-create_nested_env.R`, `test-env_exists.R`, `test-remove_env.R`)
      — all clean. Committed: `refactor: standardize list_envs output`.
- [x] Fix 4: `list_packages()` raises `condathis_cmd_status_error` instead
      of a raw `Error: object 'pkgs_df' not found`. Same shape of fix as
      fix 3, applied to `R/list_packages.R`'s equivalent failure path.
      Re-verified `test-list_packages.R` (4/4), `test-create_nested_env.R`,
      `test-create_env.R` — all clean. Committed: `fix: error when
      list_package can't run`.
- [x] `chore: just document` commit regenerated `man/*.Rd` for fixes 2–3
      via `roxygen2::roxygenize()`; a `DESCRIPTION` dev-version bump
      (`0.1.4.9003` → `0.1.4.9004`) that came along with a `roxygenize()`
      call was not reproducible on a second run and wasn't part of any
      fix's intended scope — flagged, then the user committed everything
      manually (including that version bump, deliberately) rather than
      leaving it reverted.
- [x] Full regression pass across all 10 affected/dependent test files at
      the final committed state (`run_pipeline`, `list_envs`,
      `list_packages`, `create_env`, `clean_cache`, `remove_env`,
      `create_nested_env`, `env_exists`, `run`, `run_bin`) — all clean.

All four planned fixes are now done and committed.

## Previously deferred items — now resolved

- [x] `install_micromamba()` returning a bare path instead of a
      process-result shape — **decided to keep as-is**, documented why
      rather than forced into `condathis_result`: it wraps a
      download+extract, not a single `micromamba` subprocess call, so
      there's no real `status`/`stdout`/`stderr`/`pid` to report, and
      forcing the shape would break its one genuinely useful return value
      (the installed path) for no real gain. `@returns` doc now states
      this explicitly, positioning it with `get_env_dir()`/
      `get_install_dir()`/`micromamba_bin_path()` (the path-getter family)
      instead of the process-result family.
- [x] `get_install_dir()` side-effecting (creates + guarantees existence)
      vs. `get_env_dir()`/`micromamba_bin_path()` being pure/lazy —
      **decided this is correct, intentional design**, not a bug:
      `get_install_dir()` is the root everything else is built on top of
      and must exist; `get_env_dir()`/`micromamba_bin_path()` are
      "predicted location" queries used for existence checks *before* the
      thing exists (e.g. `install_micromamba()` checks
      `fs::file_exists(micromamba_bin_path())` to decide whether to
      install). Making them consistent with each other would break one
      side or the other. Fixed the actual gap instead: `@returns` docs.
      `get_env_dir()` already said "returned even if the environment has
      not been created yet"; `micromamba_bin_path()` got the same
      treatment (didn't have it before) and now says the same, plus that
      `get_install_dir()` is the one that side-effects.
- [x] `env_exists()` silently coercing `NULL`/`NA` to `FALSE` instead of
      validating — **fixed**: now raises
      `condathis_env_exists_invalid_env_name` for `NULL`, `NA`, non-scalar,
      or non-character `env_name`, instead of silently returning `FALSE`
      indistinguishably from "that environment doesn't exist". Verified no
      internal call site ever passed an invalid `env_name` (all pass a
      real character value already), so this only affects genuinely
      invalid caller input. Updated `test-env_exists.R`'s existing test
      that had locked in the old (silent-`FALSE`) behavior. Documented as
      a breaking (minor) change in `NEWS.md`.
- [x] The `test-install_packages.R` cross-platform channel-warning flake —
      **fixed**: root cause confirmed to be `"conda-forge/label/main"`
      hosting the same packages as plain `"conda-forge"`, so which channel
      a real solve of a trivially-available package (`zlib`) records in
      history is solver tie-breaking, not something the test controls.
      Fixed by writing the second "previously used channel" directly into
      `conda-meta/history` (same line format already unit-tested in
      `test-get_env_history_channels.R`) instead of relying on a real
      install to record it — makes the warning-trigger condition fully
      deterministic. Verified with 2 consecutive clean runs (previously
      failed on the affected `expect_warning()` in roughly 1 of 3 runs).
